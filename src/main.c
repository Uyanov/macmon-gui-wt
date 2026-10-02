#include "proclist.h"
#include "smc.h"
#include "sysinfo.h"
#include "ui.h"

#include <locale.h>
#include <ncurses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MIN_INTERVAL  0.25
#define MAX_INTERVAL  5.0
#define PROC_ROWS     64
#define PRIME_MS      200
#define REPAINT_SECS  15

/*
 * 无事可做时循环最多阻塞多久。它同时也是 15 秒兜底重绘、以及被下面帧率上限
 * 压住的画面，最晚能被画出来的延迟，所以别把它放大到一秒以上。
 */
#define IDLE_TICK_SECS 0.25

/*
 * 画面重写频率的上限。数据本身最快也就是每秒变 1/interval 次，比这更频繁
 * 到来的只可能是滚动，而滚动只是要求把画面重新同步一遍。没有这个上限的话，
 * 按键来得比画一帧还快时，就会每来一个按键整屏重画一次。
 */
#define MIN_FRAME_SECS 0.05

/*
 * 每帧处理多少个按键。一次触控板滑动是成串到达的方向键序列——远多于画面
 * 能表现出来的数量——所以把已经排队的都排空，让一帧来回应整串。上限是为了
 * 防止某个永不停歇的终端（按住不放的按键自动重复、卡住的转义序列）把重绘
 * 饿死。
 */
#define DRAIN_MAX 64

static double now_secs(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
}

