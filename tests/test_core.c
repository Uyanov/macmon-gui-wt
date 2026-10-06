#include "minitest.h"
#include "core.h"

#include <time.h>

static void wait_ms(long ms)
{
    struct timespec ts = {ms / 1000, (ms % 1000) * 1000000L};
    nanosleep(&ts, NULL);
}

MT_TEST(core_publishes_snapshot) {
    monitor_core_t *core = core_create(0.25, PROC_SORT_CPU);
    core_snapshot_t snapshot;

    MT_EXPECT(core != NULL);
    MT_EXPECT_EQ_INT(core_start(core), 0);
    wait_ms(300);
    MT_EXPECT_EQ_INT(core_snapshot(core, &snapshot), 0);
    MT_EXPECT(snapshot.sequence > 0);
    MT_EXPECT(snapshot.proc_total >= snapshot.proc_count);
    MT_EXPECT(snapshot.proc_count <= CORE_PROC_ROWS);
    MT_EXPECT(snapshot.sampled_at > 0);
    MT_EXPECT(snapshot.network.status >= NETWORK_WARMUP && snapshot.network.status <= NETWORK_ERROR);
    core_destroy(core);
}

MT_TEST(core_resume_changes_epoch_and_rebuilds_network_baseline) {
    monitor_core_t *core = core_create(5, PROC_SORT_CPU);
    core_snapshot_t before, after;
    MT_EXPECT_EQ_INT(core_start(core), 0);
    wait_ms(200);
    MT_EXPECT_EQ_INT(core_snapshot(core, &before), 0);
    core_set_paused(core, 1);
    wait_ms(100);
    core_set_paused(core, 0);
    wait_ms(200);
    MT_EXPECT_EQ_INT(core_snapshot(core, &after), 0);
    MT_EXPECT(after.sampling_epoch == before.sampling_epoch + 1);
    MT_EXPECT(after.sampled_at > before.sampled_at);
    MT_EXPECT(after.network.status != NETWORK_OK);
    core_destroy(core);
}

MT_TEST(core_pause_preserves_snapshot) {
    monitor_core_t *core = core_create(0.25, PROC_SORT_CPU);
    core_snapshot_t before;
    core_snapshot_t after;
    core_snapshot_t stable;

    MT_EXPECT(core != NULL);
    MT_EXPECT_EQ_INT(core_start(core), 0);
    wait_ms(300);
    MT_EXPECT_EQ_INT(core_snapshot(core, &before), 0);
    core_set_paused(core, 1);
    wait_ms(100);
    MT_EXPECT_EQ_INT(core_snapshot(core, &after), 0);
    wait_ms(350);
    MT_EXPECT_EQ_INT(core_snapshot(core, &stable), 0);
    MT_EXPECT(after.paused);
    MT_EXPECT_EQ_INT((int)stable.sequence, (int)after.sequence);
    MT_EXPECT((int)after.sequence <= (int)before.sequence + 1);
    core_destroy(core);
}
