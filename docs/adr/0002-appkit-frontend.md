# ADR-0002: AppKit 原生前端

## 状态

已接受

## 决策

图形界面使用系统 AppKit，由 `src/gui.m` 实现；核心保持纯 C，TUI 继续由
`src/main.c` 提供。应用入口直接是 AppKit 可执行文件，不再通过 AppleScript 启动
Terminal.app。

## 原因

AppKit 是 macOS 自带框架，能在无 tty 的访达双击场景提供窗口，同时满足零第三方依赖、
universal 二进制和与 TUI 共用数据模型的要求。
