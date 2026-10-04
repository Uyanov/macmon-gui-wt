#include "core.h"

#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MIN_INTERVAL 0.25
#define MAX_INTERVAL 5.0

struct monitor_core {
    pthread_t thread;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    core_snapshot_t snapshot;
    int running;
    int started;
    int wake;
    int smc_opened;
};

static double clamp_interval(double interval)
{
    if (interval < MIN_INTERVAL) return MIN_INTERVAL;
    if (interval > MAX_INTERVAL) return MAX_INTERVAL;
    return interval;
}

static struct timespec deadline_after(double seconds)
{
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    now.tv_sec += (time_t)seconds;
    now.tv_nsec += (long)((seconds - (double)(time_t)seconds) * 1000000000.0);
    if (now.tv_nsec >= 1000000000L) {
        now.tv_sec++;
        now.tv_nsec -= 1000000000L;
    }
    return now;
}

static void history_push(core_snapshot_t *s, double value)
{
    s->history[s->history_head] = value;
    s->history_head = (s->history_head + 1) % CORE_CPU_HISTORY;
    if (s->history_len < CORE_CPU_HISTORY)
        s->history_len++;
}

static void sample_once(monitor_core_t *core)
{
    core_snapshot_t next;
    int previous_cpu_valid;
    int nprocs;
    int fan_error = 0;
    uint32_t stale;

    pthread_mutex_lock(&core->mutex);
    next = core->snapshot;
    pthread_mutex_unlock(&core->mutex);

    previous_cpu_valid = next.sequence != 0;
    stale = 0;

    if (sysinfo_cpu(&next.cpu) != 0) {
        stale |= CORE_STALE_CPU;
    } else if (!previous_cpu_valid) {
        /* The first call establishes the rate baseline, not a useful sample. */
        next.cpu.busy = 0.0;
        next.cpu.user = next.cpu.system = next.cpu.nice = 0.0;
        next.cpu.idle = 100.0;
    }

    if (sysinfo_mem(&next.mem) != 0)
        stale |= CORE_STALE_MEM;
    if (sysinfo_disk("/", &next.disk) != 0)
        stale |= CORE_STALE_DISK;
    if (sysinfo_loadavg(next.load) != 0)
        stale |= CORE_STALE_LOAD;
    if ((next.uptime = sysinfo_uptime()) < 0)
        stale |= CORE_STALE_UP;

    nprocs = proclist_sample_ex(next.procs, CORE_PROC_ROWS, next.sort,
                                &next.proc_total);
    if (nprocs < 0) {
        stale |= CORE_STALE_PROC;
    } else {
        next.proc_count = nprocs;
    }

    if (core->smc_opened) {
        if (smc_fans(&next.fans) != 0) {
            next.has_fans = 0;
            fan_error = 1;
        } else {
            next.has_fans = next.fans.count > 0;
        }
    }
    if (fan_error)
        stale |= CORE_STALE_FAN;

    /* A failed CPU sample must not duplicate the last value in the history. */
    if (!(stale & CORE_STALE_CPU) && (next.sequence != 0 || previous_cpu_valid))
        history_push(&next, next.cpu.busy);
    next.stale_mask = stale;
    next.sequence++;

    pthread_mutex_lock(&core->mutex);
    next.interval = core->snapshot.interval;
    next.sort = core->snapshot.sort;
    next.paused = core->snapshot.paused;
    core->snapshot = next;
    pthread_mutex_unlock(&core->mutex);
}

static void *sampling_thread(void *arg)
{
    monitor_core_t *core = arg;
    core->smc_opened = smc_open() == 0;
    sample_once(core);

    pthread_mutex_lock(&core->mutex);
    while (core->running) {
        if (core->snapshot.paused) {
            core->wake = 0;
            while (core->running && core->snapshot.paused && !core->wake)
                pthread_cond_wait(&core->cond, &core->mutex);
            continue;
        }
        const double interval = core->snapshot.interval;
        const struct timespec deadline = deadline_after(interval);
        core->wake = 0;
        while (core->running && !core->wake && !core->snapshot.paused) {
            if (pthread_cond_timedwait(&core->cond, &core->mutex, &deadline) == ETIMEDOUT)
                break;
        }
        const int should_sample = core->running && !core->snapshot.paused;
        pthread_mutex_unlock(&core->mutex);
        if (!core->running)
            break;
        if (should_sample)
            sample_once(core);
        pthread_mutex_lock(&core->mutex);
    }
    pthread_mutex_unlock(&core->mutex);
    return NULL;
}

monitor_core_t *core_create(double interval, proc_sort_t sort)
{
    monitor_core_t *core = calloc(1, sizeof(*core));
    if (!core)
        return NULL;
    pthread_mutex_init(&core->mutex, NULL);
    pthread_cond_init(&core->cond, NULL);
    core->snapshot.interval = clamp_interval(interval);
    core->snapshot.sort = sort;
    core->snapshot.uptime = -1;
    return core;
}

int core_start(monitor_core_t *core)
{
    if (!core || core->started)
        return -1;
    pthread_mutex_lock(&core->mutex);
    core->running = 1;
    pthread_mutex_unlock(&core->mutex);
    if (pthread_create(&core->thread, NULL, sampling_thread, core) != 0) {
        pthread_mutex_lock(&core->mutex);
        core->running = 0;
        pthread_mutex_unlock(&core->mutex);
        return -1;
    }
    core->started = 1;
    return 0;
}

void core_stop(monitor_core_t *core)
{
    if (!core || !core->started)
        return;
    pthread_mutex_lock(&core->mutex);
    core->running = 0;
    core->wake = 1;
    pthread_cond_signal(&core->cond);
    pthread_mutex_unlock(&core->mutex);
    pthread_join(core->thread, NULL);
    core->started = 0;
    smc_close();
}

void core_destroy(monitor_core_t *core)
{
    if (!core)
        return;
    core_stop(core);
    pthread_cond_destroy(&core->cond);
    pthread_mutex_destroy(&core->mutex);
    free(core);
}

static void wake_core(monitor_core_t *core)
{
    core->wake = 1;
    pthread_cond_signal(&core->cond);
}

void core_set_interval(monitor_core_t *core, double interval)
{
    if (!core) return;
    pthread_mutex_lock(&core->mutex);
    core->snapshot.interval = clamp_interval(interval);
    wake_core(core);
    pthread_mutex_unlock(&core->mutex);
}

void core_set_paused(monitor_core_t *core, int paused)
{
    if (!core) return;
    pthread_mutex_lock(&core->mutex);
    core->snapshot.paused = paused != 0;
    wake_core(core);
    pthread_mutex_unlock(&core->mutex);
}

void core_set_sort(monitor_core_t *core, proc_sort_t sort)
{
    if (!core) return;
    pthread_mutex_lock(&core->mutex);
    core->snapshot.sort = sort;
    wake_core(core);
    pthread_mutex_unlock(&core->mutex);
}

int core_snapshot(monitor_core_t *core, core_snapshot_t *out)
{
    if (!core || !out) return -1;
    pthread_mutex_lock(&core->mutex);
    *out = core->snapshot;
    pthread_mutex_unlock(&core->mutex);
    return out->sequence ? 0 : -1;
}
