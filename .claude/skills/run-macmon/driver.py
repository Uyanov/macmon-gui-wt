#!/usr/bin/env python3
"""
driver.py — launch and drive macmon (ncurses TUI) from a script.

macmon needs a real tty, and there is no tmux/pyte on a stock macOS box, so this
driver does the two things itself:

  1. spawns the binary on a pty of a known size (pty.fork + TIOCSWINSZ)
  2. keeps a VT100 screen model so `ss` can hand back *what is on the screen*
     instead of raw escape sequences

Commands are read from stdin, one per line, `#` starts a comment:

    launch              start the binary (path: --bin, default ./macmon)
    ss [label]          print the rendered screen; save to build/screens/<label>.txt
    key <name> [...]    send keys: up down left right pgup pgdn q space esc
                        enter tab bs f1..  or a single literal char
    type <text>         send literal text
    sleep <secs>        wait
    wait <secs> <re>    poll the screen until regex `re` matches (returns OK/FAIL)
    expect <re>         assert current screen matches `re`
    reject <re>         assert current screen does NOT match `re`
    size <cols> <rows>  resize the pty (TIOCSWINSZ -> SIGWINCH)
    rate <secs>         measure bytes/sec of TUI output (scroll-storm stress)
    raw [n]             print the last n raw bytes (default 300, repr'd)
    pid                 print the child pid
    alive               OK if the child is still running
    quit [secs]         send 'q', wait for exit, print exit status
    close               kill the child and clean up

Typical use (heredoc — the pattern in SKILL.md):

    python3 .claude/skills/run-macmon/driver.py <<'EOF'
    launch
    wait 3.0 busy
    key c
    ss before
    EOF
"""

import argparse
import codecs
import os
import re
import select
import signal
import struct
import sys
import time
import fcntl
import termios
import pty
import unicodedata

# --------------------------------------------------------------------------
# VT100 screen model
# --------------------------------------------------------------------------

# DEC special graphics (\E(0) -> Unicode. This matters: macmon draws the table
# rule with mvhline(ACS_HLINE), which xterm-256color renders by switching into
# this charset. Without the mapping the rule comes back as a row of 'q'.
ACS = {
    '`': '◆', 'a': '▒', 'b': '␉', 'c': '␌', 'd': '␍',
    'e': '␊', 'f': '°', 'g': '±', 'h': '␤', 'i': '␋',
    'j': '┘', 'k': '┐', 'l': '┌', 'm': '└', 'n': '┼',
    'o': '⎺', 'p': '⎻', 'q': '─', 'r': '⎼', 's': '⎽',
    't': '├', 'u': '┤', 'v': '┴', 'w': '┬', 'x': '│',
    'y': '≤', 'z': '≥', '{': 'π', '|': '≠', '}': '£',
    '~': '·',
}


