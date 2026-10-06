#include "network_internal.h"

#include <SystemConfiguration/SystemConfiguration.h>
#include <math.h>
#include <net/if_media.h>
#include <net/route.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/sockio.h>
#include <sys/sysctl.h>
#include <time.h>
#include <unistd.h>

struct network_sampler {
    network_counter_t *previous;
    size_t count;
    double time;
    int have_previous;
};

network_sampler_t *network_create(void) { return calloc(1, sizeof(network_sampler_t)); }

void network_reset(network_sampler_t *sampler)
{
    if (!sampler) return;
    free(sampler->previous);
    memset(sampler, 0, sizeof(*sampler));
}

void network_destroy(network_sampler_t *sampler)
{
    network_reset(sampler);
    free(sampler);
}

void network_update(network_sampler_t *sampler, const network_counter_t *counters,
                    size_t count, double time, network_info_t *out)
{
    *out = (network_info_t){.status = NETWORK_ERROR};
    if (!sampler || !isfinite(time) || (count && !counters)) return;
    size_t active = 0;
    for (size_t i = 0; i < count; i++)
        if (counters[i].physical && counters[i].active) active++;
    network_counter_t *current = active ? calloc(active, sizeof(*current)) : NULL;
    if (active && !current) { network_reset(sampler); return; }
    size_t n = 0;
    for (size_t i = 0; i < count; i++)
        if (counters[i].physical && counters[i].active) current[n++] = counters[i];

    const double elapsed = time - sampler->time;
    int baseline = !sampler->have_previous || elapsed <= 0 || active != sampler->count;
    double received = 0, sent = 0;
    for (size_t i = 0; i < active && !baseline; i++) {
        const network_counter_t *before = NULL;
        for (size_t j = 0; j < sampler->count; j++) {
            if (current[i].index == sampler->previous[j].index &&
                strcmp(current[i].name, sampler->previous[j].name) == 0) {
                before = &sampler->previous[j];
                break;
            }
        }
        if (!before || current[i].received < before->received || current[i].sent < before->sent) {
            baseline = 1;
            break;
        }
        received += (double)(current[i].received - before->received);
        sent += (double)(current[i].sent - before->sent);
    }
    free(sampler->previous);
    sampler->previous = current;
    sampler->count = active;
    sampler->time = time;
    sampler->have_previous = 1;
    if (!active) out->status = NETWORK_NO_LINK;
    else if (baseline) out->status = NETWORK_WARMUP;
    else {
        out->download = received / elapsed;
        out->upload = sent / elapsed;
        out->status = NETWORK_OK;
    }
}

static int physical_interface(CFArrayRef interfaces, const char *name)
{
    for (CFIndex i = 0; i < CFArrayGetCount(interfaces); i++) {
        SCNetworkInterfaceRef interface = (SCNetworkInterfaceRef)CFArrayGetValueAtIndex(interfaces, i);
        CFStringRef type = SCNetworkInterfaceGetInterfaceType(interface);
        if (!type || !(CFEqual(type, kSCNetworkInterfaceTypeEthernet) ||
                      CFEqual(type, kSCNetworkInterfaceTypeIEEE80211) ||
                      CFEqual(type, kSCNetworkInterfaceTypeFireWire))) continue;
        CFStringRef bsd = SCNetworkInterfaceGetBSDName(interface);
        char candidate[IFNAMSIZ];
        if (bsd && CFStringGetCString(bsd, candidate, sizeof(candidate), kCFStringEncodingUTF8) &&
            strcmp(candidate, name) == 0) return 1;
    }
    return 0;
}

static int active_interface(int socket_fd, const char *name, int flags)
{
    if ((flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING) || (flags & IFF_LOOPBACK))
        return 0;
    struct ifmediareq media = {0};
    snprintf(media.ifm_name, sizeof(media.ifm_name), "%s", name);
    if (socket_fd >= 0 && ioctl(socket_fd, SIOCGIFMEDIA, &media) == 0 &&
        (media.ifm_status & IFM_AVALID)) return (media.ifm_status & IFM_ACTIVE) != 0;
    return 1;
}

void network_sample(network_sampler_t *sampler, network_info_t *out)
{
    *out = (network_info_t){.status = NETWORK_ERROR};
    CFArrayRef interfaces = SCNetworkInterfaceCopyAll();
    char *buffer = NULL;
    network_counter_t *counters = NULL;
    int socket_fd = -1;
    if (!interfaces) goto failed;
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t size = 0;
    if (sysctl(mib, 6, NULL, &size, NULL, 0) != 0) goto failed;
    /* 接口可能在两次 sysctl 之间增加，留出余量并有限重试。 */
    int loaded = 0;
    for (int attempt = 0; attempt < 3; attempt++) {
        free(buffer);
        buffer = malloc(size + 4096);
        if (!buffer) goto failed;
        size += 4096;
        if (sysctl(mib, 6, buffer, &size, NULL, 0) == 0) { loaded = 1; break; }
    }
    if (!loaded) goto failed;
    counters = calloc(size / sizeof(struct if_msghdr2) + 1, sizeof(*counters));
    if (!counters) goto failed;
    socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    size_t count = 0;
    for (size_t offset = 0; offset < size;) {
        struct { unsigned short length; unsigned char version, type; } header;
        if (size - offset < sizeof(header)) goto failed;
        memcpy(&header, buffer + offset, sizeof(header));
        if (header.length < sizeof(header) || header.length > size - offset) goto failed;
        if (header.type == RTM_IFINFO2) {
            struct if_msghdr2 message;
            if (header.length < sizeof(message)) goto failed;
            memcpy(&message, buffer + offset, sizeof(message));
            network_counter_t *counter = &counters[count];
            if (if_indextoname(message.ifm_index, counter->name)) {
                counter->index = message.ifm_index;
                counter->physical = physical_interface(interfaces, counter->name);
                counter->active = counter->physical && active_interface(socket_fd, counter->name, message.ifm_flags);
                counter->received = message.ifm_data.ifi_ibytes;
                counter->sent = message.ifm_data.ifi_obytes;
                count++;
            }
        }
        offset += header.length;
    }
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) goto failed;
    network_update(sampler, counters, count, now.tv_sec + now.tv_nsec / 1e9, out);
    goto cleanup;
failed:
    network_reset(sampler);
cleanup:
    if (socket_fd >= 0) close(socket_fd);
    free(counters);
    free(buffer);
    if (interfaces) CFRelease(interfaces);
}

const char *network_status_text(network_status_t status)
{
    switch (status) {
    case NETWORK_OK: return "实时流量";
    case NETWORK_WARMUP: return "正在采样";
    case NETWORK_NO_LINK: return "无网络连接";
    case NETWORK_ERROR: return "读取失败";
    }
    return "不可用";
}

void network_format_rate(double rate, char *out, size_t size)
{
    if (!isfinite(rate) || rate < 0) { snprintf(out, size, "不可用"); return; }
    if (rate >= 1e6) snprintf(out, size, "%.1f MB/s", rate / 1e6);
    else if (rate >= 1e3) snprintf(out, size, "%.1f KB/s", rate / 1e3);
    else snprintf(out, size, "%.0f B/s", rate);
}
