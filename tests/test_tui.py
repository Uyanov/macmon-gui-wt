"""在真实伪终端中检查新增指标，以及暂停时缩放后恢复绘制。"""

import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import termios
import time
from pathlib import Path


def drain(fd, seconds):
    data = bytearray()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], max(0, min(0.1, deadline - time.monotonic())))
        if ready:
            try:
                data.extend(os.read(fd, 65536))
            except OSError:
                break
    return bytes(data)


def resize(fd, process, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    process.send_signal(signal.SIGWINCH)


def setup_terminal():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


def main():
    root = Path(__file__).resolve().parent.parent
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    process = subprocess.Popen(
        [os.environ.get("MACMON_BINARY", str(root / "macmon"))], stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "LANG": "en_US.UTF-8"},
        close_fds=True,
        preexec_fn=setup_terminal,
    )
    os.close(slave)
    try:
        labels = ("网络", "下载", "上传", "温度", "CPU 60秒")
        trend_labels = ("下载 60秒", "上传 60秒", "温度 60秒")
        initial = bytearray()
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            initial.extend(drain(master, 0.2))
            text = initial.decode("utf-8", errors="replace")
            if all(label in text for label in labels):
                break
        for label in labels:
            assert label in text, f"缺少终端指标：{label}"
        assert not any(label in text for label in trend_labels), "网络和温度仅显示读数"
        os.write(master, b" ")
        paused = drain(master, 0.8)
        assert "已暂停" in paused.decode("utf-8", errors="replace"), "暂停状态"
        os.write(master, b"m")
        drain(master, 0.3)
        resize(master, process, 24, 11)
        small = drain(master, 1.2)
        assert "终端太小" in small.decode("utf-8", errors="replace"), "窄窗口提示"
        resize(master, process, 24, 80)
        restored = drain(master, 1.2).decode("utf-8", errors="replace")
        assert "网络" in restored and "温度" in restored, "暂停时放大恢复指标"
        assert "内存↓" in restored, "内存降序快捷键"
        assert not any(label in restored for label in trend_labels), "恢复后不显示新增趋势"
        os.write(master, b"c")
        drain(master, 0.3)
        resize(master, process, 20, 46)
        narrow = drain(master, 1.2).decode("utf-8", errors="replace")
        assert "下载" in narrow and "温度" in narrow, "最小列宽显示指标"
        assert "CPU%↓" in narrow, "CPU 降序快捷键"
        os.write(master, b" ")
        drain(master, 0.3)
        os.write(master, b"q")
        # 退出前持续消费屏幕输出，避免伪终端写缓冲反过来阻塞主循环。
        deadline = time.monotonic() + 5
        while process.poll() is None and time.monotonic() < deadline:
            drain(master, 0.1)
        process.wait(timeout=1)
        assert process.returncode == 0, "终端正常退出"
        print("通过：终端仅显示网络与温度读数、CPU 历史、排序快捷键、暂停缩放恢复和最小列宽")
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=3)
        os.close(master)


if __name__ == "__main__":
    main()
