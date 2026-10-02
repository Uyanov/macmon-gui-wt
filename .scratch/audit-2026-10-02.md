# macmon 缺陷与优化候选清单

> 来源：多代理审计工作流（run `wf_becd5f93-a35`，50 个代理，2026-10-02）。所有缺陷条目经对抗性验证（每条由两名独立怀疑者尝试驳倒，分歧加终审）。项目根：`/Users/mac/Desktop/demo/macmon`（下文 file:line 相对该根；"已记录"指是否已进 README/CHANGELOG 等文档）

## 已确认缺陷

### High

**1. 缩到 <12 列再放大后永久停止渲染（ui_draw 早退死锁）** — src/ui.c:364 ｜ high ｜ 已记录 否

- 证据：三份独立发现（ui-early-return-resize-wedge / resize-under-12-cols-permanent-blank / f1-resize-freeze）同根因：`rows<1 || cols<12` 的早退分支不触碰屏幕；本环境 ncurses 5.7 只在刷新路径消化 SIGWINCH，此后窗口永不被 touch → 尺寸永不更新 → 放大后所有 SIGWINCH/按键/15s 兜底全被吞，0 字节输出直至重启。12 列及以上（走 too-small 分支、会 erase）可恢复；lldb 读冻死进程 getmaxx=8、手动 resizeterm 立即恢复；外部 WINCH 无效；独立字节计数探针复现，非驱动伪影。f1 的一条验证意见修正为 medium，其余维持 high。
- 复现：driver.py：`launch → size 11 6 → sleep 1 → size 100 30 → rate 2` → 0 B/s（12x6 对照 620-1670 B/s）。

### Medium

**2. 状态行 TASKS 恒定截断为 64** — src/main.c:230 ｜ medium ｜ 否

- 证据：proclist_sample 返回 min(可见进程数, PROC_ROWS=64)（proclist.c:157-159），ui.c:459/461 直接显示；本机 332-348 可见进程恒显 "TASKS 64"（README:14 同）；全工程无第二处统计。
- 复现：在 >64 可见进程的机器运行 ./macmon，TASKS 恒为 64。

**3. 暂停 + 改窗口：旧画面陈旧 10-15 秒（KEY_RESIZE 修复未生效）** — src/main.c:125 ｜ medium ｜ 否（CHANGELOG:64 过度承诺）

- 证据：暂停后 resize，首个输出在启动后 ~15s（墙钟兜底 main.c:200），首帧仍按旧 100 列绘制、约 52ms 后才正确 60 列。机制修正：KEY_RESIZE 并非常说的"从未送达"，而是挂起 SIGWINCH 要等下一次 doupdate 才被消化并投递，暂停时无刷新故执行太晚；未暂停时每秒重绘察觉不到（≤0.9s）。验证意见一条建议降 low、一条维持 medium。
- 复现：启动 → 空格暂停 → pty 100x30→60x20 → 静默至 ~15s 后恢复正确布局。

**4. Info.plist 声明最低 10.13，实际二进制 minos 12.0** — packaging/Info.plist:35 ｜ medium ｜ 否

- 证据：Makefile 全程无 -mmacosx-version-min；vtool 实测两 slice 均 minos 12.0/sdk 13.1（clang 默认取构建机主版本）；10.13–11.x 上 launcher 能起、嵌套 exec macmon 被 dyld 拒绝；arm64 也被迫排除 Big Sur 11.0。
- 复现：make app && vtool -show-build MacMonitor.app/Contents/MacOS/macmon。

**5. 打包应用经 Apple events 驱动 Terminal：TCC 自动化授权未文档化** — packaging/launcher.sh:24 ｜ medium ｜ 否

- 证据：`exec osascript -` 向 Terminal 发 do script；10.14+ 需自动化授权；Info.plist 缺 NSAppleEventsUsageDescription；失败无兜底（仅"二进制缺失"有 alert）；README:43/58-60 只谈 Gatekeeper。验证对"弹框 vs 静默拒绝"细节有分歧，结论不变。
- 复现：未实际触发（避免在用户桌面弹授权框），为代码+平台机制论证。

**6. README 的 xattr 建议不递归，嵌套二进制仍可能被隔离** — README.md:60 ｜ medium ｜ 否

- 证据：真实执行体是 Contents/MacOS/macmon（Makefile:61-63），由 Terminal 单独 exec；quarantine 会传播到包内文件，`xattr -d` 只清包根；ad-hoc 签名过不了 spctl。验证分歧 2/3 确认（实测带隔离属性副本 exec 被闸/挂起），1/3 驳回（认为按 bundle 整体评估、包根才是闸门）；建议改 `-dr`/`-cr`。

### Low

**7. sysinfo 返回值被忽略：失败时旧值当新值显示并再次入历史** — src/main.c:220-222 ｜ low ｜ 否

