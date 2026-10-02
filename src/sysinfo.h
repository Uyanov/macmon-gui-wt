#ifndef SYSINFO_H
#define SYSINFO_H

#include <stdint.h>

/*
 * macOS 的整机计数器。
 *
 * 每次调用都是一个时间点上的快照。sysinfo_cpu() 额外在内部记住了上一次的
 * tick 计数，所以它报告的是**自上次调用以来**的占用率——按固定间隔轮询它，
 * 得到的才是速率。间隔不稳定，得到的就不是。
 */

typedef struct {
    double user;    /* 占全部核心的百分比 */
    double system;
    double nice;
    double idle;
    double busy;    /* user + system + nice */
} cpu_usage_t;

typedef struct {
    uint64_t total;       /* 物理内存字节数 */
    uint64_t app;         /* 进程申请的匿名页 */
    uint64_t wired;       /* 永远不会被换出的内核页 */
    uint64_t compressed;  /* 当前存放在压缩器里的页 */
    uint64_t cached;      /* 内核可以随时丢弃的文件页 */
    uint64_t free;        /* 空闲链表上的页 */
    uint64_t swap_total;
    uint64_t swap_used;
} mem_usage_t;

typedef struct {
    uint64_t total;
    uint64_t used;
    uint64_t avail;
} disk_usage_t;

int  sysinfo_cpu(cpu_usage_t *out);   /* 成功 0，失败 -1 */
int  sysinfo_mem(mem_usage_t *out);
int  sysinfo_disk(const char *path, disk_usage_t *out);
int  sysinfo_loadavg(double avg[3]);
long sysinfo_uptime(void);            /* 开机至今的秒数，失败返回 -1 */

#endif
