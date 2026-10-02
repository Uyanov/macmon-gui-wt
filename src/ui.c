#include "ui.h"

#include <ncurses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum {
    PAIR_GOOD = 1,
    PAIR_WARN,
    PAIR_BAD,
    PAIR_LABEL,
    PAIR_TITLE,
    PAIR_VALUE,
};

/* 由 ui_repaint() 置位，表示已知屏幕需要整屏重写。 */
static int repaint_all;

/* 进度条起始的列，以及它允许达到的最大宽度。 */
#define METER_COL 8
#define METER_MAX 44

/*
 * 数值列是百分比和风扇转速共用的，所以按两者中更宽的那个来定尺寸：
 * "  30.0%" 和 "3550 RPM" 都是八列。
 */
#define VALUE_W   8
#define VALUE_GAP 3

/* locale 能承载时用方块字形，否则退回 ASCII。 */
static const char *glyph_full  = "#";
static const char *glyph_empty = ".";
static const char *spark[8] = {"_", "-", "=", "+", "*", "#", "%", "@"};

static void pick_glyphs(void)
{
    if (MB_CUR_MAX <= 1)
        return;   /* 纯 ASCII 终端，保留退回字形 */

    glyph_full  = "\xe2\x96\x88";   /* U+2588 FULL BLOCK */
    glyph_empty = "\xe2\x96\x91";   /* U+2591 LIGHT SHADE */

    static const char *const levels[8] = {
        "\xe2\x96\x81", "\xe2\x96\x82", "\xe2\x96\x83", "\xe2\x96\x84",
        "\xe2\x96\x85", "\xe2\x96\x86", "\xe2\x96\x87", "\xe2\x96\x88",
    };
    for (int i = 0; i < 8; i++)
        spark[i] = levels[i];
}

int ui_init(void)
{
    /*
     * 用 newterm() 而不是 initscr()：initscr() 遇到不认识的终端会直接
     * 调用 exit()，调用方根本捞不着解释的机会。这样写只是返回，让 main()
     * 打印一句有用的话——TERM 没设置时这一点很重要，cron、CI、以及没有
     * 挂到 tty 上的 ssh 命令经常是那样。
     */
    if (newterm(NULL, stdout, stdin) == NULL)
        return -1;

    cbreak();
    noecho();
    curs_set(0);
    keypad(stdscr, TRUE);

    /*
     * 一个终端能发出的序列，未必都在它的 terminfo 条目里；而恰恰缺失的
     * 就是触控板会产生的那些：普通模式的方向键 \E[A .. \E[D]，也就是
     * Terminal.app 和 iTerm2 为滚轮或两指滑动发出的东西。
     *
     * ncurses 不认得它们，于是退回一个裸 ESC，再把剩下的字节当成用户手打的
     * 字符交出来——而横向滑动发出的 "\E[C" 以 'C' 结尾，那个 'C' 正好是把
     * 进程列表切成按 CPU 排序的快捷键，于是一次斜向滑动就能把表在读者眼皮
     * 底下重新洗一遍。
     *
     * 修法是把这些序列教给 ncurses；另一条路是让按键处理去猜哪些字节是
     * 残留——一旦序列被拆到两次读取里，那种猜测就没法做到可靠。
     */
    define_key("\033[A", KEY_UP);
    define_key("\033[B", KEY_DOWN);
    define_key("\033[C", KEY_RIGHT);
    define_key("\033[D", KEY_LEFT);

    if (has_colors()) {
        start_color();
        use_default_colors();
    }
    /* 单色终端上这些都是空操作，所以不必分支。 */
    init_pair(PAIR_GOOD,  COLOR_GREEN,  -1);
    init_pair(PAIR_WARN,  COLOR_YELLOW, -1);
    init_pair(PAIR_BAD,   COLOR_RED,    -1);
    init_pair(PAIR_LABEL, COLOR_CYAN,   -1);
    init_pair(PAIR_TITLE, COLOR_BLACK,  COLOR_CYAN);
    init_pair(PAIR_VALUE, COLOR_WHITE,  -1);

    pick_glyphs();
    return 0;
}

void ui_repaint(void)
{
    repaint_all = 1;
}

void ui_teardown(void)
{
    endwin();
}

int ui_wait(int timeout_ms)
{
    timeout(timeout_ms);

    const int ch = getch();
    return ch == ERR ? -1 : ch;
}

static int color_for(double pct)
{
    if (pct >= 85.0) return PAIR_BAD;
    if (pct >= 60.0) return PAIR_WARN;
    return PAIR_GOOD;
}