- 证据：sysinfo_cpu/mem/disk 的 -1 未检查（同块内 loadavg/uptime/SMC/proclist 均有处理）；失败路径在 memset 前 return（sysinfo.c:58/113/154）保持旧值；main.c:234 无条件 history_push 重复旧 busy；时钟继续走且无陈旧提示。触发为瞬态 Mach 失败，常规运行未复现。
- 复现：代码路径确定；需注入 host_processor_info 单次失败观察。

**8. SMC result/status 字节从不检查：缺失 key 被当作成功读到 0** — src/smc.c:92 ｜ low ｜ 否

- 证据：实机 KEYINFO 对 TC0D/F1Ac 返回 kr=0、result=0x84、size=0，READ 返回 kr=0、result=0x89、bytes 全零；smc.c:91-103 只判 kIOReturnSuccess，无 result 消费点；smc_fans 可画出 "0 RPM min 0 max 0"；违反 smc.h:21-25 自身契约。本机风扇 key 均正常，无现役影响。
- 复现：/tmp/smc_probe/fail_probe；修法 `if (out.result != 0) return -1;`。

**9. make sanitize 产物留在共享 build/：之后 plain make 空转或链接失败** — Makefile:85 ｜ low ｜ 否

- 证据：sanitize 仅加 target-specific flags + clean all，对象仍写共享 OBJDIR；随后 `make` 报 "Nothing to be done"（现有 build/*.o 全为 ASan 产物即实证）；改源文件再 make 则 ___asan_*/___ubsan_* undefined。README:174 未提需先 make clean。
- 复现：make clean && make sanitize && make -W src/main.c。

**10. run-macmon 技能目录缺 SKILL.md（悬空引用）** — NOTES.md:21、.claude/skills/run-macmon/driver.py:31 ｜ low ｜ 否

- 证据：全仓库无 SKILL.md；NOTES.md:19 承诺的 gotcha 清单未写；该目录不构成可加载技能。driver.py 不依赖它，实跑 launch/wait/ss/quit 正常（exit 0）。

**11. README 称 external_page_count "单独显示为可回收"，实际只写不读** — README.md:99 ｜ low ｜ 否

- 证据：sysinfo.c:137 是唯一写点（→ mem.cached），无任何读取方；UI MEM 行只有 used/total/wired/comp（ui.c:430-433）；自带截图与实跑均无该值。

## 性能测量结论

