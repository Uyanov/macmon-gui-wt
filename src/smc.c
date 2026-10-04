#include "smc.h"

#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stdio.h>
#include <string.h>

/*
 * 风扇转速是 macOS 唯一一个不通过任何公开 API 暴露的东西。唯一的入口是
 * AppleSMC 用户客户端，而它的请求结构体没有任何文档——所以下面这些结构体
 * 是手写出来的。IOConnectCallStructMethod 是原样转发这段内存的，这使字段
 * 顺序成为 ABI 的一部分：改动或重排，内核侧读到的就是垃圾。
 */
typedef char smc_bytes_t[32];

typedef struct {
    char     major;
    char     minor;
    char     build;
    char     reserved[1];
    uint16_t release;
} smc_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} smc_plimit_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char     dataAttributes;
} smc_keyinfo_t;

typedef struct {
    uint32_t       key;
    smc_vers_t     vers;
    smc_plimit_t   pLimitData;
    smc_keyinfo_t  keyInfo;
    char           result;
    char           status;
    char           data8;
    uint32_t       data32;
    smc_bytes_t    bytes;
} smc_keydata_t;

enum {
    SMC_KERNEL_INDEX     = 2,   /* 读写方法所在的 select 索引 */
    SMC_CMD_READ_BYTES   = 5,
    SMC_CMD_READ_KEYINFO = 9,
};

static io_connect_t conn;
static int          opened;
static int          fan_limits_valid;
static fan_info_t   fan_limits;

/* SMC 的 key 是四个字符按大端打包进一个 uint32。 */
static uint32_t key_to_u32(const char *key)
{
    uint32_t v = 0;

    for (int i = 0; i < 4; i++)
        v = (v << 8) | (unsigned char)key[i];
    return v;
}

static void u32_to_type(uint32_t type, char out[5])
{
    out[0] = (char)((type >> 24) & 0xff);
    out[1] = (char)((type >> 16) & 0xff);
    out[2] = (char)((type >> 8) & 0xff);
    out[3] = (char)(type & 0xff);
    out[4] = '\0';
}

static int smc_read(const char *key, uint32_t *type, uint32_t *size,
                    smc_bytes_t bytes)
{
    smc_keydata_t in;
    smc_keydata_t out;
    size_t out_size = sizeof(out);

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));

    /* 先问这个 key 长什么样，再问它的值。 */
    in.key = key_to_u32(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (IOConnectCallStructMethod(conn, SMC_KERNEL_INDEX, &in, sizeof(in),
                                  &out, &out_size) != kIOReturnSuccess)
        return -1;
    if (out.result != 0 || out.status != 0)
        return -1;

    *size = out.keyInfo.dataSize;
    *type = out.keyInfo.dataType;

    in.keyInfo.dataSize = out.keyInfo.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    out_size = sizeof(out);
    if (IOConnectCallStructMethod(conn, SMC_KERNEL_INDEX, &in, sizeof(in),
                                  &out, &out_size) != kIOReturnSuccess)
        return -1;
    if (out.result != 0 || out.status != 0)
        return -1;

    memcpy(bytes, out.bytes, sizeof(out.bytes));
    return 0;
}

/*
 * 数值有两种编码，而且同一台机器上可以混用——风扇当前转速和它的上下限
 * 未必一致。所以要按 key 自己声明的类型解码，不能统一假设成某一种。
 */
static int decode_number(uint32_t type, uint32_t size, const smc_bytes_t bytes,
                         double *out)
{
    char t[5];

    u32_to_type(type, t);

    if (memcmp(t, "flt ", 4) == 0 && size == 4) {
        float f;
        memcpy(&f, bytes, 4);   /* Intel 和 Apple Silicon 上都是小端 */
        *out = (double)f;
        return 0;
    }
    if (memcmp(t, "fpe2", 4) == 0 && size == 2) {
        *out = (double)(((unsigned int)(unsigned char)bytes[0] << 6)
                        | ((unsigned char)bytes[1] >> 2));
        return 0;
    }
    return -1;
}

int smc_open(void)
{
    io_service_t service;
    kern_return_t kr;

    /*
     * kIOMasterPortDefault 在 macOS 12 里改了名，而新写法在更老的 SDK 里
     * 不存在，所以用当前 SDK 认识的那个。
     */
#if defined(MAC_OS_VERSION_12_0) && \
    __MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_12_0
    const mach_port_t main_port = kIOMainPortDefault;
#else
    const mach_port_t main_port = kIOMasterPortDefault;
#endif

    if (opened)
        return 0;

    service = IOServiceGetMatchingService(main_port,
                                          IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL)
        return -1;   /* 虚拟机，或者一个不肯说话的 SMC */

    kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    if (kr != kIOReturnSuccess) {
        conn = IO_OBJECT_NULL;
        return -1;
    }

    opened = 1;
    fan_limits_valid = 0;
    memset(&fan_limits, 0, sizeof(fan_limits));
    return 0;
}

void smc_close(void)
{
    if (opened) {
        IOServiceClose(conn);
        conn = IO_OBJECT_NULL;
        opened = 0;
        fan_limits_valid = 0;
        memset(&fan_limits, 0, sizeof(fan_limits));
    }
}

int smc_fans(fan_info_t *out)
{
    uint32_t type;
    uint32_t size;
    smc_bytes_t bytes;
    double value;
    int count;

    memset(out, 0, sizeof(*out));
    if (!opened)
        return -1;

    if (!fan_limits_valid) {
        if (smc_read("FNum", &type, &size, bytes) != 0)
            return -1;
        count = (unsigned char)bytes[0];
        if (count > SMC_MAX_FANS)
            count = SMC_MAX_FANS;   /* Mac Pro 的风扇可能比我们画得下的多 */
        fan_limits.count = count;
        for (int i = 0; i < count; i++) {
            char key[8];
            snprintf(key, sizeof(key), "F%dMn", i);
            if (smc_read(key, &type, &size, bytes) != 0
                    || decode_number(type, size, bytes, &fan_limits.min_rpm[i]) != 0)
                return -1;
            snprintf(key, sizeof(key), "F%dMx", i);
            if (smc_read(key, &type, &size, bytes) != 0
                    || decode_number(type, size, bytes, &fan_limits.max_rpm[i]) != 0)
                return -1;
        }
        fan_limits_valid = 1;
    }

    *out = fan_limits;
    count = out->count;

    for (int i = 0; i < count; i++) {
        char key[8];

        snprintf(key, sizeof(key), "F%dAc", i);
        if (smc_read(key, &type, &size, bytes) != 0
                || decode_number(type, size, bytes, &value) != 0) {
            memset(out, 0, sizeof(*out));
            return -1;
        }
        out->rpm[i] = value;

    }
    return 0;
}