/*
 * ncurses 会在右边界折行，把溢出的部分涂到下一行去，所以每一段长度不定的
 * 字符串都要走下面这一对函数，按这一行实际剩下的空间裁掉。
 *
 * 返回的是 s 的最长前缀的**字节**长度，渲染出来不超过 cols 列。mvaddnstr()
 * 数的是字节，而一个方块字形是三字节一列宽，所以直接拿列预算去喂它会把这些
 * 进度条裁到三分之一长。
 */
static size_t fit_cols(const char *s, int cols)
{
    size_t i = 0;
    int used = 0;

    while (s[i] != '\0') {
        if ((s[i] & 0xc0) != 0x80) {   /* 续字节不占列 */
            if (used == cols)
                break;                 /* 已经满了，而这里正好是新字形的开头 */
            used++;
        }
        i++;
    }
    return i;
}

static void put(int row, int col, const char *s)
{
    if (row < 0 || row >= LINES || col < 0 || col >= COLS)
        return;
    mvaddnstr(row, col, s, (int)fit_cols(s, COLS - col));
}

/* 把 "[####....]" 渲染进 buf，返回它在屏幕上占的列数。 */
static int meter(char *buf, size_t cap, double pct, int width)
{
    if (pct < 0.0) pct = 0.0;
    if (pct > 100.0) pct = 100.0;

    int filled = (int)(pct / 100.0 * (double)width + 0.5);
    if (filled > width) filled = width;

    size_t len = 0;
    if (len < cap - 1) buf[len++] = '[';
    for (int i = 0; i < width && len < cap - 1; i++) {
        const char *g = i < filled ? glyph_full : glyph_empty;
        const size_t gl = strlen(g);
        if (len + gl >= cap - 1)
            break;
        memcpy(buf + len, g, gl);
        len += gl;
    }
    if (len < cap - 1) buf[len++] = ']';
    buf[len] = '\0';
    return width + 2;
}

static void human_bytes(uint64_t bytes, char *buf, size_t cap)
{
    static const char units[] = "BKMGTP";
    double v = (double)bytes;
    int u = 0;

    while (v >= 1024.0 && u < 5) {
        v /= 1024.0;
        u++;
    }
    if (u == 0 || v >= 100.0)
        snprintf(buf, cap, "%.0f%c", v, units[u]);
    else
        snprintf(buf, cap, "%.1f%c", v, units[u]);
}

static void draw_title(int cols, const ui_state_t *st)
{
    char line[256];
    char clock[16];
    const time_t t = time(NULL);
    struct tm tm;

    localtime_r(&t, &tm);
    strftime(clock, sizeof(clock), "%H:%M:%S", &tm);

    /* 那串长提示在经典 80 列终端里放不下。 */
    const char *hint = cols >= 92
        ? "q quit   +/- speed   c/m sort   space pause "
        : "q quit  +/-  c/m  space ";

    snprintf(line, sizeof(line), " MacMonitor  %s   every %.2fs%s   %s",
             clock, st->interval, st->paused ? "  [PAUSED]" : "", hint);

    attron(COLOR_PAIR(PAIR_TITLE) | A_BOLD);
    for (int x = 0; x < cols; x++)
        mvaddch(0, x, (size_t)x < strlen(line) ? (chtype)(unsigned char)line[x]
                                               : ' ');
    attroff(COLOR_PAIR(PAIR_TITLE) | A_BOLD);
}

/*
 * pct 决定进度条的长度和颜色；value 是印在它旁边的文字。风扇那行两者不同，
 * 因为它是一个转速而不是百分比，读数是 RPM。
 */
static void metric_row(int row, const char *label, double pct, int width,
                       const char *value, const char *detail)
{
    char bar[METER_MAX * 4 + 8];

    meter(bar, sizeof(bar), pct, width);

    attron(COLOR_PAIR(PAIR_LABEL) | A_BOLD);
    put(row, 1, label);
    attroff(COLOR_PAIR(PAIR_LABEL) | A_BOLD);

    attron(COLOR_PAIR(color_for(pct)));
    put(row, METER_COL, bar);
    put(row, METER_COL + width + 2, value);
    attroff(COLOR_PAIR(color_for(pct)));

    attron(COLOR_PAIR(PAIR_VALUE));
    put(row, METER_COL + width + 2 + VALUE_W + VALUE_GAP, detail);
    attroff(COLOR_PAIR(PAIR_VALUE));
}

