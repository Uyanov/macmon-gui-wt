#import <Cocoa/Cocoa.h>
#include "core.h"

@interface MacMonitorApp : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic) monitor_core_t *core;
@property(nonatomic) core_snapshot_t snapshot;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSMutableArray<NSTextField *> *metrics;
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
    window.minSize = NSMakeSize(620, 420);

    NSStackView *root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor]
    ]];

    self.metrics = [NSMutableArray array];
    for (NSString *title in @[@"CPU", @"内存", @"交换空间", @"磁盘", @"风扇", @"CPU 走势"]) {
        NSTextField *label = [self label:title size:15];
        [self.metrics addObject:label];
        [root addArrangedSubview:label];
    }
    self.status = [self label:@"正在采样…" size:13];
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
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

    [window center];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self
        selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (void)refresh:(NSTimer *)timer {
    (void)timer;
    if (core_snapshot(self.core, &_snapshot) != 0)
        return;
    double memUsed = (double)(_snapshot.mem.app + _snapshot.mem.wired + _snapshot.mem.compressed);
    double memPct = _snapshot.mem.total ? 100.0 * memUsed / _snapshot.mem.total : 0;
    double diskPct = _snapshot.disk.total ? 100.0 * _snapshot.disk.used / _snapshot.disk.total : 0;
    NSString *fan = _snapshot.has_fans && _snapshot.fans.count > 0
        ? [NSString stringWithFormat:@"风扇: %.0f RPM", _snapshot.fans.rpm[0]] : @"风扇: 不可用";
    _metrics[0].stringValue = [NSString stringWithFormat:@"CPU: %.1f%% (用户 %.1f%% / 系统 %.1f%% / 空闲 %.1f%%)",
        _snapshot.cpu.busy, _snapshot.cpu.user, _snapshot.cpu.system, _snapshot.cpu.idle];
    _metrics[1].stringValue = [NSString stringWithFormat:@"内存: %.1f%%  应用/总计 %.1fG / %.1fG",
        memPct, memUsed / 1073741824.0, _snapshot.mem.total / 1073741824.0];
    _metrics[2].stringValue = [NSString stringWithFormat:@"交换空间: %.1f%%  %.1fG / %.1fG",
        _snapshot.mem.swap_total ? 100.0 * _snapshot.mem.swap_used / _snapshot.mem.swap_total : 0,
        _snapshot.mem.swap_used / 1073741824.0, _snapshot.mem.swap_total / 1073741824.0];
    _metrics[3].stringValue = [NSString stringWithFormat:@"磁盘: %.1f%%  已用 %.1fG / %.1fG",
        diskPct, _snapshot.disk.used / 1073741824.0, _snapshot.disk.total / 1073741824.0];
    _metrics[4].stringValue = fan;
    NSMutableString *history = [NSMutableString stringWithString:@"CPU 走势: "];
    for (int i = 0; i < _snapshot.history_len; i++) {
        int index = (_snapshot.history_head - _snapshot.history_len + i + CORE_CPU_HISTORY) % CORE_CPU_HISTORY;
        [history appendFormat:@"%c", "._:=+*#%"[(int)MIN(7, MAX(0, _snapshot.history[index] / 100.0 * 7.0))]];
    }
    _metrics[5].stringValue = history;
    long uptime = _snapshot.uptime;
    NSString *up = uptime >= 0
        ? [NSString stringWithFormat:@"运行 %ldd %02ldh %02ldm", uptime / 86400,
            (uptime % 86400) / 3600, (uptime % 3600) / 60]
        : @"运行时间不可用";
    _status.stringValue = [NSString stringWithFormat:@"负载 %.2f %.2f %.2f   进程 %d   %@   %@",
        _snapshot.load[0], _snapshot.load[1], _snapshot.load[2], _snapshot.proc_total, up,
        _snapshot.stale_mask ? @"数据陈旧" : @"数据正常"];
    [_table reloadData];
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
    if ([column.identifier isEqualToString:@"pid"]) cell.textField.stringValue = [NSString stringWithFormat:@"%d", p.pid];
    else if ([column.identifier isEqualToString:@"name"]) cell.textField.stringValue = [NSString stringWithUTF8String:p.name] ?: @"";
    else if ([column.identifier isEqualToString:@"cpu"]) cell.textField.stringValue = [NSString stringWithFormat:@"%.1f", p.cpu];
    else cell.textField.stringValue = [NSString stringWithFormat:@"%.1fM", p.mem / 1048576.0];
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
