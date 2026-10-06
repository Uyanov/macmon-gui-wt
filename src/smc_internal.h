#ifndef SMC_INTERNAL_H
#define SMC_INTERNAL_H

#include "smc.h"

typedef int (*smc_reader_t)(void *context, const char *key, uint32_t *type,
                          uint32_t *size, char bytes[32]);
int smc_decode_number(uint32_t type, uint32_t size, const char bytes[32], double *out);
void smc_read_temperature(smc_reader_t reader, void *context, const char *core_key,
                         temperature_info_t *out);

#endif