- 方法：同 flags 干净 -O2 构建（仓库现有 ./macmon 与 build/*.o 是 ASan+UBSan 产物，不可计时）；0.25s 间隔 TUI 75s + sample 55s/220 tick；rusage soak 240s/960 tick 复核。
- 每 tick（墙钟 ≈8ms）：proclist_sample 5.2ms（65%；proc_pidinfo 3.14 + proc_name 1.78）、smc_fans 2.28ms（29%）、sysinfo_cpu 0.25ms、ui_draw 0.23ms；CPU 实耗 5.02ms/tick（2.0% 单核、83% 内核态），1s 间隔 5.31ms/tick（0.53%）。绘制极轻（整帧 0.29ms；15s 兜底整屏 ≈2.7KB）。注：sample 实测节拍 ~1.13ms/样本，各函数 ms 或低估 ~13%（统一缩放，占比与 rusage 数字不变）。已记录：部分（README:158-162）。
- proclist "约 4.4ms / 整体 O(n²)" 复核：4.4ms 代表性成立（min 3.1-3.6、p50 3.5-3.9ms；构成 pidinfo≈60%/proc_name≈34%/其余 6%）；n² 扫描项仅 2-4%（最坏 0.055ms@349 可见）。"二分+名字缓存削掉大半"不成立，上限 ≈1/3（二分 ~3%、名字缓存 ~34%）。已记录 否。
- SMC 常量重读：F0Mn/F0Mx（+FNum）每 tick 重读，占 smc_fans ~50%≈1.1ms/tick（min/max 跨 16 份截图恒 2700/8000，属机器常量）；缓存后 2.28→约 1.1ms/tick。注意耗时几乎全在 mach_msg_trap 阻塞，CPU 口径收益小于壁钟。已记录 否。
- 间隔精度：0.25/1/5s 无累积漂移（p50 偏差 ≤0.1ms、60-90s 漂移 ≤5ms）；15s 兜底相位独立于 tick，5s 间隔下多一次整屏重绘（≈184B/s，可忽略）。已记录 是。
- 无泄漏（负面结果）：0.25s×240s soak 0 leaks、RSS 1.53MB 平台期；每 tick 仅 pid 数组一次 malloc/free。

## 文档与清理项

- git 基线未建立：main 零提交、9 个顶层条目全部 untracked（无历史可溯）。
- screens/first.txt 是采集损坏：SWAP 5747.0% 与同行 553M/2.0G 算术矛盾、跨帧字符/行拼接（四个重复条目同结论）；同类拼接可由 driver.py 复现，不指向代码缺陷，建议重抓或删除。
- mach_host_self() 每次采样泄漏 1 个 send-right 引用（sysinfo.c:56/117；1000 次调用 urefs 3→1003）：仅 refcount，1Hz 下 32 位溢出约需 68 年；重构时可缓存 host port。
- 进程 CPU 基线仅按 pid 匹配（proclist.c:39-53），无启动时间；pid 复用在理论窗口可致假尖峰（本机未触发）——proclist 重写时的加固注记。
- 46x14/15 守卫：阈值与 README 一致，但不保证提示语不折行（14x10 折两行）、不保证 46-67 列下数值不静默截断（TASKS/风扇 max/wired/comp）。
- smc sp78 未解码（smc.c:131；本机 TC0P/TC0E/TB0T 为 sp78）：属 README:166 计划内、非遗漏；实现时需配合 result 字节检查。
- smc ABI/字节序/生命周期实测无缺陷（80 字节结构/偏移/大端 key/小端 flt/fpe2/无泄漏/非 root 可用）；arm64 小端分支未实机验证。
- scroll-storm 修复验证通过（define_key、粘滞 repaint_all、排空、20fps；200 箭头键 6687B 有界、不洗牌）；唯一残余：单 ESC 需等 ESCDELAY（实测 1009ms）。
- 工具层：driver.py 缺 DECSTBM/区域滚动支持、CJK 宽度计数有误——假阳性截图根因，属测试夹具缺陷而非应用缺陷。

## 前端解耦耦合地图

**采样核心（main.c 主循环）**

- 唯一采样段 219-241（sysinfo_cpu/mem/disk/loadavg/uptime → smc_fans → proclist_sample；history_push 234；next_sample 236-238；dirty 240）；循环前预热 185-187（PRIME_MS=200）。
- 唯一绘制调用 250-255（dirty × next_frame 门控，MIN_FRAME_SECS=0.05@30）；15s 兜底重绘 199-204（墙钟、纯表现层）；唤醒合成 261-268（采样 deadline × 帧限 × paused）；输入段 269-279（ui_wait → handle_key，DRAIN_MAX=64@38）。
- 采样缓冲为 main() 局部量 143-154（procs[PROC_ROWS]@148；have_smc@162），采样写、绘制读共用所有权。

**耦合点（UI 偏好 ↔ 采样行为）**

- handle_key（73-139）直接改写采样所读 ui_state_t：interval（79/83 经 65-70）、sort（87/91）、paused（95）。
- st.paused：采样闸门（219/247）+ UI 状态（95；ui.c:215 [PAUSED]）。
- st.sort 经 230 传入 proclist_sample，决定 qsort 与截断保留集（proclist.c:154-158）——UI 偏好改变返回数据内容而非仅渲染顺序。
- st.interval 驱动采样节奏（236-238、243-248）。
- 样本经 history_push（57-63、234）写入 ui_state_t.history；ui_state_t（ui.h:10-17）混合偏好与采样数据，两侧读写。
- nprocs 同时被进程表（ui.c:333）与状态行 TASKS（ui.c:459/461）消费。

**模块边界**

- ui.c 不调用采样函数；依赖面 = ui_draw 参数表（352-355 / ui.h:33-36）+ 数据类型；文件级可变状态仅 repaint_all（19/105/399-402）与 glyph 指针（33-51/99）；ncurses 调用全部在 ui.c（main.c 仅 KEY_*）。绘制路径 ui_draw → draw_procs（306-350，466 调用）→ 行循环 333-349，唯一转换 MEM human_bytes@339。
- sysinfo 5 个公开函数（sysinfo.h:39-43）；全局态仅 cpu 差分基线（sysinfo.c:18-22、71-103）+ page_size 缓存（39-47）。
- proclist 仅 proclist_sample（proclist.h:31）；跨调用全局缓存 cached/cached_len（proclist.c:26-29）；每 tick malloc/free pid 表（87/150）；完整路径 75→80/91→110/135→126-148→154-159。
- smc 3 入口（smc.h:18-25），共享 conn/opened（smc.c:56-57、150-176）；smc_fans 正确性依赖先 smc_open 的调用顺序。

## 已排除的候选

- 稳态 9s pty 快照行序错乱 / MEM 73318.6%：driver.py 回放模型未实现 DECSTBM/区域滚动，同一字节流喂 pyte 与补丁模型均正常渲染——应用侧假阳性。
- 快速按键后整行错位与字符合并：同源（driver.py 模型缺陷）；原复现命令 5/5 不可复现，真实终端无此现象。

## 覆盖度自查

- 未覆盖：长时稳定性（小时/天级运行、SMC 长跑、风扇转速长期漂移）；Apple Silicon/arm64 实机（本机 Intel macOS 12.7.6，universal 构建未运行）；多风扇/无风扇机型。
- 其余空缺：真实终端与 GUI（结论均出自 pty/驱动，GUI 尚不存在，TASKS/minos 继承问题属前瞻推断）；CJK 宽度与 locale；Mach 调用失败的真实触发（sysinfo 缺陷仅代码路径级复现）。
