# NOTES — scratchpad for building the run-macmon skill

Platform check: this is a **real macOS 12.7.6 / Intel x86_64** box (MacBookAir8,2),
not a Linux container. So the "macOS-only" claim is testable here rather than
something to route around.

Tooling found:
- `clang`, `make`, `python3` (3.9.6), `expect`, `script` — present
- `tmux` — **NOT installed**, `brew` — **NOT installed**
- `pyte`, `pexpect` — **NOT installed** (no pip/network assumed)

=> The TUI example's tmux driver is unavailable. Build the driver on stdlib
   `pty` + `termios` + a hand-written VT100 screen emulator. This is strictly
   better for this app anyway: no tmux dependency, and it gives a real rendered
   screen rather than raw escape soup.

Build: `make clean && make` — clean, zero warnings with -Wall -Wextra.

## Gotchas hit while building the driver

(collecting as I go — see skill SKILL.md for the final list)