class Screen:
    """Just enough of a VT100 to read a full-screen ncurses app back out."""

    def __init__(self, cols, rows):
        self.cols = cols
        self.rows = rows
        self.reset()

    def reset(self):
        c, r = self.cols, self.rows
        self.grid = [[' '] * c for _ in range(r)]
        self.x = 0
        self.y = 0
        self.wrap_pending = False
        self.charsets = ['ascii', 'ascii']   # G0, G1
        self.gl = 0                          # which one is active
        self.alt = False
        self.raw_mode = False
        self._st = 'GROUND'
        self._buf = ''
        self._priv = False
        self.scroll_top = 0
        self.scroll_bottom = self.rows - 1

    def resize(self, cols, rows):
        old = self.grid
        self.cols, self.rows = cols, rows
        self.grid = [[' '] * cols for _ in range(rows)]
        for r in range(min(rows, len(old))):
            for c in range(min(cols, len(old[r]))):
                self.grid[r][c] = old[r][c]
        self.x = min(self.x, max(0, cols - 1))
        self.y = min(self.y, max(0, rows - 1))
        self.scroll_top = 0
        self.scroll_bottom = rows - 1
        self.wrap_pending = False

    # -- low level edits ---------------------------------------------------
    def _scroll_up(self):
        top, bottom = self.scroll_top, self.scroll_bottom
        self.grid.pop(top)
        self.grid.insert(bottom, [' '] * self.cols)

    def _scroll_down(self):
        top, bottom = self.scroll_top, self.scroll_bottom
        self.grid.pop(bottom)
        self.grid.insert(top, [' '] * self.cols)

    def _put(self, ch):
        if self.wrap_pending:
            self.wrap_pending = False
            self.x = 0
            self.y += 1
            if self.y > self.scroll_bottom:
                self.y = self.scroll_bottom
                self._scroll_up()
        if self.charsets[self.gl] == 'acs':
            ch = ACS.get(ch, ch)
        if 0 <= self.y < self.rows and 0 <= self.x < self.cols:
            self.grid[self.y][self.x] = ch
        width = 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
        if width == 2 and self.x + 1 < self.cols:
            self.grid[self.y][self.x + 1] = ' '
        if self.x >= self.cols - width:
            self.wrap_pending = True      # deferred wrap, xterm behaviour
        else:
            self.x += width

    def _params(self, raw, default=0):
        raw = raw.lstrip('?')
        if not raw:
            return [default]
        out = []
        for p in raw.split(';'):
            try:
                out.append(int(p) if p else default)
            except ValueError:
                out.append(default)
        return out

    # -- the parser --------------------------------------------------------
    def feed(self, text):
        for ch in text:
            self._feed1(ch)

    def _feed1(self, ch):
        st = self._st

        if st == 'GROUND':
            o = ord(ch)
            if ch == '\x1b':
                self._st = 'ESC'
            elif ch == '\r':
                self.x = 0
                self.wrap_pending = False
            elif ch in '\n\x0b\x0c':
                self.wrap_pending = False
                self.y += 1
                if self.y > self.scroll_bottom:
                    self.y = self.scroll_bottom
                    self._scroll_up()
            elif ch == '\b':
                self.x = max(0, self.x - 1)
                self.wrap_pending = False
            elif ch == '\t':
                self.x = min(self.cols - 1, (self.x // 8 + 1) * 8)
                self.wrap_pending = False
            elif ch == '\x0e':            # SO -> G1
                self.gl = 1
            elif ch == '\x0f':            # SI -> G0
                self.gl = 0
            elif o < 0x20:
                pass                       # \a and friends
            else:
                self._put(ch)
            return

        if st == 'ESC':
            if ch == '[':
                self._buf = ''
                self._priv = False
                self._st = 'CSI'
            elif ch == '(':
                self._st = 'G0'
            elif ch == ')':
                self._st = 'G1'
            elif ch == 'M':                # reverse index
                if self.y == self.scroll_top:
                    self._scroll_down()
                else:
                    self.y -= 1
                self._st = 'GROUND'
            elif ch == 'D':                # index
                self._feed1('\n')
                self._st = 'GROUND'
            elif ch == 'E':                # next line
                self.x = 0
                self._feed1('\n')
                self._st = 'GROUND'
            elif ch == '7':                # save cursor
                self._saved = (self.x, self.y)
                self._st = 'GROUND'
            elif ch == '8':                # restore cursor
                if getattr(self, '_saved', None):
                    self.x, self.y = self._saved
                self._st = 'GROUND'
            elif ch == 'c':                # RIS
                self.reset()
            else:
                self._st = 'GROUND'
            return

        if st == 'G0':
            self.charsets[0] = 'acs' if ch == '0' else 'ascii'
            self._st = 'GROUND'
            return

        if st == 'G1':
            self.charsets[1] = 'acs' if ch == '0' else 'ascii'
            self._st = 'GROUND'
            return

        if st == 'CSI':
            o = ord(ch)
            if ch == '?' and not self._buf:
                self._priv = True
                return
            if 0x20 <= o <= 0x3f:
                self._buf += ch
                return
            if 0x40 <= o <= 0x7e:
                self._csi(ch, self._buf)
                self._st = 'GROUND'
            else:
                self._st = 'GROUND'
            return

    def _csi(self, final, raw):
        p = self._params(raw)
        n = p[0]
        self.wrap_pending = False

        if final in 'Hf':
            row = (p[0] if p[0] else 1) - 1
            col = (p[1] if len(p) > 1 and p[1] else 1) - 1
            self.y = max(0, min(self.rows - 1, row))
            self.x = max(0, min(self.cols - 1, col))
        elif final == 'A':
            self.y = max(0, self.y - max(1, n))
        elif final == 'B':
            self.y = min(self.rows - 1, self.y + max(1, n))
        elif final == 'C':
            self.x = min(self.cols - 1, self.x + max(1, n))
        elif final == 'D':
            self.x = max(0, self.x - max(1, n))
        elif final == 'G':
            self.x = max(0, min(self.cols - 1, max(1, n) - 1))
        elif final == 'd':
            self.y = max(0, min(self.rows - 1, max(1, n) - 1))
        elif final == 'J':
            if n == 2:
                self.grid = [[' '] * self.cols for _ in range(self.rows)]
            elif n == 1:
                for r in range(self.y):
                    self.grid[r] = [' '] * self.cols
                for c in range(self.x + 1):
                    self.grid[self.y][c] = ' '
            else:
                for c in range(self.x, self.cols):
                    self.grid[self.y][c] = ' '
                for r in range(self.y + 1, self.rows):
                    self.grid[r] = [' '] * self.cols
        elif final == 'K':
            if n == 2:
                self.grid[self.y] = [' '] * self.cols
            elif n == 1:
                for c in range(self.x + 1):
                    self.grid[self.y][c] = ' '
            else:
                for c in range(self.x, self.cols):
                    self.grid[self.y][c] = ' '
        elif final == 'X':
            for c in range(self.x, min(self.cols, self.x + max(1, n))):
                self.grid[self.y][c] = ' '
        elif final == 'L':
            for _ in range(max(1, n)):
                self.grid.insert(self.y, [' '] * self.cols)
                self.grid.pop()
        elif final == 'M':
            for _ in range(max(1, n)):
                self.grid.pop(self.y)
                self.grid.append([' '] * self.cols)
        elif final == 'P':
            row = self.grid[self.y]
            del row[self.x:self.x + max(1, n)]
            self.grid[self.y] = row + [' '] * (self.cols - len(row))
        elif final == '@':
            row = self.grid[self.y]
            row[self.x:self.x] = [' '] * max(1, n)
            self.grid[self.y] = row[:self.cols]
        elif final == 'S':
            for _ in range(max(1, n)):
                self._scroll_up()
        elif final == 'T':
            for _ in range(max(1, n)):
                self._scroll_down()
        elif final == 'r':
            top = (p[0] if p[0] else 1) - 1
            bottom = (p[1] if len(p) > 1 and p[1] else self.rows) - 1
            if 0 <= top < bottom < self.rows:
                self.scroll_top, self.scroll_bottom = top, bottom
            self.x = 0
            self.y = self.scroll_top
        elif final in 'hl' and self._priv:
            # ?1049 alternate screen, ?25 cursor visibility — tracked, not drawn
            if n == 1049:
                self.alt = (final == 'h')
            elif n == 25:
                self.raw_mode = (final == 'l')
        # 'm' (SGR) and everything else: no visual effect here

    # -- output ------------------------------------------------------------
    def text(self, keep_blank=False):
        lines = [''.join(r).rstrip() for r in self.grid]
        if not keep_blank:
            while lines and not lines[-1]:
                lines.pop()
        return '\n'.join(lines)


# --------------------------------------------------------------------------
# pty session
# --------------------------------------------------------------------------

class Session:
    def __init__(self, binary, cols, rows, utf8=True, env_extra=None):
        self.binary = os.path.abspath(binary)
        self.cols = cols
        self.rows = rows
        self.utf8 = utf8
        self.env_extra = env_extra or {}
        self.cols_now, self.rows_now = cols, rows
        self.screen = Screen(cols, rows)
        self.raw = bytearray()
        self.total_bytes = 0
        self.pid = None
        self.fd = None
        self.status = None
        self._dec = codecs.getincrementaldecoder('utf-8')(errors='replace')
        self._dead = False

    def launch(self):
        pid, fd = pty.fork()
        if pid == 0:
            # Child: become macmon.
            try:
                os.environ['TERM'] = 'xterm-256color'
                if self.utf8:
                    os.environ['LANG'] = 'en_US.UTF-8'
                    os.environ['LC_ALL'] = 'en_US.UTF-8'
                else:
                    os.environ['LANG'] = 'C'
                    os.environ['LC_ALL'] = 'C'
                os.environ.update(self.env_extra)
                os.execv(self.binary, [self.binary])
            except Exception as e:                      # pragma: no cover
                os.write(2, ('exec failed: %s\n' % e).encode())
                os._exit(127)
        self.pid, self.fd = pid, fd
        self.set_size(self.cols, self.rows)
        # The child needs a moment to reach newterm() before we start polling.
        time.sleep(0.4)
        self.pump(0.2)
        return self

    def set_size(self, cols, rows):
        self.cols_now, self.rows_now = cols, rows
        if self.fd is not None:
            fcntl.ioctl(self.fd, termios.TIOCSWINSZ,
                        struct.pack('HHHH', rows, cols, 0, 0))
        if self.screen.cols != cols or self.screen.rows != rows:
            self.screen.resize(cols, rows)

    def pump(self, timeout=0.15):
        """Drain available output into the screen model. Returns bytes read."""
        if self._dead or self.fd is None:
            return 0
        got = 0
        deadline = time.time() + timeout
        while True:
            remaining = max(0.0, deadline - time.time())
            try:
                r, _, _ = select.select([self.fd], [], [], remaining)
            except (OSError, ValueError):
                self._dead = True
                break
            if not r:
                break
            try:
                data = os.read(self.fd, 65536)
            except OSError:
                # EIO on macOS = the child closed the pty
                self._dead = True
                break
            if not data:
                self._dead = True
                break
            got += len(data)
            self.total_bytes += len(data)
            self.raw.extend(data)
            del self.raw[:-8192]
            self.screen.feed(self._dec.decode(data))
        self._reap()
        return got

    def sample_rate(self, secs):
        """Bytes/sec over `secs`, pumping the whole time. For scroll storms."""
        start = time.time()
        total = 0
        while time.time() - start < secs:
            total += self.pump(0.05)
        return total / max(1e-6, (time.time() - start))

    def drain(self, secs):
        """Pump for a fixed wall-clock duration regardless of output."""
        end = time.time() + secs
        while time.time() < end:
            self.pump(min(0.1, max(0.0, end - time.time())))

    def wait_for(self, pattern, timeout):
        rx = re.compile(pattern)
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.1)
            if rx.search(self.screen.text()):
                return True
            if self._dead and self.status is not None:
                return bool(rx.search(self.screen.text()))
        return bool(rx.search(self.screen.text()))

    def send(self, data):
        if self.fd is None or self._dead:
            return False
        os.write(self.fd, data)
        return True

    def _reap(self):
        if self.status is None and self.pid is not None:
            try:
                done, st = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError:
                self.status = 0
                return
            if done == self.pid:
                self.status = st

    def wait_exit(self, timeout=5.0):
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.1)
            self._reap()
            if self.status is not None:
                return self.status
        return None

    def close(self):
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None
        if self.pid is not None and self.status is None:
            try:
                os.kill(self.pid, signal.SIGKILL)
                os.waitpid(self.pid, 0)
            except (ProcessLookupError, ChildProcessError, OSError):
                pass
        self._dead = True


