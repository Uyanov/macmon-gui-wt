#ifndef PROCLIST_H
#define PROCLIST_H

#include <stdint.h>
#include <sys/types.h>

#define PROC_NAME_MAX 64

typedef enum {
    PROC_SORT_CPU,
    PROC_SORT_MEM,
    PROC_SORT_CPU_ASC,
    PROC_SORT_MEM_ASC,
    PROC_SORT_DEFAULT, /* 沿用 CPU 降序；GUI 不显示排序箭头。 */
} proc_sort_t;

typedef struct {
    pid_t    pid;
    char     name[PROC_NAME_MAX];
    double   cpu;      /* 占单个核心的百分比，可以超过 100 */
    uint64_t mem;      /* 常驻内存字节数 */
    uint64_t cpu_ns;   /* 累计 CPU 时间，供下次采样算速率 */
} proc_info_t;

/*
 * 给进程表拍一张快照，按 sort 对全部可读进程排序，再将前 max 项写进 out。只返回当前
 * 用户有权查看的进程——root 身份下是全部，否则只有自己的。
 *
 * 和 sysinfo_cpu() 一样，cpu 是速率，因此需要间隔已知的两次调用；第一次调用
 * 会把每个进程都报成 0。
 *
 * 返回写入的条目数，失败返回 -1。
 */
int proclist_sample_ex(proc_info_t *out, int max, proc_sort_t sort,
                       int *total_out);

/* 兼容旧调用方；返回写入 out 的条目数。 */
int proclist_sample(proc_info_t *out, int max, proc_sort_t sort);

/* 对已有读数排序，支持前端在下一次采样前立即响应列标题点击。相同占用按 PID 升序。 */
void proclist_sort(proc_info_t *procs, int count, proc_sort_t sort);

#endif
