#ifndef MINITEST_H
#define MINITEST_H

/*
 * 零依赖的极简测试框架。
 *
 * 用法：在任意 tests 目录下的 .c 文件里写
 *     MT_TEST(名字) { ... MT_EXPECT(条件); ... }
 * 测试函数通过 constructor 自动注册；所有测试文件编进同一个二进制，
 * 由 tests/main.c 的 runner 依次执行。断言失败只记数、不中断，
 * 方便一次跑完看全貌。
 */

#include <stdarg.h>
#include <stdio.h>

typedef void (*mt_test_fn)(void);

typedef struct mt_case {
    const char     *name;
    mt_test_fn      fn;
    struct mt_case *next;
} mt_case;

/* 由 runner（tests/main.c）实现。 */
void mt_register(const char *name, mt_test_fn fn);
void mt_fail(const char *file, int line, const char *fmt, ...);

#define MT_TEST(name)                                                     \
    static void name(void);                                               \
    __attribute__((constructor))                                          \
    static void name##_mt_register(void) { mt_register(#name, name); }    \
    static void name(void)

#define MT_EXPECT(cond)                                                   \
    do {                                                                  \
        if (!(cond))                                                      \
            mt_fail(__FILE__, __LINE__, "断言失败：%s", #cond);           \
    } while (0)

#define MT_EXPECT_MSG(cond, ...)                                          \
    do {                                                                  \
        if (!(cond))                                                      \
            mt_fail(__FILE__, __LINE__, __VA_ARGS__);                     \
    } while (0)

#define MT_EXPECT_EQ_INT(a, b)                                            \
    do {                                                                  \
        long long mt_a_ = (long long)(a);                                 \
        long long mt_b_ = (long long)(b);                                 \
        if (mt_a_ != mt_b_)                                               \
            mt_fail(__FILE__, __LINE__,                                   \
                    "断言失败：%s == %s（实际 %lld，期望 %lld）",          \
                    #a, #b, mt_a_, mt_b_);                                \
    } while (0)

#endif
