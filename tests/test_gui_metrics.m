#define main macmon_application_main
#import "../src/gui.m"
#undef main

static void require(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "失败：%s\n", message.UTF8String); exit(1); }
}

static void capture(NSWindow *window, NSString *path) {
    [window.contentView layoutSubtreeIfNeeded];
    NSScrollView *scroll = (NSScrollView *)window.contentView.subviews.firstObject;
    NSView *document = scroll.documentView;
    [document layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [document bitmapImageRepForCachingDisplayInRect:document.bounds];
    [document cacheDisplayInRect:document.bounds toBitmapImageRep:bitmap];
    require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"保存界面预览");
}

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app finishLaunching];
        MacMonitorApp *delegate = [[MacMonitorApp alloc] init];
        [delegate applicationDidFinishLaunching:
            [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:app]];
        require(delegate.window != nil, @"创建窗口");
        [delegate.timer invalidate];
        core_stop(delegate.core);
        [delegate refresh:delegate.timer];
        delegate.extendedHistory = (metric_history_t){0};
        require(delegate.metricCards.count == 6, @"独立网络和温度卡片");
        for (NSInteger kind = CardIconCPU; kind <= CardIconTemperature; kind++) {
            CardIconView *icon = [[CardIconView alloc] initWithKind:kind];
            require(icon.image != nil, @"图标可用");
        }
        core_snapshot_t snapshot = {.sequence = 1, .sampled_at = 100, .interval = 1,
            .network = {0, 0, NETWORK_OK}, .temperature = {63.4, TEMPERATURE_OK, TEMPERATURE_VIRTUAL, "TC0E"}};
        delegate.snapshot = snapshot;
        [delegate refreshExtendedMetrics];
        require([delegate.metricCards[METRIC_NETWORK].accessibilityLabel containsString:@"下载 0 B/s"], @"真实零速率");
        require([delegate.metricCards[METRIC_NETWORK].accessibilityLabel containsString:@"上传 0 B/s"], @"两种方向");
        require([delegate.metricCards[METRIC_TEMPERATURE].accessibilityLabel containsString:@"63.4°C"], @"摄氏温度");
        require([delegate.metricCards[METRIC_TEMPERATURE].accessibilityLabel containsString:@"虚拟二极管"], @"温度具体口径");
        snapshot.sequence++; snapshot.sampled_at++;
        snapshot.network.status = NETWORK_WARMUP;
        snapshot.temperature.status = TEMPERATURE_ERROR;
        delegate.snapshot = snapshot;
        [delegate refreshExtendedMetrics];
        require([delegate.metricCards[METRIC_NETWORK].accessibilityLabel containsString:@"正在采样"], @"网络基线提示");
        require([delegate.metricCards[METRIC_TEMPERATURE].accessibilityLabel containsString:@"读取失败"], @"温度错误提示");
        require(![delegate.metricCards[METRIC_TEMPERATURE].accessibilityLabel containsString:@"0.0°C"], @"缺失读数不显示零值");
        for (int i = 2; i <= 60; i++) {
            snapshot.sequence++; snapshot.sampled_at = 100 + i;
            snapshot.network.status = NETWORK_OK;
            snapshot.network.download = 10000 + 5000 * sin(i / 5.0);
            snapshot.network.upload = 2000 + 1000 * cos(i / 7.0);
            snapshot.temperature.status = TEMPERATURE_OK;
            snapshot.temperature.celsius = 60 + 8 * sin(i / 12.0);
            delegate.snapshot = snapshot;
            [delegate refreshExtendedMetrics];
        }
        [delegate.window setContentSize:NSMakeSize(1040, 800)];
        capture(delegate.window, @"build/gui-metrics-wide.png");
        [delegate.window setContentSize:NSMakeSize(520, 800)];
        capture(delegate.window, @"build/gui-metrics-narrow.png");
        for (MetricCardView *card in delegate.metricCards)
            require(NSWidth(card.frame) >= 200, @"窄窗口卡片宽度");
        snapshot.sequence++; snapshot.sampled_at++;
        snapshot.network.status = NETWORK_NO_LINK;
        snapshot.temperature = (temperature_info_t){.status = TEMPERATURE_UNAVAILABLE};
        delegate.snapshot = snapshot;
        [delegate refreshExtendedMetrics];
        require([delegate.metricCards[METRIC_NETWORK].accessibilityLabel containsString:@"无网络连接"], @"断网提示");
        require([delegate.metricCards[METRIC_TEMPERATURE].accessibilityLabel containsString:@"不支持或不可用"], @"无传感器提示");
        [delegate.window close];
        core_destroy(delegate.core); delegate.core = NULL;
        fprintf(stderr, "通过：新增指标显示、来源、异常状态与宽窄窗口\n");
    }
    return 0;
}
