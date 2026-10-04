/*
 * sysinfo 公开 API 的冒烟测试：直接打真实系统调用，验证返回值与基本不变量。
 * 这些断言在任何一台运行中的 Mac 上都应恒真，不依赖 tty / ncurses。
 */

#include "minitest.h"
#include "sysinfo.h"

#include <math.h>

MT_TEST(sysinfo_loadavg_returns_three_nonneg) {
    double avg[3] = {-1.0, -1.0, -1.0};

    MT_EXPECT_EQ_INT(sysinfo_loadavg(avg), 0);
    for (int i = 0; i < 3; i++) {
        MT_EXPECT(avg[i] >= 0.0);
        /* 顺手排除 inf / NaN（NaN 与任何数比较都是 false） */
        MT_EXPECT(avg[i] < 1.0e6);
    }
}

MT_TEST(sysinfo_uptime_is_valid_or_unavailable) {
    /* 受限测试环境可能拒绝 kern.boottime；成功时结果必须非负。 */
    const long uptime = sysinfo_uptime();
    MT_EXPECT(uptime == -1 || uptime >= 0);
}

MT_TEST(sysinfo_mem_invariants) {
    mem_usage_t m;

    MT_EXPECT_EQ_INT(sysinfo_mem(&m), 0);
    MT_EXPECT(m.total > 0);
    MT_EXPECT(m.swap_used <= m.swap_total);
}

MT_TEST(sysinfo_disk_root_invariants) {
    disk_usage_t d;

    MT_EXPECT_EQ_INT(sysinfo_disk("/", &d), 0);
    MT_EXPECT(d.total > 0);
    MT_EXPECT(d.used <= d.total);
    MT_EXPECT(d.avail <= d.total);
}

MT_TEST(sysinfo_cpu_percentages_bounded) {
    cpu_usage_t c;

    MT_EXPECT_EQ_INT(sysinfo_cpu(&c), 0);

    const double fields[4] = {c.user, c.system, c.nice, c.idle};
    for (int i = 0; i < 4; i++)
        MT_EXPECT(fields[i] >= 0.0 && fields[i] <= 100.0);

    /* busy 定义为三者之和，必须与分量自洽 */
    MT_EXPECT(fabs(c.busy - (c.user + c.system + c.nice)) < 1.0e-9);
}
