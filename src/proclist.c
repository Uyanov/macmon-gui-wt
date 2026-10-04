#include "proclist.h"

#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/*
 * 一台桌面机很少跑超过几百个进程，而采样器是单线程的，所以固定缓冲区就够
 * 了——除了那份 pid 列表本身，这个文件不做任何 malloc。
 */
#define CACHE_MAX 2048

/*
 * 内核是按大约 1ms 一个量子的粒度记账 CPU 时间的，所以远短于这个长度的
 * 窗口，基本取决于哪几个线程恰好落在窗口两端——同一个进程这次读出来是
 * 0%，下次就是好几百，拿它排序等于每帧把整张表重新洗一遍。
 *
 * 窗口太短时，沿用上一次的速率，并且把基线留在原地，让下一次调用量的是
 * 整个累积起来的窗口。100ms 远低于界面能设置的下限 250ms，所以正常路径上
 * 这条不会触发。
 */
#define MIN_ELAPSED_NS 100000000ull

static proc_info_t cached[CACHE_MAX];      /* 上一次的采样，用来算速率 */
static int         cached_len;
static proc_info_t snapshot[CACHE_MAX];    /* 暂存，每次采样复用 */
static uint64_t    prev_wall_ns;

typedef struct {
    pid_t pid;
    char  name[PROC_NAME_MAX];
} name_cache_entry_t;

static name_cache_entry_t name_cache[CACHE_MAX];
static int                 name_cache_len;

static uint64_t now_ns(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint64_t cached_cpu_ns(pid_t pid)
{
    for (int i = 0; i < cached_len; i++)
        if (cached[i].pid == pid)
            return cached[i].cpu_ns;
    return 0;
}

static double cached_cpu_pct(pid_t pid)
{
    for (int i = 0; i < cached_len; i++)
        if (cached[i].pid == pid)
            return cached[i].cpu;
    return 0.0;
}

static const char *cached_name(pid_t pid)
{
    for (int i = 0; i < name_cache_len; i++)
        if (name_cache[i].pid == pid)
            return name_cache[i].name;
    return NULL;
}

static const char *process_name(pid_t pid, char name[PROC_NAME_MAX])
{
    const char *known = cached_name(pid);
    if (known)
        return known;

    if (proc_name(pid, name, PROC_NAME_MAX) <= 0)
        snprintf(name, PROC_NAME_MAX, "(%d)", pid);

    if (name_cache_len < CACHE_MAX) {
        name_cache_entry_t *entry = &name_cache[name_cache_len++];
        entry->pid = pid;
        snprintf(entry->name, sizeof(entry->name), "%s", name);
        return entry->name;
    }
    return name;
}

static int cmp_cpu(const void *a, const void *b)
{
    const proc_info_t *x = a;
    const proc_info_t *y = b;

    if (x->cpu < y->cpu) return 1;
    if (x->cpu > y->cpu) return -1;
    return 0;
}

static int cmp_mem(const void *a, const void *b)
{
    const proc_info_t *x = a;
    const proc_info_t *y = b;

    if (x->mem < y->mem) return 1;
    if (x->mem > y->mem) return -1;
    return 0;
}

int proclist_sample_ex(proc_info_t *out, int max, proc_sort_t sort,
                       int *total_out)
{
    if (total_out)
        *total_out = 0;
    if (max <= 0)
        return 0;

    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0)
        return -1;

    /* 进程表可能在"量尺寸"和"真正取"这两次调用之间变大，所以要多要一些
       余量，而不是不多不少就要那么多。 */
    const size_t cap = (size_t)bytes * 2;
    pid_t *pids = malloc(cap);
    if (!pids)
        return -1;

    bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, (int)cap);
    if (bytes <= 0) {
        free(pids);
        return -1;
    }
    const int npid = bytes / (int)sizeof(pid_t);

    const uint64_t wall = now_ns();
    const uint64_t elapsed = prev_wall_ns ? wall - prev_wall_ns : 0;
    /* 第一次调用根本没有基线：它是来立基线的，而不是拿零长度窗口量自己。 */
    const int too_soon = prev_wall_ns != 0 && elapsed < MIN_ELAPSED_NS;
    int n = 0;

    for (int i = 0; i < npid && n < CACHE_MAX; i++) {
        const pid_t pid = pids[i];
        if (pid <= 0)
            continue;

        struct proc_taskinfo ti;
        if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, sizeof(ti))
                != (int)sizeof(ti))
            continue;   /* 已经退出，或者属于别的用户 */

        /*
         * libproc 已经把这些值从 mach 绝对时间换算过了，所以在任何架构上
         * 都是纳秒——这里不需要再做 timebase 换算。
         */
        const uint64_t cpu_ns = ti.pti_total_user + ti.pti_total_system;

        proc_info_t *p = &snapshot[n++];
        p->pid = pid;
        p->cpu_ns = cpu_ns;
        p->mem = ti.pti_resident_size;
        p->cpu = 0.0;

        if (too_soon) {
            p->cpu = cached_cpu_pct(pid);
        } else if (elapsed > 0) {
            const uint64_t before = cached_cpu_ns(pid);
            if (before > 0 && cpu_ns > before)
                p->cpu = 100.0 * (double)(cpu_ns - before) / (double)elapsed;
        }

        char name[PROC_NAME_MAX];
        const char *cached = process_name(pid, name);
        snprintf(p->name, sizeof(p->name), "%s", cached);
    }

    /*
     * 不提交基线正是让窗口变宽的原因：cached 里留着的还是旧的绝对计数器，
     * prev_wall_ns 也还是旧的起点，于是下一次调用会把两个差值都量在同一个、
     * 更长的窗口上。
     */
    if (!too_soon) {
        memcpy(cached, snapshot, sizeof(proc_info_t) * (size_t)n);
        cached_len = n;
        prev_wall_ns = wall;
    }
    free(pids);

    /* 先排整张表——排之前就截断的话，留下的只会是 pid 最小的那些，而不是
       最忙的那些。 */
    qsort(snapshot, (size_t)n, sizeof(proc_info_t),
          sort == PROC_SORT_MEM ? cmp_mem : cmp_cpu);

    if (total_out)
        *total_out = n;

    if (n > max)
        n = max;
    memcpy(out, snapshot, sizeof(proc_info_t) * (size_t)n);
    return n;
}

int proclist_sample(proc_info_t *out, int max, proc_sort_t sort)
{
    return proclist_sample_ex(out, max, sort, NULL);
}
