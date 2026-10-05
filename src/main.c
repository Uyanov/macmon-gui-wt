#include "core.h"
#include "ui.h"

#include <locale.h>
#include <ncurses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MIN_INTERVAL 0.25
#define MAX_INTERVAL 5.0
#define REPAINT_SECS 15
#define IDLE_TICK_MS 250
#define MIN_FRAME_SECS 0.05
#define DRAIN_MAX 64

static double now_secs(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
}

static void adjust_interval(ui_state_t *st, double factor)
{
    st->interval *= factor;
    if (st->interval < MIN_INTERVAL) st->interval = MIN_INTERVAL;
    if (st->interval > MAX_INTERVAL) st->interval = MAX_INTERVAL;
}

static int handle_key(int ch, ui_state_t *st, monitor_core_t *core, int *dirty)
{
    switch (ch) {
    case 'q': case 'Q':
        return 1;
    case '+': case '=':
        adjust_interval(st, 1.0 / 1.5);
        core_set_interval(core, st->interval);
        *dirty = 1;
        break;
    case '-': case '_':
        adjust_interval(st, 1.5);
        core_set_interval(core, st->interval);
        *dirty = 1;
        break;
    case 'c': case 'C':
        st->sort = PROC_SORT_CPU;
        core_set_sort(core, st->sort);
        *dirty = 1;
        break;
    case 'm': case 'M':
        st->sort = PROC_SORT_MEM;
        core_set_sort(core, st->sort);
        *dirty = 1;
        break;
    case ' ':
        st->paused = !st->paused;
        core_set_paused(core, st->paused);
        *dirty = 1;
        break;
    case KEY_UP: case KEY_DOWN: case KEY_RIGHT: case KEY_LEFT:
    case KEY_PPAGE: case KEY_NPAGE: case KEY_SR: case KEY_SF: case KEY_MOUSE:
    case 27:
        ui_repaint();
        *dirty = 1;
        break;
    case KEY_RESIZE:
        /* 在暂停时没有采样触发 refresh，主动让 ncurses 读取新的 pty 尺寸。 */
        resizeterm(0, 0);
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
    monitor_core_t *core;
    core_snapshot_t snap;
    ui_state_t st;
    double next_frame = 0.0;
    time_t last_repaint = time(NULL);
    uint64_t drawn_sequence = 0;
    int dirty = 1;
    int quitting = 0;

    setlocale(LC_ALL, "");
    /* 界面使用 UTF-8；兼容从 LANG=C 或未配置 locale 的终端启动。 */
    setlocale(LC_CTYPE, "en_US.UTF-8");
    memset(&st, 0, sizeof(st));
    st.interval = 1.0;
    st.sort = PROC_SORT_CPU;

    if (ui_init() != 0) {
        const char *term = getenv("TERM");
        fprintf(stderr, "macmon: 无法打开终端（TERM=%s）\n",
                term ? term : "未设置");
        return 1;
    }

    core = core_create(st.interval, st.sort);
    if (!core || core_start(core) != 0) {
        fprintf(stderr, "macmon: 无法启动采样核心\n");
        core_destroy(core);
        ui_teardown();
        return 1;
    }

    while (!quitting) {
        const double now = now_secs();
        const time_t wall = time(NULL);

        if (ui_sync_resize())
            dirty = 1;

        if (wall - last_repaint >= REPAINT_SECS) {
            ui_repaint();
            last_repaint = wall;
            dirty = 1;
        }

        if (core_snapshot(core, &snap) == 0 && snap.sequence != drawn_sequence) {
            st.interval = snap.interval;
            st.paused = snap.paused;
            st.sort = snap.sort;
            st.stale_mask = snap.stale_mask;
            memcpy(st.history, snap.history, sizeof(st.history));
            st.head = snap.history_head;
            st.len = snap.history_len;
            drawn_sequence = snap.sequence;
            dirty = 1;
        }

        if (dirty && now >= next_frame && drawn_sequence != 0) {
            ui_draw(&snap.cpu, &snap.mem, &snap.disk, snap.load, snap.uptime,
                    snap.has_fans ? &snap.fans : NULL, snap.procs,
                    snap.proc_count, snap.proc_total, &st);
            dirty = 0;
            next_frame = now + MIN_FRAME_SECS;
        }

        int timeout = IDLE_TICK_MS;
        if (dirty && next_frame > now) {
            const int until_frame = (int)((next_frame - now) * 1000.0);
            if (until_frame < timeout)
                timeout = until_frame;
        }
        if (timeout < 0)
            timeout = 0;

        int ch = ui_wait(timeout);
        if (ch == -1)
            continue;
        for (int handled = 0; ch != -1 && handled < DRAIN_MAX; handled++) {
            if (handle_key(ch, &st, core, &dirty)) {
                quitting = 1;
                break;
            }
            ch = ui_wait(0);
        }
    }

    core_destroy(core);
    ui_teardown();
    return 0;
}
