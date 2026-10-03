# 13: 分发与文档一致性

**What to build:** 分发收官：二进制最低系统版本与 Info.plist 声明一致（12.0）；Terminal 借道机制随 GUI 入口落地而退役，并在 README 说明；Gatekeeper 放行指引改为递归（xattr -dr）；run-macmon 的悬空 SKILL.md 引用处理（补全或移除）；README 的 external_page_count 叙述修正。

**Blocked by:** 09

**Status:** ready-for-agent

- [ ] vtool 显示的 minos 与声明一致
- [ ] 首次打开指引与现实一致（含递归去隔离；不再涉及已退役机制）
- [ ] 无悬空引用；README 无已知不实叙述
