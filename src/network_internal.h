#ifndef NETWORK_INTERNAL_H
#define NETWORK_INTERNAL_H

#include "network.h"
#include <net/if.h>

/* 系统计数器与差分计算之间的内部测试缝。 */
typedef struct {
    unsigned int index;
    char name[IFNAMSIZ];
    uint64_t received;
    uint64_t sent;
    int physical;
    int active;
} network_counter_t;

void network_update(network_sampler_t *sampler, const network_counter_t *counters,
                    size_t count, double time, network_info_t *out);

#endif
