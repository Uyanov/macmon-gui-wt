#ifndef HISTORY_H
#define HISTORY_H

#include "core.h"

#define METRIC_HISTORY_CAPACITY 512
#define METRIC_HISTORY_SECONDS 60.0
enum { HISTORY_DOWNLOAD, HISTORY_UPLOAD, HISTORY_TEMPERATURE, HISTORY_METRICS };

typedef struct {
    double time;
    double values[HISTORY_METRICS];
    unsigned int breaks;             /* 本点之前不能与上一点连线 */
} metric_history_point_t;

/* GUI 持有展示历史，核心仅发布当前快照；TUI 只显示新增指标的当前读数。 */
typedef struct {
    metric_history_point_t points[METRIC_HISTORY_CAPACITY];
    size_t count;
    uint64_t sequence;
    uint64_t epoch;
    char temperature_key[5];
} metric_history_t;

void metric_history_record(metric_history_t *history, const core_snapshot_t *snapshot);
double metric_history_at(const metric_history_t *history, int metric, double time, double tolerance);

#endif
