# 09: GUI 骨架（tracer bullet）

**What to build:** 双击 .app 打开原生窗口：Cocoa 表现层（Objective-C 源文件，C 的超集）从核心快照渲染出首个实时面板（如 CPU）；.app 的打包入口改为 GUI 应用本体（告别借 Terminal 显示）。落一条 ADR 记录 AppKit 选型。

**Blocked by:** 04

**Status:** resolved

- [x] 双击启动直达 GUI 窗口（不经 Terminal），CPU 面板随快照实时更新
- [x] 表现层不阻塞核心采样；关闭窗口正常退出
- [x] universal（x86_64 + arm64）构建仍可用；零第三方依赖
- [x] ADR 记录 AppKit 选型与理由
