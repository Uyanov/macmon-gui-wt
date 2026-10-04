# run-macmon

用标准库 `pty` 驱动 macmon 的 ncurses 端到端测试夹具。驱动不依赖 tmux、pyte
或其他第三方包，启动前先执行 `make`。

```sh
python3 .claude/skills/run-macmon/driver.py --bin ./macmon <<'EOF'
launch
wait 3.0 TASKS
size 11 6
size 100 30
expect TASKS
key q
quit
EOF
```

常用命令包括 `launch`、`ss`、`key`、`type`、`sleep`、`wait`、`expect`、`reject`、
`size`、`rate`、`raw`、`alive`、`quit` 和 `close`。`ss` 会输出并保存驱动解析后的
VT100 屏幕；模型支持备用屏幕、DECSTBM 区域滚动和中日韩宽字符。
