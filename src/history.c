#include "history.h"

#include <math.h>
#include <string.h>

void metric_history_record(metric_history_t *history, const core_snapshot_t *snapshot)
{
    if (!snapshot->sequence || history->sequence == snapshot->sequence ||
        !isfinite(snapshot->sampled_at)) return;
    metric_history_point_t point = {.time = snapshot->sampled_at, .values = {NAN, NAN, NAN}};
    if (snapshot->network.status == NETWORK_OK && !(snapshot->stale_mask & CORE_STALE_NET)) {
        point.values[HISTORY_DOWNLOAD] = snapshot->network.download;
        point.values[HISTORY_UPLOAD] = snapshot->network.upload;
    }
    if (snapshot->temperature.status == TEMPERATURE_OK && !(snapshot->stale_mask & CORE_STALE_TEMP))
        point.values[HISTORY_TEMPERATURE] = snapshot->temperature.celsius;
    if (history->count) {
        const metric_history_point_t *previous = &history->points[history->count - 1];
        if (snapshot->sampling_epoch != history->epoch || snapshot->sequence != history->sequence + 1 ||
            point.time - previous->time > snapshot->interval * 1.75)
            point.breaks = (1u << HISTORY_METRICS) - 1;
        if (strcmp(history->temperature_key, snapshot->temperature.key) != 0)
            point.breaks |= 1u << HISTORY_TEMPERATURE;
        for (int i = 0; i < HISTORY_METRICS; i++)
            if (!isfinite(previous->values[i]) || !isfinite(point.values[i])) point.breaks |= 1u << i;
    }
    history->sequence = snapshot->sequence;
    history->epoch = snapshot->sampling_epoch;
    memcpy(history->temperature_key, snapshot->temperature.key, sizeof(history->temperature_key));
    size_t expired = 0;
    while (expired < history->count && history->points[expired].time < point.time - METRIC_HISTORY_SECONDS)
        expired++;
    if (expired) {
        history->count -= expired;
        memmove(history->points, history->points + expired, history->count * sizeof(point));
    }
    /* 排序操作可能提前唤醒核心；合并过密的点仍保留断点信息。 */
    if (history->count && floor(point.time / 0.125) == floor(history->points[history->count - 1].time / 0.125)) {
        point.breaks |= history->points[history->count - 1].breaks;
        history->points[history->count - 1] = point;
    } else {
        if (history->count == METRIC_HISTORY_CAPACITY) {
            memmove(history->points, history->points + 1, (--history->count) * sizeof(point));
        }
        history->points[history->count++] = point;
    }
}

double metric_history_at(const metric_history_t *history, int metric, double time, double tolerance)
{
    if (metric < 0 || metric >= HISTORY_METRICS) return NAN;
    double distance = INFINITY, value = NAN;
    for (size_t i = 0; i < history->count; i++) {
        double delta = fabs(history->points[i].time - time);
        if (delta < distance && delta <= tolerance) {
            distance = delta;
            value = history->points[i].values[metric];
        }
    }
    return value;
}