# --------------------------------------------------------------------------
# key names
# --------------------------------------------------------------------------

KEYS = {
    'up': b'\x1b[A', 'down': b'\x1b[B', 'right': b'\x1b[C', 'left': b'\x1b[D',
    'pgup': b'\x1b[5~', 'pgdn': b'\x1b[6~', 'home': b'\x1b[H', 'end': b'\x1b[F',
    'enter': b'\r', 'cr': b'\r', 'tab': b'\t', 'bs': b'\x7f',
    'esc': b'\x1b', 'space': b' ',
    'shift-up': b'\x1b[1;2A', 'shift-down': b'\x1b[1;2B',
    'shift-right': b'\x1b[1;2C', 'shift-left': b'\x1b[1;2D',
    'mouse-scroll-up': b'\x1b[M`!!', 'mouse-scroll-down': b'\x1b[Mb!!',
    'f1': b'\x1bOP', 'f2': b'\x1bOQ',
    'sgr-mouse': b'\x1b[<64;10;5M',          # modern SGR mouse wheel
}


def encode_key(tok):
    low = tok.lower()
    if low in KEYS:
        return KEYS[low]
    if len(tok) == 1:
        return tok.encode()
    raise ValueError('unknown key %r' % tok)


# --------------------------------------------------------------------------
# REPL
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--bin', default='./macmon')
    ap.add_argument('--cols', type=int, default=100)
    ap.add_argument('--rows', type=int, default=30)
    ap.add_argument('--ascii', action='store_true',
                    help='run with LANG=C so macmon uses its ASCII fallback glyphs')
    ap.add_argument('--screens', default='build/screens',
                    help='screen capture directory (default: build/screens)')
    args = ap.parse_args()

    s = Session(args.bin, args.cols, args.rows, utf8=not args.ascii)
    launcher = None

    def out(msg=''):
        sys.stdout.write(msg + '\n')
        sys.stdout.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        cmd, _, rest = line.partition(' ')
        rest = rest.strip()
        try:
            if cmd == 'launch':
                if not os.path.exists(s.binary):
                    out('ERROR: %s not found — run `make` first' % s.binary)
                    continue
                if launcher is None:
                    launcher = s
                s.launch()
                out('OK pid=%d size=%dx%d' % (s.pid, s.cols_now, s.rows_now))

            elif cmd == 'ss':
                s.pump(0.25)
                label = rest or 'screen'
                os.makedirs(args.screens, exist_ok=True)
                path = os.path.join(args.screens, label + '.txt')
                body = s.screen.text()
                with open(path, 'w') as f:
                    f.write(body + '\n')
                out('--- screen (%dx%d alt=%s cursor=%d,%d) -> %s'
                    % (s.screen.cols, s.screen.rows, s.screen.alt, s.screen.x, s.screen.y, path))
                out(body)
                out('--- end screen')

            elif cmd == 'key':
                toks = rest.split()
                if not toks:
                    out('ERROR: key needs an argument')
                    continue
                try:
                    data = b''.join(encode_key(t) for t in toks)
                except ValueError as e:
                    out('ERROR: %s' % e)
                    continue
                s.send(data)
                out('OK sent %r' % data)

            elif cmd == 'type':
                s.send(rest.encode())
                out('OK typed %r' % rest)

            elif cmd == 'sleep':
                s.drain(float(rest or '1'))
                out('OK')

            elif cmd == 'wait':
                secs, _, pat = rest.partition(' ')
                ok = s.wait_for(pat, float(secs or '3'))
                out('OK' if ok else 'FAIL: /%s/ not on screen within %ss'
                    % (pat, secs))
                if not ok:
                    out(s.screen.text())

            elif cmd in ('expect', 'reject'):
                s.pump(0.2)
                hit = bool(re.search(rest, s.screen.text()))
                ok = hit if cmd == 'expect' else not hit
                out('OK' if ok else 'FAIL: %s /%s/' % (cmd, rest))
                if not ok:
                    out(s.screen.text())

            elif cmd == 'size':
                c, _, r = rest.partition(' ')
                s.set_size(int(c), int(r))
                s.drain(0.6)
                out('OK resized to %sx%s' % (c, r))

            elif cmd == 'rate':
                secs = float(rest or '2')
                bps = s.sample_rate(secs)
                out('OK %.0f bytes/sec over %.1fs' % (bps, secs))

            elif cmd == 'raw':
                n = int(rest or '300')
                out(repr(bytes(s.raw[-n:])))

            elif cmd == 'pid':
                out('OK pid=%s' % s.pid)

            elif cmd == 'alive':
                s.pump(0.1)
                s._reap()
                out('OK alive' if s.status is None else 'OK exited=%s'
                    % _describe(s.status))

            elif cmd == 'quit':
                secs = float(rest or '5')
                s.send(b'q')
                st = s.wait_exit(secs)
                out('OK exited=%s' % (_describe(st) if st is not None
                                      else 'TIMEOUT (still running)'))

            elif cmd == 'close':
                s.close()
                out('OK closed')

            else:
                out('ERROR: unknown command %r' % cmd)

        except Exception as e:
            out('ERROR: %s: %s' % (type(e).__name__, e))

    s.close()
    return 0


def _describe(st):
    if st is None:
        return 'None'
    if os.WIFEXITED(st):
        return 'exit %d' % os.WEXITSTATUS(st)
    if os.WIFSIGNALED(st):
        return 'signal %d' % os.WTERMSIG(st)
    return str(st)


if __name__ == '__main__':
    sys.exit(main())
