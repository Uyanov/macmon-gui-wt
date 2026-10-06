#ifndef NETWORK_H
#define NETWORK_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    NETWORK_WARMUP = 0,
    NETWORK_OK,
    NETWORK_NO_LINK,
    NETWORK_ERROR
} network_status_t;

typedef struct {
    double download;
    double upload;
    network_status_t status;
} network_info_t;

typedef struct network_sampler network_sampler_t;
network_sampler_t *network_create(void);
void network_destroy(network_sampler_t *sampler);
void network_reset(network_sampler_t *sampler);
void network_sample(network_sampler_t *sampler, network_info_t *out);
const char *network_status_text(network_status_t status);
void network_format_rate(double rate, char *out, size_t size);

#endif
