#include "minitest.h"
#include "network_internal.h"
#include <math.h>
#include <string.h>

MT_TEST(network_rates_use_elapsed_time_and_64_bit_per_interface_deltas) {
    network_sampler_t *sampler = network_create();
    network_info_t result;
    network_counter_t counters[] = {
        {1, "en0", UINT64_C(1) << 40, UINT64_C(1) << 41, 1, 1},
        {2, "en1", 100000, 200000, 1, 1},
        {3, "utun0", 50000, 60000, 0, 1},
        {4, "en2", 100, 200, 1, 0},
        {5, "lo0", 10000, 10000, 0, 1}
    };
    network_update(sampler, counters, 5, 10, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_WARMUP);
    counters[0].received += 2000; counters[0].sent += 1000;
    counters[1].received += 4000; counters[1].sent += 3000;
    counters[2].received += 9999999; counters[4].sent += 9999999;
    network_update(sampler, counters, 5, 12, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_OK);
    MT_EXPECT(fabs(result.download - 3000) < 1e-9);
    MT_EXPECT(fabs(result.upload - 2000) < 1e-9);
    network_update(sampler, counters, 5, 12.25, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_OK);
    MT_EXPECT(result.download == 0 && result.upload == 0);
    network_destroy(sampler);
}

MT_TEST(network_topology_resets_and_pause_require_new_baselines) {
    network_sampler_t *sampler = network_create();
    network_info_t result;
    network_counter_t counters[] = {{1, "en0", 1000, 1000, 1, 1}, {2, "en1", 5000000, 6000000, 1, 1}};
    network_update(sampler, counters, 1, 1, &result);
    network_update(sampler, counters, 2, 2, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_WARMUP);
    network_update(sampler, counters, 2, 3, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_OK);
    network_update(sampler, counters, 1, 4, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_WARMUP);
    counters[0].received = 0;
    network_update(sampler, counters, 1, 5, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_WARMUP);
    counters[0].index = 6; strcpy(counters[0].name, "en6");
    network_update(sampler, counters, 1, 6, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_WARMUP);
    network_reset(sampler);
    counters[0].received = 10000000;
    network_update(sampler, counters, 1, 100, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_WARMUP);
    counters[0].received += 100;
    network_update(sampler, counters, 1, 101, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_OK);
    MT_EXPECT(result.download == 100);
    counters[0].active = 0;
    network_update(sampler, counters, 1, 102, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_NO_LINK);
    counters[0].active = 1;
    network_update(sampler, counters, 1, 103, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_WARMUP);
    network_update(sampler, counters, 1, 103, &result);
    MT_EXPECT_EQ_INT(result.status, NETWORK_WARMUP);
    network_destroy(sampler);
}

MT_TEST(network_status_and_decimal_units_are_unambiguous) {
    char value[32];
    network_format_rate(0, value, sizeof(value)); MT_EXPECT(strcmp(value, "0 B/s") == 0);
    network_format_rate(1500, value, sizeof(value)); MT_EXPECT(strcmp(value, "1.5 KB/s") == 0);
    network_format_rate(2500000, value, sizeof(value)); MT_EXPECT(strcmp(value, "2.5 MB/s") == 0);
    network_format_rate(NAN, value, sizeof(value)); MT_EXPECT(strcmp(value, "不可用") == 0);
    network_format_rate(-1, value, sizeof(value)); MT_EXPECT(strcmp(value, "不可用") == 0);
}

MT_TEST(network_system_sampling_has_valid_rates_or_explicit_status) {
    network_sampler_t *sampler = network_create();
    network_info_t result;
    network_sample(sampler, &result);
    MT_EXPECT(result.status != NETWORK_OK);
    network_sample(sampler, &result);
    if (result.status == NETWORK_OK)
        MT_EXPECT(isfinite(result.download) && isfinite(result.upload) && result.download >= 0 && result.upload >= 0);
    network_destroy(sampler);
}
