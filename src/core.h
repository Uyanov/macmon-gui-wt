#ifndef CORE_H
#define CORE_H

#include "proclist.h"
#include "smc.h"
#include "sysinfo.h"

#include <stdint.h>

#define CORE_CPU_HISTORY 60
#define CORE_PROC_ROWS   64

enum {
    CORE_STALE_CPU  = 1u << 0,
    CORE_STALE_MEM  = 1u << 1,
    CORE_STALE_DISK = 1u << 2,
    CORE_STALE_LOAD = 1u << 3,
    CORE_STALE_UP   = 1u << 4,
    CORE_STALE_PROC = 1u << 5,
    CORE_STALE_FAN  = 1u << 6,
};

typedef struct {
    cpu_usage_t cpu;
    mem_usage_t mem;
    disk_usage_t disk;
    double load[3];
    long uptime;
    fan_info_t fans;
    int has_fans;
    proc_info_t procs[CORE_PROC_ROWS];
    int proc_count;
    int proc_total;
    double history[CORE_CPU_HISTORY];
    int history_head;
    int history_len;
    double interval;
    proc_sort_t sort;
    int paused;
    uint32_t stale_mask;
    uint64_t sequence;
} core_snapshot_t;

typedef struct monitor_core monitor_core_t;

monitor_core_t *core_create(double interval, proc_sort_t sort);
int core_start(monitor_core_t *core);
void core_stop(monitor_core_t *core);
void core_destroy(monitor_core_t *core);
void core_set_interval(monitor_core_t *core, double interval);
void core_set_paused(monitor_core_t *core, int paused);
void core_set_sort(monitor_core_t *core, proc_sort_t sort);
int core_snapshot(monitor_core_t *core, core_snapshot_t *out);

#endif
