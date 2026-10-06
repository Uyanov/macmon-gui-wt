#ifndef UI_H
#define UI_H

#include "proclist.h"
#include "network.h"
#include "smc.h"
#include "sysinfo.h"

#define CPU_HISTORY 60

typedef struct {
    double      history[CPU_HISTORY];  /* 近期 CPU 占用率的环形缓冲 */
    int         head;                  /* 下一个要写入的槽位 */
    int         len;                   /* 已经填了多少个槽位 */
    double      interval;              /* 两次采样之间的秒数 */
    int         paused;
    proc_sort_t sort;
    uint32_t    stale_mask;
} ui_state_t;

/*
 * 强制下一帧重写每一个单元格。当 ncurses 之外的力量可能移动或改动了画面
 * 时调用它——最常见的就是终端滚动了视口。
 */
void ui_repaint(void);

/* 成功返回 0，终端无法初始化时返回 -1。 */
int  ui_init(void);
void ui_teardown(void);

/* 最多等待 timeout_ms 毫秒等一个按键。没有按键就返回 -1。 */
int  ui_wait(int timeout_ms);
int  ui_sync_resize(void);

/* fans 可以为 NULL，那样就一行风扇都不画。 */
void ui_draw(const cpu_usage_t *cpu, const mem_usage_t *mem,
             const disk_usage_t *disk, const double load[3], long uptime,
             const fan_info_t *fans, const proc_info_t *procs, int nprocs,
             const network_info_t *network, const temperature_info_t *temperature,
             int total_procs,
             const ui_state_t *st);

#endif
