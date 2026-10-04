# 01: 测试网骨架

**What to build:** 项目拥有零依赖的 C 单元测试设施：一个测试目录、一组断言宏、一个 `make test` 入口；先以冒烟测试证明"绿了是真绿、红了是真红"。这是后续所有重构的安全网（本票不改变任何应用行为）。

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] `make test` 一条命令跑通全部测试并返回正确退出码
- [x] 断言失败时输出失败位置与信息，退出码非零
- [x] 至少一个针对既有代码的冒烟测试通过（若既有纯计算经公开头文件不可达，则以 harness 自检替代并说明原因）
- [x] 不引入任何第三方依赖

## Comments

- 实现与验证（完成日 2026-10-02，提交见 git log）：
  - `tests/` 新增零依赖框架（constructor 自动注册 + 断言宏）与 `make test` 目标；测试直接链接被测源码，不经过 TUI 层。
  - 冒烟测试选型：经公开头文件可达的**纯计算**函数不存在（`human_bytes`、`decode_number`、排序比较器、history 环形缓冲均为文件内 static），故选 **sysinfo 公开 API** 做真实冒烟——无 tty 依赖、只读系统调用、在任何运行中的 Mac 上恒真。覆盖 5 个用例：loadavg 非负、uptime 为正、内存/磁盘不变量、CPU 百分比有界且 busy 自洽。
  - 绿路径：5/5 通过，`make test` exit=0。红路径（/tmp 临时用例故意失败）：打印 `<文件>:<行>: 断言失败：1 == 2（实际 1，期望 2）`，exit=1。
  - 编译零警告（`-Wall -Wextra`）。
