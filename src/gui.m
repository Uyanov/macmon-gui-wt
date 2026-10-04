#import <Cocoa/Cocoa.h>
#include "core.h"

enum {
    METRIC_CPU = 0,
    METRIC_MEMORY,
    METRIC_SWAP,
    METRIC_DISK,
    METRIC_COUNT,
};

@interface MacMonitorApp : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic) monitor_core_t *core;
@property(nonatomic) core_snapshot_t snapshot;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSMutableArray<NSProgressIndicator *> *progressIndicators;
@property(nonatomic) NSMutableArray<NSTextField *> *metricValues;
@property(nonatomic) NSTextField *fanStatus;
@property(nonatomic) NSTextField *history;
@property(nonatomic) NSTextField *status;
@property(nonatomic) NSTableView *table;
@property(nonatomic) proc_sort_t sort;
@end

@implementation MacMonitorApp

- (NSTextField *)label:(NSString *)text size:(CGFloat)size {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSStackView *)metricRow:(NSString *)title {
    NSStackView *row = [NSStackView stackViewWithViews:@[]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *titleLabel = [self label:title size:13];
    titleLabel.alignment = NSTextAlignmentRight;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titleLabel.widthAnchor constraintEqualToConstant:76].active = YES;

    NSProgressIndicator *progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    progress.style = NSProgressIndicatorStyleBar;
    progress.indeterminate = NO;
    progress.minValue = 0.0;
    progress.maxValue = 100.0;
    progress.controlSize = NSControlSizeSmall;
    progress.translatesAutoresizingMaskIntoConstraints = NO;
    [progress.widthAnchor constraintGreaterThanOrEqualToConstant:110].active = YES;
    [progress setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                forOrientation:NSLayoutConstraintOrientationHorizontal];
    [progress setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField *value = [self label:@"不可用" size:12];
    value.alignment = NSTextAlignmentLeft;
    value.lineBreakMode = NSLineBreakByTruncatingTail;
    value.maximumNumberOfLines = 1;
    [value setContentHuggingPriority:NSLayoutPriorityDefaultLow
                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    [value setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];

    [row addArrangedSubview:titleLabel];
    [row addArrangedSubview:progress];
    [row addArrangedSubview:value];
    [self.progressIndicators addObject:progress];
    [self.metricValues addObject:value];
    return row;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    self.sort = PROC_SORT_CPU;
    self.core = core_create(1.0, self.sort);
    if (!self.core || core_start(self.core) != 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法启动采样核心";
        alert.informativeText = @"请检查系统权限后重试。";
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }

    NSRect frame = NSMakeRect(0, 0, 900, 650);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    window.title = @"MacMonitor";
    window.minSize = NSMakeSize(520, 360);

    NSStackView *root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeWidth;
    root.spacing = 10;
    root.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor]
    ]];

    self.progressIndicators = [NSMutableArray arrayWithCapacity:METRIC_COUNT];
    self.metricValues = [NSMutableArray arrayWithCapacity:METRIC_COUNT];
    NSStackView *metrics = [NSStackView stackViewWithViews:@[]];
    metrics.orientation = NSUserInterfaceLayoutOrientationVertical;
    metrics.alignment = NSLayoutAttributeWidth;
    metrics.spacing = 6;
    [metrics addArrangedSubview:[self metricRow:@"CPU"]];
    [metrics addArrangedSubview:[self metricRow:@"内存"]];
    [metrics addArrangedSubview:[self metricRow:@"交换空间"]];
    [metrics addArrangedSubview:[self metricRow:@"磁盘"]];
    [root addArrangedSubview:metrics];

    self.fanStatus = [self label:@"风扇：不可用" size:12];
    self.fanStatus.lineBreakMode = NSLineBreakByWordWrapping;
    self.fanStatus.maximumNumberOfLines = 0;
    [root addArrangedSubview:self.fanStatus];

    self.history = [self label:@"CPU 走势（60 秒）：暂无数据" size:12];
    self.history.lineBreakMode = NSLineBreakByTruncatingTail;
    [root addArrangedSubview:self.history];

    self.status = [self label:@"正在采样…" size:12];
    self.status.lineBreakMode = NSLineBreakByTruncatingTail;
    [root addArrangedSubview:self.status];

    self.table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.usesAlternatingRowBackgroundColors = YES;
    for (NSArray *spec in @[@[@"pid", @"PID", @70], @[@"name", @"进程", @300],
                             @[@"cpu", @"CPU%", @90], @[@"mem", @"内存", @100]]) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        [self.table addTableColumn:column];
    }
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.documentView = self.table;
    scroll.hasVerticalScroller = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [root addArrangedSubview:scroll];
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
    [scroll setContentHuggingPriority:NSLayoutPriorityDefaultLow
                              forOrientation:NSLayoutConstraintOrientationVertical];

    [window center];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self
        selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (void)setMetric:(NSInteger)index percent:(double)percent value:(NSString *)value
        available:(BOOL)available stale:(BOOL)stale {
    NSProgressIndicator *progress = self.progressIndicators[index];
    NSTextField *display = self.metricValues[index];
    progress.hidden = !available || stale;
    progress.doubleValue = MIN(100.0, MAX(0.0, percent));
    if (stale)
        display.stringValue = @"数据陈旧";
    else if (!available)
        display.stringValue = @"不可用";
    else
        display.stringValue = value;
}

- (NSString *)fanSummary {
    if (_snapshot.stale_mask & CORE_STALE_FAN)
        return @"风扇：数据陈旧";
    if (!_snapshot.has_fans || _snapshot.fans.count <= 0)
        return @"风扇：无传感器或不可用";

    NSMutableString *summary = [NSMutableString stringWithString:@"风扇："];
    for (int i = 0; i < _snapshot.fans.count && i < SMC_MAX_FANS; i++) {
        if (i > 0)
            [summary appendString:@"   "];
        [summary appendFormat:@"风扇 %d %.0f RPM", i + 1, _snapshot.fans.rpm[i]];
    }
    return summary;
}

