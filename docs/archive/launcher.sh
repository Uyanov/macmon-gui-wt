#!/bin/sh
#
# MacMonitor.app 的入口。
#
# 这个程序是 ncurses 写的 TUI，必须有真正的 tty 才能跑起来——从访达双击启动
# 的 .app 是没有终端的，newterm() 会拿到 NULL，程序只会打印一行错误就退出。
# 所以这里干的事是把真正的二进制交给 Terminal.app 去跑，然后自己立刻退出，
# 免得在 Dock 里挂着一个什么都不干的图标。
#
# 二进制路径是通过 argv 传给 osascript 的，不是拼进 AppleScript 源码里的。
# 后者要求对路径里的引号和反斜杠做转义，而那种转义在 AppleScript 字符串和
# shell 字符串两层之间很容易写错；argv 没有这个问题。

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
BIN="$HERE/macmon"

if [ ! -x "$BIN" ]; then
    osascript -e 'display alert "MacMonitor" message "应用包里的可执行文件不见了，请重新构建。" as critical'
    exit 1
fi

exec osascript - "$BIN" <<'APPLESCRIPT'
on run argv
    set binPath to item 1 of argv
    tell application "Terminal"
        activate
        -- exec 让 macmon 顶替掉 shell，于是退出时这个会话就干净地结束了，
        -- Terminal 会按它自己的设置把窗口关掉，而不是留一个空提示符。
        do script "exec " & quoted form of binPath
    end tell
end run
APPLESCRIPT