static void sleep_ms(long ms)
{
    struct timespec ts;

    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

static void history_push(ui_state_t *st, double value)
{
    st->history[st->head] = value;
    st->head = (st->head + 1) % CPU_HISTORY;
    if (st->len < CPU_HISTORY)
        st->len++;
}

static void adjust_interval(ui_state_t *st, double factor)
{
    st->interval *= factor;
    if (st->interval < MIN_INTERVAL) st->interval = MIN_INTERVAL;
    if (st->interval > MAX_INTERVAL) st->interval = MAX_INTERVAL;
}

/* 返回 1 表示这个按键要求退出程序。 */
static int handle_key(int ch, ui_state_t *st, int *dirty)
{
    switch (ch) {
    case 'q': case 'Q':
        return 1;
    case '+': case '=':
        adjust_interval(st, 1.0 / 1.5);
        *dirty = 1;
        break;
    case '-': case '_':
        adjust_interval(st, 1.5);
        *dirty = 1;
        break;
    case 'c': case 'C':
        st->sort = PROC_SORT_CPU;
        *dirty = 1;
        break;
    case 'm': case 'M':
        st->sort = PROC_SORT_MEM;
        *dirty = 1;
        break;
    case ' ':
        st->paused = !st->paused;
        *dirty = 1;
        break;

    case KEY_UP: case KEY_DOWN: case KEY_PPAGE: case KEY_NPAGE:
    case KEY_SR: case KEY_SF: case KEY_MOUSE:
        /*
         * 滚动。在备用屏幕里滚轮通常以方向键或翻页键的身份到达，而它挪动的
         * 视口是 ncurses 看不见的——所以再画之前先重新同步一遍。这个标志是
         * 粘滞的、由下一帧消费，因此一整串滚动按键只花掉一次重绘，而不是
         * 每次一个。
         */
        ui_repaint();
        *dirty = 1;
        break;

    case 27:
        /*
         * 一个孤立的 ESC，或者 ncurses 没认出来的转义序列。一次被拆成两半
         * 的读取也会落到这里。
         *
         * ESC 故意**不**绑定退出，正是因为这个：它是所有转义序列的前缀，
         * 任何一个没被认出来的序列都会悄悄把程序杀掉。滚轮发出的普通模式
         * 方向键（\E[A、\E[B）曾经正属于这一类，现在由 ui_init() 里的
         * define_key() 注册掉了——"排序被滑动改掉"那个 bug 就是这么来的。
         */
        ui_repaint();
        *dirty = 1;
        break;

    case KEY_RESIZE:
        /*
         * ncurses 已经把屏幕按新尺寸调整好了，但暂停时没有任何东西会把画面
         * 重画一遍——错位的旧画面会一直挂到 15 秒的兜底重绘为止。未暂停时
         * 不需要这一手，采样本来就会把画面标脏。
         */
        ui_repaint();
        *dirty = 1;
        break;

    default:
        break;
    }
    return 0;
}

int main(void)
{
    cpu_usage_t  cpu;
    mem_usage_t  mem;
    disk_usage_t disk;
    fan_info_t   fans;
    double       load[3] = {0.0, 0.0, 0.0};
    proc_info_t  procs[PROC_ROWS];
    ui_state_t   st;
    long         uptime = -1;
    time_t       last_repaint;
    double       next_sample;
    double       next_frame = 0.0;
    int          nprocs = 0;
    int          quitting = 0;
    int          dirty = 1;

    /*
     * 风扇转速需要 SMC，虚拟机没有，加固过的系统也可能拒绝。这不是致命
     * 问题：风扇那几行直接消失，其余一切照常。
     */
    int have_smc = (smc_open() == 0);

    /* 放在 initscr() 之前，让 ncurses 拿到 locale 并画出 UTF-8。 */
    setlocale(LC_ALL, "");

    memset(&cpu, 0, sizeof(cpu));
    memset(&mem, 0, sizeof(mem));
    memset(&disk, 0, sizeof(disk));
    memset(&st, 0, sizeof(st));
    st.interval = 1.0;
    st.sort = PROC_SORT_CPU;

    if (ui_init() != 0) {
        const char *term = getenv("TERM");
        fprintf(stderr, "macmon: 无法打开终端（TERM=%s）\n",
                term ? term : "未设置");
        return 1;
    }

    /*
     * CPU 百分比和进程占用都是差分，需要间隔已知的两次采样。先空跑一对，
     * 否则第一帧满屏都是 0。
     */
    sysinfo_cpu(&cpu);
    proclist_sample(procs, PROC_ROWS, st.sort);
    sleep_ms(PRIME_MS);

    last_repaint = time(NULL);
    next_sample  = now_secs();   /* 正好在空跑那一对之后 PRIME_MS */

    while (!quitting) {
        const double now = now_secs();

        /*
         * 拖动滚动条不产生任何输入，上面那些分支一个都不会触发，所以再加
         * 一道定时兜底。redrawwin() 是原地重写，因此这点输出量不会闪。
         */
        const time_t wall = time(NULL);
        if (wall - last_repaint >= REPAINT_SECS) {
            ui_repaint();
            last_repaint = wall;
            dirty = 1;
        }

        /*
         * 采样只跟着时钟走，别的什么都不跟。
         *
         * 两个采样器报告的都是**速率**，量的是两次调用之间的间隔——见
         * proclist.h。而用 ui_wait() 的超时来给循环定节拍是给不出这个间隔
         * 的：对于一个已经缓冲好的按键，getch() 会立刻返回，于是一串输入
         * 就能把循环周期从一秒压到几毫秒，速率随之变成噪声。现在输入只决定
         * 什么时候重画。
         *
         * 截止时刻是从上一个截止时刻递推的，而不是从 now 起算，这样间隔不会
         * 被采样本身的耗时带偏；阻塞期间错过的截止时刻直接跳过而不是补跑，
         * 补跑会连着触发采样，恰恰是这里要避免的事。
         */
        if (!st.paused && now >= next_sample) {
            sysinfo_cpu(&cpu);
            sysinfo_mem(&mem);
            sysinfo_disk("/", &disk);
            if (sysinfo_loadavg(load) != 0)
                memset(load, 0, sizeof(load));
            uptime = sysinfo_uptime();

            if (have_smc && smc_fans(&fans) != 0)
                have_smc = 0;   /* SMC 不再应答，就别再问了 */

            nprocs = proclist_sample(procs, PROC_ROWS, st.sort);
            if (nprocs < 0)
                nprocs = 0;

            history_push(&st, cpu.busy);

            do {
                next_sample += st.interval;
            } while (next_sample <= now);

            dirty = 1;
        }

        /*
         * 改了间隔之后，应该在新间隔之内看到效果，而不是等旧间隔剩下来的
         * 那一段。这里只会把截止时刻往前提，所以其余每一轮都是空操作。
         */
        if (!st.paused && next_sample > now + st.interval)
            next_sample = now + st.interval;

        if (dirty && now >= next_frame) {
            ui_draw(&cpu, &mem, &disk, load, uptime,
                    have_smc ? &fans : NULL, procs, nprocs, &st);
            dirty = 0;
            next_frame = now + MIN_FRAME_SECS;
        }

        /*
         * 一直阻塞到下一件非做不可的事——一次采样、帧率上限解除、兜底重绘
         * 到点——或者某个按键到达，看哪个先来。
         */
        double wake = now + IDLE_TICK_SECS;
        if (!st.paused && next_sample < wake) wake = next_sample;
        if (dirty && next_frame < wake)       wake = next_frame;

        int timeout = (int)((wake - now_secs()) * 1000.0);
        if (timeout < 0)
            timeout = 0;

        int ch = ui_wait(timeout);
        if (ch == -1)
            continue;   /* 只是超时，不是按键 */

        for (int handled = 0; ch != -1 && handled < DRAIN_MAX; handled++) {
            if (handle_key(ch, &st, &dirty)) {
                quitting = 1;
                break;
            }
            ch = ui_wait(0);   /* 非阻塞：把已经排队的都取走 */
        }
    }

    ui_teardown();
    smc_close();
    return 0;
}
