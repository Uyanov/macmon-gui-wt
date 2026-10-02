#ifndef SMC_H
#define SMC_H

#define SMC_MAX_FANS 4

typedef struct {
    int    count;                  /* 实际存在的风扇数，0..SMC_MAX_FANS */
    double rpm[SMC_MAX_FANS];      /* 当前转速 */
    double min_rpm[SMC_MAX_FANS];
    double max_rpm[SMC_MAX_FANS];
} fan_info_t;

/*
 * 打开 AppleSMC 服务。成功返回 0，没有可对话的对象（虚拟机）或者用户无权
 * 打开时返回 -1。完全无风扇的 Mac 在这里也会得到 0——那种情况表现为
 * smc_fans() 返回的 count == 0。
 */
int  smc_open(void);
void smc_close(void);

/*
 * 刷新风扇读数。SMC 有应答就返回 0——包括它说"没有风扇"的情况；查询本身
 * 失败才返回 -1，此时 out 会被清零。
 */
int  smc_fans(fan_info_t *out);

#endif
