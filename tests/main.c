/*
 * 测试 runner：收拢各测试文件经 constructor 注册的用例，逐个执行并汇报。
 * 退出码约定：全部通过 0，出现断言失败 1。
 */

#include "minitest.h"

static mt_case *g_tests;
static int      g_assert_failures;

void mt_register(const char *name, mt_test_fn fn)
{
    static mt_case pool[256];
    static int used;

    if (used >= (int)(sizeof(pool) / sizeof(pool[0]))) {
        fprintf(stderr, "测试用例数超过注册池上限\n");
        return;
    }
    mt_case *c = &pool[used++];
    c->name = name;
    c->fn = fn;
    c->next = g_tests;
    g_tests = c;
}

void mt_fail(const char *file, int line, const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    fprintf(stderr, "  %s:%d: ", file, line);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);

    g_assert_failures++;
}

int main(void)
{
    int run = 0;
    int passed = 0;

    for (mt_case *c = g_tests; c != NULL; c = c->next) {
        int before = g_assert_failures;

        c->fn();
        run++;
        if (g_assert_failures == before) {
            passed++;
            printf("PASS %s\n", c->name);
        } else {
            printf("FAIL %s\n", c->name);
        }
    }

    printf("\n%d 个测试：%d 通过，%d 失败（断言失败 %d 次）\n",
           run, passed, run - passed, g_assert_failures);
    return g_assert_failures == 0 ? 0 : 1;
}