/* 把风扇画在 row .. row + fans->count - 1 行上；返回下一行的行号。 */
static int draw_fans(int row, int width, const fan_info_t *fans)
{
    for (int i = 0; i < fans->count; i++) {
        char label[8];
        char value[16];
        char detail[64];
        const double max = fans->max_rpm[i];
        const double pct = max > 0.0 ? 100.0 * fans->rpm[i] / max : 0.0;

        if (fans->count > 1)
            snprintf(label, sizeof(label), "FAN%d", i);
        else
            snprintf(label, sizeof(label), "FAN");
        snprintf(value, sizeof(value), "%4.0f RPM", fans->rpm[i]);
        snprintf(detail, sizeof(detail), "min %.0f   max %.0f",
                 fans->min_rpm[i], max);

        metric_row(row + i, label, pct, width, value, detail);
    }
    return row + fans->count;
}

static void draw_history(int row, int cols, const ui_state_t *st)
{
    /*
     * 环形缓冲区装的是 CPU_HISTORY 个采样，而采样间隔是可变的，所以这段
     * 历史的跨度是 60 × interval 秒，不是一个固定的 60 秒。写死标签会在
     * 你把间隔调快或调慢之后说谎。
     */
    char label[16];
    snprintf(label, sizeof(label), "CPU %.0fs", CPU_HISTORY * st->interval);

    attron(COLOR_PAIR(PAIR_LABEL) | A_BOLD);
    mvaddstr(row, 1, label);
    attroff(COLOR_PAIR(PAIR_LABEL) | A_BOLD);

    int histw = cols - 12;
    if (histw > CPU_HISTORY) histw = CPU_HISTORY;
    if (histw > st->len) histw = st->len;

    int start = st->head - histw;
    while (start < 0)
        start += CPU_HISTORY;

    for (int i = 0; i < histw; i++) {
        const double v = st->history[(start + i) % CPU_HISTORY];
        int lvl = (int)(v / 100.0 * 7.0 + 0.5);
        if (lvl < 0) lvl = 0;
        if (lvl > 7) lvl = 7;

        attron(COLOR_PAIR(color_for(v)));
        mvaddstr(row, 9 + i, spark[lvl]);
        attroff(COLOR_PAIR(color_for(v)));
    }
}

static void draw_procs(int top, int avail, int cols, const proc_info_t *procs,
                       int nprocs)
{
    int namew = cols - 27;
    if (namew < 12) namew = 12;
    if (namew > 40) namew = 40;

    const int cpu_col = 9 + namew + 1;
    const int mem_col = cpu_col + 7;

    attron(COLOR_PAIR(PAIR_LABEL) | A_BOLD);
    mvprintw(top, 1, "%7s", "PID");
    mvprintw(top, 9, "%-*.*s", namew, namew, "COMMAND");
    mvprintw(top, cpu_col, "%6s", "CPU%");
    mvprintw(top, mem_col, "%8s", "MEM");
    attroff(COLOR_PAIR(PAIR_LABEL) | A_BOLD);

    if (cols > 2)
        mvhline(top + 1, 1, ACS_HLINE, cols - 2);

    if (nprocs == 0) {
        attron(COLOR_PAIR(PAIR_VALUE));
        mvaddstr(top + 2, 3, "(no processes visible)");
        attroff(COLOR_PAIR(PAIR_VALUE));
        return;
    }

    for (int i = 0; i < nprocs && i < avail; i++) {
        const proc_info_t *p = &procs[i];
        const int row = top + 2 + i;
        const int hot = p->cpu >= 25.0;
        char mem[16];

        human_bytes(p->mem, mem, sizeof(mem));

        if (hot)
            attron(COLOR_PAIR(color_for(p->cpu)) | A_BOLD);
        mvprintw(row, 1, "%7d", p->pid);
        mvprintw(row, 9, "%-*.*s", namew, namew, p->name);
        mvprintw(row, cpu_col, "%6.1f", p->cpu);
        if (hot)
            attroff(COLOR_PAIR(color_for(p->cpu)) | A_BOLD);
        mvprintw(row, mem_col, "%8s", mem);
    }
}

