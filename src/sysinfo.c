#include "sysinfo.h"

#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/machine.h>
#include <mach/processor_info.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <sys/time.h>

/*
 * host_processor_info() 交回来的是 32 位的 tick 计数器。按 100Hz 算，开机
 * 大约 497 天后回绕，所以这里保留原始值、用 uint32_t 相减——即使累计值已经
 * 不对了，差值在跨回绕时仍然是正确的。
 */
static uint64_t prev_ticks[CPU_STATE_MAX];
static int      have_prev;

/* 最近一次值得上报的读数，见下面的 MIN_TICKS。 */
static cpu_usage_t last;

/*
 * 一个 tick 是 10ms（kern.clockrate: hz = 100）。两次读数如果比这还近，
 * 能拿到的 tick 总数只有个位数，busy% 于是只能落在少数几个离散值上——
 * 表现就是进度条要么 0% 要么 100%，中间什么都没有，这正是一次滚动突发
 * 曾经制造出来的东西。
 *
 * 与其上报这种东西，不如把读数和基线都按住：差分的起点不动，窗口一直
 * 变宽，直到覆盖一段有意义的时长。8 个 tick 在四核机器上是 20ms，在单核
 * 上是 80ms，都远低于界面允许你设置的下限 250ms，所以正常路径上这条永远
 * 不会触发。
 */
#define MIN_TICKS 8

static uint64_t page_size(void)
{
    static uint64_t cached;

    if (cached == 0) {
        vm_size_t ps = 0;
        if (host_page_size(mach_host_self(), &ps) != KERN_SUCCESS || ps == 0)
            ps = 4096;
        cached = ps;
    }
    return cached;
}

int sysinfo_cpu(cpu_usage_t *out)
{
    natural_t cpu_count = 0;
    processor_info_array_t info = NULL;
    mach_msg_type_number_t info_count = 0;

    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                            &cpu_count, &info, &info_count) != KERN_SUCCESS)
        return -1;

    uint64_t now[CPU_STATE_MAX] = {0, 0, 0, 0};
    const processor_cpu_load_info_t loads = (processor_cpu_load_info_t)info;
    for (natural_t cpu = 0; cpu < cpu_count; cpu++)
        for (int state = 0; state < CPU_STATE_MAX; state++)
            now[state] += loads[cpu].cpu_ticks[state];

    vm_deallocate(mach_task_self(), (vm_address_t)info,
                  info_count * sizeof(integer_t));

    memset(out, 0, sizeof(*out));

    if (!have_prev) {
        memcpy(prev_ticks, now, sizeof(now));
        have_prev = 1;
        out->idle = 100.0;
        last = *out;
        return 0;
    }

    uint64_t delta[CPU_STATE_MAX];
    uint64_t total = 0;
    for (int state = 0; state < CPU_STATE_MAX; state++) {
        delta[state] = (uint32_t)(now[state] - prev_ticks[state]);
        total += delta[state];
    }

    /*
     * tick 太少，除法没有意义。注意这里**故意不**推进基线，所以下一次调用
     * 量的是整个累积窗口，而不是眼前这一段。
     */
    if (total < MIN_TICKS) {
        *out = last;
        return 0;
    }

    memcpy(prev_ticks, now, sizeof(now));

    out->user   = 100.0 * (double)delta[CPU_STATE_USER]   / (double)total;
    out->system = 100.0 * (double)delta[CPU_STATE_SYSTEM] / (double)total;
    out->nice   = 100.0 * (double)delta[CPU_STATE_NICE]   / (double)total;
    out->idle   = 100.0 * (double)delta[CPU_STATE_IDLE]   / (double)total;
    out->busy   = out->user + out->system + out->nice;

    last = *out;
    return 0;
}

int sysinfo_mem(mem_usage_t *out)
{
    uint64_t ram = 0;
    size_t len = sizeof(ram);

    if (sysctlbyname("hw.memsize", &ram, &len, NULL, 0) != 0)
        return -1;

    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                          (host_info64_t)&vm, &count) != KERN_SUCCESS)
        return -1;

    const uint64_t ps = page_size();

    /*
     * 口径对齐活动监视器的"已用内存"：应用内存 + 联动内存 + 已压缩内存。
     * 应用内存取的是进程实际申请的匿名页；可清除页要减掉，因为内核随时能把
     * 它们收回去，不该算作占用。
     */
    const uint64_t app = vm.internal_page_count > vm.purgeable_count
                       ? vm.internal_page_count - vm.purgeable_count
                       : 0;

    memset(out, 0, sizeof(*out));
    out->total      = ram;
    out->app        = app * ps;
    out->wired      = (uint64_t)vm.wire_count * ps;
    out->compressed = (uint64_t)vm.compressor_page_count * ps;
    out->cached     = (uint64_t)vm.external_page_count * ps;
    out->free       = (uint64_t)vm.free_count * ps;

    struct xsw_usage swap;
    len = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &len, NULL, 0) == 0) {
        out->swap_total = swap.xsu_total;
        out->swap_used  = swap.xsu_used;
    }
    return 0;
}

int sysinfo_disk(const char *path, disk_usage_t *out)
{
    struct statfs fs;

    if (statfs(path, &fs) != 0)
        return -1;

    out->total = (uint64_t)fs.f_blocks * (uint64_t)fs.f_bsize;
    out->avail = (uint64_t)fs.f_bavail * (uint64_t)fs.f_bsize;
    /* f_bfree 计入了留给 root 的块，所以"已用"从它推出来而不是从 f_bavail
       推——否则 total 就不等于 used + avail 了。 */
    out->used  = out->total - (uint64_t)fs.f_bfree * (uint64_t)fs.f_bsize;
    return 0;
}

int sysinfo_loadavg(double avg[3])
{
    return getloadavg(avg, 3) == 3 ? 0 : -1;
}

long sysinfo_uptime(void)
{
    struct timeval boot;
    struct timeval now;
    size_t len = sizeof(boot);

    if (sysctlbyname("kern.boottime", &boot, &len, NULL, 0) != 0)
        return -1;
    if (gettimeofday(&now, NULL) != 0)
        return -1;
    return (long)(now.tv_sec - boot.tv_sec);
}