- (void)refresh:(NSTimer *)timer {
    (void)timer;
    if (core_snapshot(self.core, &_snapshot) != 0)
        return;

    const BOOL cpuAvailable = !(_snapshot.stale_mask & CORE_STALE_CPU);
    const BOOL memAvailable = !(_snapshot.stale_mask & CORE_STALE_MEM) && _snapshot.mem.total > 0;
    const BOOL swapAvailable = !(_snapshot.stale_mask & CORE_STALE_MEM) && _snapshot.mem.swap_total > 0;
    const BOOL diskAvailable = !(_snapshot.stale_mask & CORE_STALE_DISK) && _snapshot.disk.total > 0;
    double memUsed = (double)(_snapshot.mem.app + _snapshot.mem.wired + _snapshot.mem.compressed);
    double memPct = memAvailable ? 100.0 * memUsed / _snapshot.mem.total : 0.0;
    double swapPct = swapAvailable ? 100.0 * _snapshot.mem.swap_used / _snapshot.mem.swap_total : 0.0;
    double diskPct = diskAvailable ? 100.0 * _snapshot.disk.used / _snapshot.disk.total : 0.0;
    NSString *cpuValue = [NSString stringWithFormat:@"%.1f%%（用户 %.1f / 系统 %.1f / 空闲 %.1f）",
        _snapshot.cpu.busy, _snapshot.cpu.user, _snapshot.cpu.system, _snapshot.cpu.idle];
    NSString *memValue = [NSString stringWithFormat:@"%.1f%%  %.1fG / %.1fG",
        memPct, memUsed / 1073741824.0, _snapshot.mem.total / 1073741824.0];
    NSString *swapValue = [NSString stringWithFormat:@"%.1f%%  %.1fG / %.1fG",
        swapPct, _snapshot.mem.swap_used / 1073741824.0,
        _snapshot.mem.swap_total / 1073741824.0];
    NSString *diskValue = [NSString stringWithFormat:@"%.1f%%  %.1fG / %.1fG",
        diskPct, _snapshot.disk.used / 1073741824.0, _snapshot.disk.total / 1073741824.0];
    [self setMetric:METRIC_CPU percent:_snapshot.cpu.busy value:cpuValue
          available:cpuAvailable stale:(_snapshot.stale_mask & CORE_STALE_CPU) != 0];
    [self setMetric:METRIC_MEMORY percent:memPct value:memValue
          available:memAvailable stale:(_snapshot.stale_mask & CORE_STALE_MEM) != 0];
    [self setMetric:METRIC_SWAP percent:swapPct value:swapValue
          available:swapAvailable stale:(_snapshot.stale_mask & CORE_STALE_MEM) != 0];
    [self setMetric:METRIC_DISK percent:diskPct value:diskValue
          available:diskAvailable stale:(_snapshot.stale_mask & CORE_STALE_DISK) != 0];
    self.fanStatus.stringValue = [self fanSummary];

    NSMutableString *history = [NSMutableString stringWithString:@"CPU 走势（60 秒）："];
    static const char glyphs[] = "._:=+*#%";
    for (int i = 0; i < _snapshot.history_len; i++) {
        int index = (_snapshot.history_head - _snapshot.history_len + i + CORE_CPU_HISTORY)
            % CORE_CPU_HISTORY;
        int level = (int)(_snapshot.history[index] / 100.0 * 7.0);
        level = MIN(7, MAX(0, level));
        [history appendFormat:@"%c", glyphs[level]];
    }
    if (_snapshot.history_len == 0)
        [history appendString:@"暂无数据"];
    self.history.stringValue = history;

    long uptime = _snapshot.uptime;
    NSString *up = uptime >= 0
        ? [NSString stringWithFormat:@"运行 %ldd %02ldh %02ldm", uptime / 86400,
            (uptime % 86400) / 3600, (uptime % 3600) / 60]
        : @"运行时间不可用";
    self.status.stringValue = [NSString stringWithFormat:@"负载 %.2f %.2f %.2f   进程 %d   %@   %@",
        _snapshot.load[0], _snapshot.load[1], _snapshot.load[2], _snapshot.proc_total, up,
        _snapshot.stale_mask ? @"部分数据陈旧" : (_snapshot.paused ? @"已暂停" : @"数据正常")];
    [self.table reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return _snapshot.proc_count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:column.identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = column.identifier;
        NSTextField *text = [NSTextField labelWithString:@""];
        text.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        text.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:text];
        cell.textField = text;
        [NSLayoutConstraint activateConstraints:@[
            [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    proc_info_t p = _snapshot.procs[row];
    if ([column.identifier isEqualToString:@"pid"])
        cell.textField.stringValue = [NSString stringWithFormat:@"%d", p.pid];
    else if ([column.identifier isEqualToString:@"name"])
        cell.textField.stringValue = [NSString stringWithUTF8String:p.name] ?: @"";
    else if ([column.identifier isEqualToString:@"cpu"])
        cell.textField.stringValue = [NSString stringWithFormat:@"%.1f", p.cpu];
    else
        cell.textField.stringValue = [NSString stringWithFormat:@"%.1fM", p.mem / 1048576.0];
    return cell;
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)column {
    (void)tableView;
    self.sort = [column.identifier isEqualToString:@"mem"] ? PROC_SORT_MEM : PROC_SORT_CPU;
    core_set_sort(self.core, self.sort);
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    core_destroy(self.core);
    self.core = NULL;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}
@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        MacMonitorApp *delegate = [[MacMonitorApp alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
