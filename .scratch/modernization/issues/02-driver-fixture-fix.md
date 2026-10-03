# 02: pty 驱动夹具修复

**What to build:** 测试夹具（run-macmon 的 pty 驱动）修掉两类已证实的假阳性根源：终端区域滚动（DECSTBM）模型缺失、CJK 字符宽度计数错误。修好后，审计期间误报的"帧损坏/错位"场景重放不再产生假阳性，夹具可被信任用于后续回归测试。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 审计场景的字节流重放不再出现行序错乱/数值异常类假阳性
- [ ] 既有驱动功能不回退（launch/ss/key/wait/expect/reject/size/rate/quit 等命令照常工作）
- [ ] CJK 宽度处理正确（中文界面元素不引起布局误判）
- [ ] 不引入新的运行时依赖（标准库范围内）