void ui_draw(const cpu_usage_t *cpu, const mem_usage_t *mem,
             const disk_usage_t *disk, const double load[3], long uptime,
             const fan_info_t *fans, const proc_info_t *procs, int nprocs,
             const ui_state_t *st)
{
    int rows, cols, row;
    char detail[128];

    /* 无风扇的 Mac 上没有，没有 SMC 可问的机器上也没有。 */
    const int fan_rows = (fans != NULL && fans->count > 0) ? fans->count : 0;

    getmaxyx(stdscr, rows, cols);
    if (rows < 1 || cols < 12)
        return;   /* 什么都放不下，别去动屏幕 */

    /*
     * 再小的话，固定的那几样东西（标题、四条进度条、风扇、历史、负载行、
     * 进程表头）加上两行进程就放不下了，结果会是一团被裁过的乱码，而不是
     * 同一个界面的缩小版——所以干脆明说。
     */
    if (rows < 14 + fan_rows || cols < 46) {
        erase();
        mvaddstr(rows / 2, 1, "terminal too small");
        return;
    }

    /*
     * 给进度条定宽，好让跟在其后的说明文字也放得下：8 列标签、进度条本身、
     * 百分比，以及最长的说明串（"12.4G / 16.0G   wired 2.8G   comp 320M"）
     * 都要挤在这一行里。
     */
    int width = cols - METER_COL - (2 + VALUE_W + VALUE_GAP) - 38;
    if (width > METER_MAX) width = METER_MAX;
    if (width < 10) width = 10;

    erase();

    /*
     * erase() 清空的是**虚拟**屏幕，而 refresh() 仍然只写出与 ncurses 记录
     * 的物理屏幕不同的那些单元格。终端一旦滚动，这份记录就过期了：增量更新
     * 于是把碎片画到那些已经不再持有 ncurses 以为的内容的位置上，表现出来
     * 就是进度条长度错乱。redrawwin() 逐格原地重写——不清屏，所以不闪——
     * 两边就重新一致了。
     *
     * 一整串滚动按键只会走到这里一次，因为 repaint_all 是粘滞的：main.c 把
     * 已排队的按键一次排空，再由一帧来消费它。
     */
    if (repaint_all) {
        redrawwin(stdscr);
        repaint_all = 0;
    }

    draw_title(cols, st);

    const uint64_t mem_used = mem->app + mem->wired + mem->compressed;
    const double mem_pct = mem->total
                         ? 100.0 * (double)mem_used / (double)mem->total : 0.0;
    const double swap_pct = mem->swap_total
                          ? 100.0 * (double)mem->swap_used
                                  / (double)mem->swap_total : 0.0;
    const double disk_pct = disk->total
                          ? 100.0 * (double)disk->used / (double)disk->total
                          : 0.0;

    char a[16], b[16], c[16], d[16];
    char pct[16];

    row = 1;

    snprintf(detail, sizeof(detail), "u %.1f  s %.1f  i %.1f",
             cpu->user, cpu->system, cpu->idle);
    snprintf(pct, sizeof(pct), "%7.1f%%", cpu->busy);
    metric_row(row++, "CPU", cpu->busy, width, pct, detail);

    human_bytes(mem_used, a, sizeof(a));
    human_bytes(mem->total, b, sizeof(b));
    human_bytes(mem->wired, c, sizeof(c));
    human_bytes(mem->compressed, d, sizeof(d));
    snprintf(detail, sizeof(detail), "%s / %s   wired %s   comp %s",
             a, b, c, d);
    snprintf(pct, sizeof(pct), "%7.1f%%", mem_pct);
    metric_row(row++, "MEM", mem_pct, width, pct, detail);

    human_bytes(mem->swap_used, a, sizeof(a));
    human_bytes(mem->swap_total, b, sizeof(b));
    snprintf(detail, sizeof(detail), "%s / %s", a, b);
    snprintf(pct, sizeof(pct), "%7.1f%%", swap_pct);
    metric_row(row++, "SWAP", swap_pct, width, pct, detail);

    human_bytes(disk->used, a, sizeof(a));
    human_bytes(disk->total, b, sizeof(b));
    human_bytes(disk->avail, c, sizeof(c));
    snprintf(detail, sizeof(detail), "%s / %s   free %s", a, b, c);
    snprintf(pct, sizeof(pct), "%7.1f%%", disk_pct);
    metric_row(row++, "DISK", disk_pct, width, pct, detail);

    if (fan_rows > 0)
        row = draw_fans(row, width, fans);

    row++;                              /* 空行 */
    draw_history(row++, cols, st);

    char status[128];
    if (uptime >= 0)
        snprintf(status, sizeof(status),
                 "LOAD %.2f %.2f %.2f   UP %ldd %02ldh %02ldm   TASKS %d",
                 load[0], load[1], load[2], uptime / 86400,
                 (uptime % 86400) / 3600, (uptime % 3600) / 60, nprocs);
    else
        snprintf(status, sizeof(status), "LOAD %.2f %.2f %.2f   TASKS %d",
                 load[0], load[1], load[2], nprocs);
    put(row++, 1, status);

    row++;                              /* 空行 */
    draw_procs(row, rows - (row + 2), cols, procs, nprocs);
}
