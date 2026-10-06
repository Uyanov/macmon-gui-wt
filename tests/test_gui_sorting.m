#define main macmon_application_main
#import "../src/gui.m"
#undef main

static void require(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "失败：%s\n", message.UTF8String); exit(1); }
}

static void expectOrder(MacMonitorApp *delegate, const pid_t expected[4]) {
    NSTableColumn *pidColumn = [delegate.table tableColumnWithIdentifier:@"pid"];
    for (NSInteger row = 0; row < 4; row++) {
        NSTableCellView *cell = (NSTableCellView *)[delegate tableView:delegate.table
            viewForTableColumn:pidColumn row:row];
        require(cell.textField.stringValue.intValue == expected[row], @"进程显示顺序");
    }
}

static void click(MacMonitorApp *delegate, NSString *identifier) {
    [delegate tableView:delegate.table
        didClickTableColumn:[delegate.table tableColumnWithIdentifier:identifier]];
}

static void expectHeaders(MacMonitorApp *delegate, NSString *cpu, NSString *mem) {
    require([[delegate.table tableColumnWithIdentifier:@"cpu"].title isEqualToString:cpu], @"CPU 排序箭头");
    require([[delegate.table tableColumnWithIdentifier:@"mem"].title isEqualToString:mem], @"内存排序箭头");
}

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app finishLaunching];
        MacMonitorApp *delegate = [[MacMonitorApp alloc] init];
        [delegate applicationDidFinishLaunching:
            [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:app]];
        [delegate.timer invalidate];
        core_stop(delegate.core);
        require(delegate.sort == PROC_SORT_DEFAULT, @"启动时默认排序");
        expectHeaders(delegate, @"CPU 占用", @"内存");
        core_snapshot_t snapshot = {.proc_count = 4, .procs = {
            {.pid = 30, .cpu = 75, .mem = 300}, {.pid = 20, .cpu = 35, .mem = 100},
            {.pid = 10, .cpu = 0, .mem = 900}, {.pid = 40, .cpu = 0, .mem = 100},
        }};
        delegate.snapshot = snapshot;
        click(delegate, @"cpu");
        expectHeaders(delegate, @"CPU 占用 ↓", @"内存");
        expectOrder(delegate, (pid_t[]){30, 20, 10, 40});
        click(delegate, @"cpu");
        expectHeaders(delegate, @"CPU 占用 ↑", @"内存");
        expectOrder(delegate, (pid_t[]){10, 40, 20, 30});
        require([delegate.processSectionHint.stringValue containsString:@"从小到大"], @"升序说明");
        click(delegate, @"cpu");
        expectHeaders(delegate, @"CPU 占用", @"内存");
        expectOrder(delegate, (pid_t[]){30, 20, 10, 40});
        require([delegate.processSectionHint.stringValue isEqualToString:@"默认排序"], @"默认排序说明");
        click(delegate, @"mem");
        expectHeaders(delegate, @"CPU 占用", @"内存 ↓");
        expectOrder(delegate, (pid_t[]){10, 30, 20, 40});
        click(delegate, @"mem");
        expectHeaders(delegate, @"CPU 占用", @"内存 ↑");
        expectOrder(delegate, (pid_t[]){20, 40, 30, 10});
        click(delegate, @"pid");
        click(delegate, @"name");
        expectHeaders(delegate, @"CPU 占用", @"内存 ↑");
        click(delegate, @"cpu");
        expectHeaders(delegate, @"CPU 占用 ↓", @"内存");
        expectOrder(delegate, (pid_t[]){30, 20, 10, 40});
        click(delegate, @"mem");
        expectHeaders(delegate, @"CPU 占用", @"内存 ↓");
        click(delegate, @"mem");
        click(delegate, @"mem");
        expectHeaders(delegate, @"CPU 占用", @"内存");
        expectOrder(delegate, (pid_t[]){30, 20, 10, 40});
        snapshot.stale_mask = CORE_STALE_PROC;
        delegate.snapshot = snapshot;
        click(delegate, @"mem");
        require([delegate.processSectionHint.stringValue containsString:@"数据陈旧"], @"陈旧提示保留");
        expectHeaders(delegate, @"CPU 占用", @"内存 ↓");
        // 暂停期间点击仍立即重排，后续快照刷新保持所选方向。
        core_set_paused(delegate.core, 1);
        click(delegate, @"mem");
        [delegate refresh:nil];
        expectHeaders(delegate, @"CPU 占用", @"内存 ↑");
        core_snapshot_t actual;
        require(core_snapshot(delegate.core, &actual) == 0 && actual.sort == PROC_SORT_MEM_ASC,
            @"后台收到升序控制");
        for (int i = 1; i < delegate.snapshot.proc_count; i++)
            require(delegate.snapshot.procs[i - 1].mem <= delegate.snapshot.procs[i].mem,
                @"刷新后保持内存升序");
        [delegate.window close];
        core_destroy(delegate.core); delegate.core = NULL;
        fprintf(stderr, "通过：进程列三态排序、箭头、切列、默认恢复、暂停与刷新\n");
    }
    return 0;
}
