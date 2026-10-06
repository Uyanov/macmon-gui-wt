# 历史资料归档

本目录保留早期实现资料，供追溯项目演变。

| 文件 | 原路径 | 用途 |
| --- | --- | --- |
| [run-macmon-notes.md](run-macmon-notes.md) | `NOTES.md` | 构建 pty 测试驱动时的环境检查与笔记 |
| [launcher.sh](launcher.sh) | `packaging/launcher.sh` | 旧版通过 Terminal.app 启动 TUI 的应用入口 |

笔记中的环境版本、路径和工具可用性反映记录时的状态。旧启动脚本保留原文，
依赖原应用包中与脚本同目录的 `macmon`，不适合直接从归档目录运行。
当前应用由 AppKit 可执行文件启动，打包入口见根目录 `Makefile` 的 `app` 目标。
