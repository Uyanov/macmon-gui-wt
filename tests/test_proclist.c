#include "minitest.h"
#include "proclist.h"

#include <string.h>

MT_TEST(process_sort_directions_and_default) {
    const proc_info_t original[] = {
        {.pid = 40, .cpu = 0, .mem = 100},
        {.pid = 10, .cpu = 0, .mem = UINT64_MAX},
        {.pid = 30, .cpu = 175, .mem = 300},
        {.pid = 20, .cpu = 35, .mem = 100},
    };
    const proc_sort_t modes[] = {PROC_SORT_DEFAULT, PROC_SORT_CPU, PROC_SORT_CPU_ASC,
        PROC_SORT_MEM, PROC_SORT_MEM_ASC};
    const pid_t expected[][4] = {
        {30, 20, 10, 40}, {30, 20, 10, 40}, {10, 40, 20, 30},
        {10, 30, 20, 40}, {20, 40, 30, 10},
    };
    for (int mode = 0; mode < 5; mode++) {
        proc_info_t rows[4];
        memcpy(rows, original, sizeof(rows));
        proclist_sort(rows, 4, modes[mode]);
        for (int i = 0; i < 4; i++)
            MT_EXPECT_EQ_INT(rows[i].pid, expected[mode][i]);
    }
}

MT_TEST(process_sort_more_than_snapshot_capacity) {
    proc_info_t rows[80];
    for (int i = 0; i < 80; i++)
        rows[i] = (proc_info_t){.pid = i + 1, .cpu = 79 - i, .mem = (uint64_t)i};
    proclist_sort(rows, 80, PROC_SORT_CPU_ASC);
    MT_EXPECT_EQ_INT(rows[0].pid, 80);
    MT_EXPECT_EQ_INT(rows[63].pid, 17);
    proclist_sort(rows, 80, PROC_SORT_MEM_ASC);
    MT_EXPECT_EQ_INT(rows[0].pid, 1);
    MT_EXPECT_EQ_INT(rows[63].pid, 64);
    proclist_sort(NULL, 0, PROC_SORT_DEFAULT);
    proclist_sort(rows, 1, PROC_SORT_CPU);
    MT_EXPECT_EQ_INT(rows[0].pid, 1);
}
