# 这里用 `=` 而不是 `?=`：make 会预定义 CC，用 `?=` 的话根本不会生效。
# `make CC=...` 依然优先，因为命令行变量会覆盖这里的赋值。
CC      = clang
# 用 gnu11 而不是 c11：我们需要的那几个 POSIX 接口（clock_gettime、
# localtime_r、getloadavg、statfs）在 __STRICT_ANSI__ 下会被藏起来。
CFLAGS  ?= -std=gnu11 -O2 -g -Wall -Wextra -mmacosx-version-min=12.0
LDLIBS  := -lncurses -framework IOKit -framework CoreFoundation -lpthread

SRCDIR  := src
OBJDIR  := build
BIN     := macmon

SRCS    := $(wildcard $(SRCDIR)/*.c)
OBJS    := $(SRCS:$(SRCDIR)/%.c=$(OBJDIR)/%.o)
DEPS    := $(OBJS:.o=.d)

all: $(BIN)

$(BIN): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LDLIBS)

$(OBJDIR)/%.o: $(SRCDIR)/%.c | $(OBJDIR)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

$(OBJDIR):
	@mkdir -p $(OBJDIR)

# ---- 打包成 MacMonitor.app ----
#
# macOS 的 .app 是一个结构固定的目录。当前入口是 AppKit GUI；TUI 仍由根目录的
# macmon 二进制提供，供终端用户直接运行。

VERSION  := 1.0.0
BUILD    := 1
APP      := MacMonitor.app
CONTENTS := $(APP)/Contents

# 通用二进制：本机是 Intel，但做出来的 .app 拿到 Apple Silicon 上也该能跑。
# 单独用一份目标文件，免得把默认的 make 产物也变成胖二进制。
ARCHES   := -arch x86_64 -arch arm64
CORE_SRCS := $(SRCDIR)/core.c $(SRCDIR)/proclist.c $(SRCDIR)/smc.c $(SRCDIR)/sysinfo.c
UNIOBJS  := $(CORE_SRCS:$(SRCDIR)/%.c=$(OBJDIR)/universal/%.o)
GUIOBJ   := $(OBJDIR)/universal/gui.o
APPICON  := $(CONTENTS)/Resources/MacMonitor.icns

app: $(APP)

$(APP): $(CONTENTS)/MacOS/MacMonitor \
        $(CONTENTS)/Info.plist \
        $(CONTENTS)/PkgInfo \
        $(APPICON)
	@# 先给嵌套的可执行文件签名，再签整包——包的内容一变签名就作废，顺序不能反。
	@# Apple Silicon 上未签名的可执行文件根本不会被加载，所以这一步不是可选的；
	@# 用 ad-hoc 签名（-s -）就够，本机自己用不需要开发者证书。
	codesign --force --sign - --timestamp=none $(CONTENTS)/MacOS/MacMonitor
	codesign --force --sign - --timestamp=none $(APP)
	@echo "==> $(APP) 已生成，双击即可运行"

$(OBJDIR)/universal/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(ARCHES) -MMD -MP -c $< -o $@

$(GUIOBJ): $(SRCDIR)/gui.m
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(ARCHES) -fobjc-arc -MMD -MP -c $< -o $@

$(CONTENTS)/MacOS/MacMonitor: $(GUIOBJ) $(UNIOBJS)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(ARCHES) -fobjc-arc -o $@ $(GUIOBJ) $(UNIOBJS) $(LDLIBS) -framework Cocoa

$(CONTENTS)/Info.plist: packaging/Info.plist
	@mkdir -p $(dir $@)
	sed -e 's/@VERSION@/$(VERSION)/g' -e 's/@BUILD@/$(BUILD)/g' $< > $@

$(CONTENTS)/PkgInfo:
	@mkdir -p $(dir $@)
	printf 'APPL????' > $@

$(APPICON): packaging/make-icon.py
	@mkdir -p $(dir $@)
	python3 $< $(OBJDIR)/MacMonitor.iconset
	iconutil -c icns $(OBJDIR)/MacMonitor.iconset -o $@

# AddressSanitizer + UndefinedBehaviorSanitizer。macOS 上没有 LeakSanitizer：
# ASAN_OPTIONS=detect_leaks=1 不会去查泄漏，而是让程序在启动那一刻直接中止。
# 直接编译到独立的 $(SANBIN)，不写共享的 build/：否则 ASan 目标文件会污染普通
# 构建，之后 make 空转、改源码后链接失败（见 .scratch/audit-2026-10-02.md #9）。
SANBIN  := macmon-sanitize
sanitize: CFLAGS += -fsanitize=address,undefined -fno-omit-frame-pointer
sanitize: $(SANBIN)

$(SANBIN): $(SRCS)
	$(CC) $(CFLAGS) -o $@ $(SRCS) $(LDLIBS)

# ---- 测试 ----
# 零依赖单元测试：测试直接链接被测源码（不经过 TUI 层）。
# 核心采样模块与 sysinfo 一起直接链接，测试不经过 TUI 层。
TESTBIN  := $(OBJDIR)/test_macmon
TESTSRCS := $(wildcard tests/*.c)
TESTDEPS := $(SRCDIR)/sysinfo.c $(SRCDIR)/proclist.c $(SRCDIR)/smc.c $(SRCDIR)/core.c

test: $(TESTBIN)
	@./$(TESTBIN)

$(TESTBIN): $(TESTSRCS) $(TESTDEPS) | $(OBJDIR)
	$(CC) $(CFLAGS) -I$(SRCDIR) -o $@ $(TESTSRCS) $(TESTDEPS) $(LDLIBS)

# AppKit 测试需要已登录的图形会话，覆盖真正的窗口关闭与事件池清理。
GUITESTBIN := $(OBJDIR)/test_gui_lifecycle
test-gui: $(GUITESTBIN)
	./$(GUITESTBIN) close 0.1
	./$(GUITESTBIN) close 1.2
	./$(GUITESTBIN) drain 0.1
	./$(GUITESTBIN) drain 1.2
	./$(GUITESTBIN) quit 1.2

$(GUITESTBIN): tests/test_gui_lifecycle.m $(SRCDIR)/gui.m $(wildcard $(SRCDIR)/*.h) $(UNIOBJS)
	$(CC) $(CFLAGS) -fobjc-arc -I$(SRCDIR) -o $@ $< $(UNIOBJS) $(LDLIBS) -framework Cocoa

clean:
	rm -rf $(OBJDIR) $(BIN) $(APP) $(SANBIN)

.PHONY: all app clean sanitize test test-gui

-include $(DEPS) $(UNIOBJS:.o=.d) $(GUIOBJ:.o=.d)
