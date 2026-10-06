#include "minitest.h"
#include "smc_internal.h"
#include <math.h>
#include <string.h>

static uint32_t type_code(const char *type) {
    return ((uint32_t)(unsigned char)type[0] << 24) | ((uint32_t)(unsigned char)type[1] << 16) |
           ((uint32_t)(unsigned char)type[2] << 8) | (unsigned char)type[3];
}

MT_TEST(temperature_decodes_signed_fixed_point_and_rejects_bad_data) {
    char bytes[32] = {0x3f, 0x62};
    double value;
    MT_EXPECT_EQ_INT(smc_decode_number(type_code("sp78"), 2, bytes, &value), 0);
    MT_EXPECT(fabs(value - 63.3828125) < 1e-9);
    bytes[0] = (char)0xff; bytes[1] = (char)0x80;
    MT_EXPECT_EQ_INT(smc_decode_number(type_code("sp78"), 2, bytes, &value), 0);
    MT_EXPECT(value == -0.5);
    float number = 75.5f;
    memcpy(bytes, &number, sizeof(number));
    MT_EXPECT_EQ_INT(smc_decode_number(type_code("flt "), 4, bytes, &value), 0);
    MT_EXPECT(value == 75.5);
    number = NAN; memcpy(bytes, &number, sizeof(number));
    MT_EXPECT_EQ_INT(smc_decode_number(type_code("flt "), 4, bytes, &value), -1);
    number = INFINITY; memcpy(bytes, &number, sizeof(number));
    MT_EXPECT_EQ_INT(smc_decode_number(type_code("flt "), 4, bytes, &value), -1);
    MT_EXPECT_EQ_INT(smc_decode_number(type_code("sp78"), 1, bytes, &value), -1);
    MT_EXPECT_EQ_INT(smc_decode_number(type_code("ui16"), 2, bytes, &value), -1);
}

typedef struct { unsigned int available; int invalid; } sensor_fixture_t;
static const char *sensor_keys[] = {"TCAD", "TC0D", "Tp09", "TC0E", "TC0F", "TC0P"};
static int fixture_read(void *context, const char *key, uint32_t *type, uint32_t *size, char bytes[32]) {
    sensor_fixture_t *fixture = context;
    for (int i = 0; i < 6; i++) {
        if (strcmp(key, sensor_keys[i]) == 0 && (fixture->available & (1u << i))) {
            *type = type_code(fixture->invalid ? "xxxx" : "sp78"); *size = 2;
            bytes[0] = 50 + i; bytes[1] = 0;
            return 0;
        }
    }
    return -1;
}

MT_TEST(temperature_priority_fallback_and_failures_preserve_identity) {
    sensor_fixture_t fixture = {.available = 63};
    temperature_info_t result = {0};
    const temperature_source_t sources[] = {TEMPERATURE_PACKAGE, TEMPERATURE_DIODE, TEMPERATURE_CORE,
        TEMPERATURE_VIRTUAL, TEMPERATURE_FILTERED, TEMPERATURE_PROXIMITY};
    for (int i = 0; i < 6; i++) {
        smc_read_temperature(fixture_read, &fixture, "Tp09", &result);
        MT_EXPECT_EQ_INT(result.status, TEMPERATURE_OK);
        MT_EXPECT_EQ_INT(result.source, sources[i]);
        MT_EXPECT(strcmp(result.key, sensor_keys[i]) == 0);
        MT_EXPECT(result.celsius == 50 + i);
        fixture.available &= ~(1u << i);
    }
    smc_read_temperature(fixture_read, &fixture, NULL, &result);
    MT_EXPECT_EQ_INT(result.status, TEMPERATURE_ERROR);
    MT_EXPECT(strcmp(result.key, "TC0P") == 0);
    MT_EXPECT(isnan(result.celsius));
    smc_read_temperature(fixture_read, &fixture, NULL, &result);
    MT_EXPECT_EQ_INT(result.status, TEMPERATURE_ERROR);
    result = (temperature_info_t){0};
    smc_read_temperature(fixture_read, &fixture, NULL, &result);
    MT_EXPECT_EQ_INT(result.status, TEMPERATURE_UNAVAILABLE);
    fixture.available = 63; fixture.invalid = 1;
    smc_read_temperature(fixture_read, &fixture, NULL, &result);
    MT_EXPECT_EQ_INT(result.status, TEMPERATURE_UNAVAILABLE);
    MT_EXPECT(isnan(result.celsius));
}
