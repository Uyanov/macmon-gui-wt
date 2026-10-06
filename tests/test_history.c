#include "minitest.h"
#include "history.h"
#include <math.h>
#include <string.h>

static core_snapshot_t sample(double time, uint64_t sequence, double interval) {
    core_snapshot_t snapshot = {.sequence = sequence, .sampled_at = time, .interval = interval,
        .network = {123, 456, NETWORK_OK}, .temperature = {60, TEMPERATURE_OK, TEMPERATURE_VIRTUAL, "TC0E"}};
    return snapshot;
}

MT_TEST(history_keeps_real_60_second_windows_at_all_refresh_rates) {
    const double intervals[] = {0.25, 1, 5};
    for (int rate = 0; rate < 3; rate++) {
        metric_history_t history = {0};
        double interval = intervals[rate];
        uint64_t sequence = 0;
        for (double time = 0; time <= 120; time += interval) {
            core_snapshot_t snapshot = sample(time, ++sequence, interval);
            metric_history_record(&history, &snapshot);
        }
        MT_EXPECT(history.count == (size_t)(60 / interval) + 1);
        MT_EXPECT(history.points[0].time == 60);
        MT_EXPECT(history.points[history.count - 1].time == 120);
        for (size_t i = 1; i < history.count; i++) MT_EXPECT(history.points[i].breaks == 0);
        core_snapshot_t duplicate = sample(120, sequence, interval);
        size_t count = history.count;
        metric_history_record(&history, &duplicate);
        MT_EXPECT(history.count == count);
    }
}

MT_TEST(history_gaps_pause_and_source_changes_do_not_join) {
    metric_history_t history = {0};
    core_snapshot_t snapshot = sample(1, 1, 1);
    metric_history_record(&history, &snapshot);
    snapshot = sample(2, 2, 1); snapshot.network.status = NETWORK_ERROR;
    metric_history_record(&history, &snapshot);
    MT_EXPECT(isnan(history.points[1].values[HISTORY_DOWNLOAD]));
    snapshot = sample(3, 3, 1);
    metric_history_record(&history, &snapshot);
    MT_EXPECT(history.points[2].breaks & (1u << HISTORY_DOWNLOAD));
    MT_EXPECT(!(history.points[2].breaks & (1u << HISTORY_TEMPERATURE)));
    snapshot = sample(4, 4, 1); strcpy(snapshot.temperature.key, "TC0P");
    metric_history_record(&history, &snapshot);
    MT_EXPECT(history.points[3].breaks & (1u << HISTORY_TEMPERATURE));
    snapshot = sample(14, 5, 1); snapshot.sampling_epoch = 1;
    metric_history_record(&history, &snapshot);
    MT_EXPECT_EQ_INT(history.points[4].breaks, 7);
    MT_EXPECT(isnan(metric_history_at(&history, HISTORY_DOWNLOAD, 8, 0.5)));
    snapshot = sample(15, 7, 1); snapshot.sampling_epoch = 1;
    metric_history_record(&history, &snapshot);
    MT_EXPECT_EQ_INT(history.points[5].breaks, 7);
    snapshot = sample(80, 8, 1); snapshot.sampling_epoch = 2;
    metric_history_record(&history, &snapshot);
    MT_EXPECT(history.count == 1 && history.points[0].time == 80);
}

MT_TEST(history_rapid_control_wakes_preserve_a_bounded_real_time_window) {
    metric_history_t history = {0};
    for (uint64_t i = 0; i <= 12000; i++) {
        core_snapshot_t snapshot = sample(i / 100.0, i + 1, 0.25);
        metric_history_record(&history, &snapshot);
    }
    MT_EXPECT(history.count >= 479 && history.count <= METRIC_HISTORY_CAPACITY);
    MT_EXPECT(history.points[0].time >= 60 && history.points[0].time < 60.25);
    MT_EXPECT(history.points[history.count - 1].time == 120);
}
