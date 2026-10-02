# 这里用 `=` 而不是 `?=`：make 会预定义 CC，用 `?=` 的话根本不会生效。
# `make CC=...` 依然优先，因为命令行变量会覆盖这里的赋值。
CC      = clang
# 用 gnu11 而不是 c11：我们需要的那几个 POSIX 接口（clock_gettime、
# localtime_r、getloadavg、statfs）在 __STRICT_ANSI__ 下会被藏起来。
CFLAGS  ?= -std=gnu11 -O2 -g -Wall -Wextra
LDLIBS  := -lncurses -framework IOKit -framework CoreFoundation

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
# macOS 的 .app 就是一个结构固定的目录。这里有个前提得说清楚：macmon 是
# ncurses 写的 TUI，需要真正的 tty，而从访达双击启动的 .app 是没有终端的，
# newterm() 会拿到 NULL。所以包的入口不是 macmon 自己，而是
# packaging/launcher.sh——它把真正的二进制交给 Terminal.app 去跑。

VERSION  := 1.0.0
BUILD    := 1
APP      := MacMonitor.app
CONTENTS := $(APP)/Contents

# 通用二进制：本机是 Intel，但做出来的 .app 拿到 Apple Silicon 上也该能跑。
# 单独用一份目标文件，免得把默认的 make 产物也变成胖二进制。
ARCHES   := -arch x86_64 -arch arm64
UNIOBJS  := $(SRCS:$(SRCDIR)/%.c=$(OBJDIR)/universal/%.o)

app: $(APP)

$(APP): $(CONTENTS)/MacOS/macmon $(CONTENTS)/MacOS/MacMonitor \
        $(CONTENTS)/Info.plist $(CONTENTS)/Resources/AppIcon.icns \
        $(CONTENTS)/PkgInfo
	@# 先给嵌套的可执行文件签名，再签整包——包的内容一变签名就作废，顺序不能反。
	@# Apple Silicon 上未签名的可执行文件根本不会被加载，所以这一步不是可选的；
	@# 用 ad-hoc 签名（-s -）就够，本机自己用不需要开发者证书。
	codesign --force --sign - --timestamp=none $(CONTENTS)/MacOS/macmon
	codesign --force --sign - --timestamp=none $(APP)
	@echo "==> $(APP) 已生成，双击即可运行"

$(OBJDIR)/universal/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(ARCHES) -MMD -MP -c $< -o $@

$(CONTENTS)/MacOS/macmon: $(UNIOBJS)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(ARCHES) -o $@ $(UNIOBJS) $(LDLIBS)

$(CONTENTS)/MacOS/MacMonitor: packaging/launcher.sh
	@mkdir -p $(dir $@)
	cp $< $@
	chmod +x $@

$(CONTENTS)/Info.plist: packaging/Info.plist
	@mkdir -p $(dir $@)
	sed -e 's/@VERSION@/$(VERSION)/g' -e 's/@BUILD@/$(BUILD)/g' $< > $@

$(CONTENTS)/Resources/AppIcon.icns: packaging/make-icon.py
	@mkdir -p $(dir $@)
	python3 $< $(OBJDIR)/AppIcon.iconset
	iconutil -c icns -o $@ $(OBJDIR)/AppIcon.iconset

$(CONTENTS)/PkgInfo:
	@mkdir -p $(dir $@)
	printf 'APPL????' > $@

# AddressSanitizer + UndefinedBehaviorSanitizer。macOS 上没有 LeakSanitizer：
# ASAN_OPTIONS=detect_leaks=1 不会去查泄漏，而是让程序在启动那一刻直接中止。
# 直接编译到独立的 $(SANBIN)，不写共享的 build/：否则 ASan 目标文件会污染普通
# 构建，之后 make 空转、改源码后链接失败（见 .scratch/audit-2026-10-02.md #9）。
SANBIN  := macmon-sanitize
sanitize: CFLAGS += -fsanitize=address,undefined -fno-omit-frame-pointer
sanitize: $(SANBIN)

$(SANBIN): $(SRCS)
	$(CC) $(CFLAGS) -o $@ $(SRCS) $(LDLIBS)

clean:
	rm -rf $(OBJDIR) $(BIN) $(APP) $(SANBIN)

.PHONY: all app clean sanitize

-include $(DEPS) $(UNIOBJS:.o=.d)
