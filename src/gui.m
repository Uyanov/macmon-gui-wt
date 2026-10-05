#import <Cocoa/Cocoa.h>
#include "core.h"

enum {
    METRIC_CPU = 0,
    METRIC_MEMORY,
    METRIC_SWAP,
    METRIC_DISK,
    METRIC_COUNT,
};

typedef NS_ENUM(NSInteger, UISeverity) {
    UISeverityNormal = 0,
    UISeverityWarning,
    UISeverityError,
    UISeverityNeutral,
};

static NSColor *UISeverityColor(UISeverity severity) {
    switch (severity) {
    case UISeverityWarning:
        return [NSColor systemOrangeColor];
    case UISeverityError:
        return [NSColor systemRedColor];
    case UISeverityNeutral:
        return [NSColor secondaryLabelColor];
    case UISeverityNormal:
    default:
        return [NSColor systemGreenColor];
    }
}

@interface RoundedPanelView : NSView
@property(nonatomic) NSColor *fillColor;
@property(nonatomic) NSColor *borderColor;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) CGFloat borderWidth;
@end

@implementation RoundedPanelView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        _fillColor = [NSColor controlBackgroundColor];
        _borderColor = [NSColor separatorColor];
        _cornerRadius = 10.0;
        _borderWidth = 0.75;
    }
    return self;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    self.layer.backgroundColor = self.fillColor.CGColor;
    self.layer.borderColor = self.borderColor.CGColor;
    self.layer.borderWidth = self.borderWidth;
    self.layer.cornerRadius = self.cornerRadius;
    self.layer.masksToBounds = YES;
}

- (void)setFillColor:(NSColor *)fillColor {
    _fillColor = fillColor;
    [self setNeedsDisplay:YES];
}

- (void)setBorderColor:(NSColor *)borderColor {
    _borderColor = borderColor;
    [self setNeedsDisplay:YES];
}

@end

@interface AdaptiveGridView : NSView
- (instancetype)initWithItems:(NSArray<NSView *> *)items
                  wideColumns:(NSInteger)wideColumns
               compactColumns:(NSInteger)compactColumns
             compactThreshold:(CGFloat)compactThreshold
                    itemHeight:(CGFloat)itemHeight
                       spacing:(CGFloat)spacing
                 columnSpacing:(CGFloat)columnSpacing;
@end

@implementation AdaptiveGridView {
    NSArray<NSView *> *_items;
    NSInteger _wideColumns;
    NSInteger _compactColumns;
    NSInteger _columns;
    CGFloat _compactThreshold;
    CGFloat _itemHeight;
    CGFloat _spacing;
    CGFloat _columnSpacing;
    NSStackView *_stack;
}

- (instancetype)initWithItems:(NSArray<NSView *> *)items
                  wideColumns:(NSInteger)wideColumns
               compactColumns:(NSInteger)compactColumns
             compactThreshold:(CGFloat)compactThreshold
                    itemHeight:(CGFloat)itemHeight
                       spacing:(CGFloat)spacing
                 columnSpacing:(CGFloat)columnSpacing {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _items = [items copy];
        _wideColumns = MAX(1, wideColumns);
        _compactColumns = MAX(1, compactColumns);
        _compactThreshold = compactThreshold;
        _itemHeight = itemHeight;
        _spacing = spacing;
        _columnSpacing = columnSpacing;
        _columns = 0;

        _stack = [NSStackView stackViewWithViews:@[]];
        _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _stack.alignment = NSLayoutAttributeWidth;
        _stack.spacing = spacing;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
    }
    return self;
}

- (void)layout {
    [super layout];
    NSInteger desiredColumns = self.bounds.size.width > 0 &&
        self.bounds.size.width < _compactThreshold ? _compactColumns : _wideColumns;
    if (desiredColumns != _columns)
        [self rebuildRows:desiredColumns];
}

- (void)rebuildRows:(NSInteger)columns {
    for (NSStackView *row in [_stack.arrangedSubviews copy]) {
        for (NSView *item in [row.subviews copy]) {
            [row removeArrangedSubview:item];
            [item removeFromSuperview];
        }
        [_stack removeArrangedSubview:row];
        [row removeFromSuperview];
    }

    _columns = columns;
    for (NSInteger start = 0; start < (NSInteger)_items.count; start += columns) {
        NSStackView *row = [NSStackView stackViewWithViews:@[]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeHeight;
        row.distribution = NSStackViewDistributionFillEqually;
        row.spacing = _columnSpacing;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [row.heightAnchor constraintEqualToConstant:_itemHeight].active = YES;
        for (NSInteger index = start; index < start + columns && index < (NSInteger)_items.count;
             index++) {
            [row addArrangedSubview:_items[index]];
        }
        [_stack addArrangedSubview:row];
    }
    [self invalidateIntrinsicContentSize];
}

- (NSSize)intrinsicContentSize {
    NSInteger columns = _columns > 0 ? _columns : _wideColumns;
    NSInteger rows = (_items.count + columns - 1) / columns;
    CGFloat height = rows > 0 ? rows * _itemHeight + (rows - 1) * _spacing : 0;
    return NSMakeSize(NSViewNoIntrinsicMetric, height);
}

@end

@interface MetricCardView : RoundedPanelView
@property(nonatomic, readonly) NSString *metricTitle;
- (instancetype)initWithTitle:(NSString *)title;
- (void)setPercent:(double)percent
             value:(NSString *)value
            detail:(NSString *)detail
             state:(NSString *)state
          severity:(UISeverity)severity;
@end

@implementation MetricCardView {
    NSTextField *_titleLabel;
    NSTextField *_stateLabel;
    NSTextField *_valueLabel;
    NSTextField *_detailLabel;
    NSProgressIndicator *_progress;
}

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _metricTitle = [title copy];
        self.accessibilityRole = NSAccessibilityGroupRole;

        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        _titleLabel.textColor = [NSColor secondaryLabelColor];
        [_titleLabel setContentHuggingPriority:NSLayoutPriorityRequired
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];

        _stateLabel = [NSTextField labelWithString:@"正常"];
        _stateLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        _stateLabel.alignment = NSTextAlignmentLeft;
        [_stateLabel setContentHuggingPriority:NSLayoutPriorityRequired
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSView *titleSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
        [titleSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        [titleSpacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *titleRow = [NSStackView stackViewWithViews:@[
            _titleLabel, _stateLabel, titleSpacer
        ]];
        titleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        titleRow.alignment = NSLayoutAttributeCenterY;
        titleRow.distribution = NSStackViewDistributionFill;
        titleRow.translatesAutoresizingMaskIntoConstraints = NO;

        _valueLabel = [NSTextField labelWithString:@"不可用"];
        _valueLabel.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
        _valueLabel.textColor = [NSColor labelColor];
        _valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        _progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        _progress.style = NSProgressIndicatorStyleBar;
        _progress.indeterminate = NO;
        _progress.minValue = 0.0;
        _progress.maxValue = 100.0;
        _progress.controlSize = NSControlSizeSmall;
        _progress.controlTint = NSBlueControlTint;
        _progress.translatesAutoresizingMaskIntoConstraints = NO;
        [_progress.heightAnchor constraintEqualToConstant:7].active = YES;

        _detailLabel = [NSTextField labelWithString:@"暂无数据"];
        _detailLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        _detailLabel.textColor = [NSColor secondaryLabelColor];
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _detailLabel.maximumNumberOfLines = 1;

        NSStackView *content = [NSStackView stackViewWithViews:@[
            titleRow, _valueLabel, _progress, _detailLabel
        ]];
        content.orientation = NSUserInterfaceLayoutOrientationVertical;
        content.alignment = NSLayoutAttributeWidth;
        content.spacing = 5;
        content.edgeInsets = NSEdgeInsetsMake(11, 13, 10, 13);
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [content.topAnchor constraintEqualToAnchor:self.topAnchor],
            [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
    }
    return self;
}

- (void)setPercent:(double)percent
             value:(NSString *)value
            detail:(NSString *)detail
             state:(NSString *)state
          severity:(UISeverity)severity {
    NSColor *color = UISeverityColor(severity);
    _stateLabel.stringValue = state;
    _stateLabel.textColor = color;
    _valueLabel.stringValue = value;
    _detailLabel.stringValue = detail;
    _valueLabel.textColor = severity == UISeverityNormal ? [NSColor labelColor] : color;
    _progress.doubleValue = MIN(100.0, MAX(0.0, percent));
    _progress.hidden = severity != UISeverityNormal;
    self.borderColor = [color colorWithAlphaComponent:severity == UISeverityNormal ? 0.22 : 0.55];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@ %@，%@", _metricTitle, value, state];
}

@end

@interface InfoTileView : RoundedPanelView
- (instancetype)initWithTitle:(NSString *)title;
- (void)setValueText:(NSString *)value severity:(UISeverity)severity;
@end

@implementation InfoTileView {
    NSTextField *_titleLabel;
    NSTextField *_valueLabel;
}

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        _titleLabel.textColor = [NSColor secondaryLabelColor];

        _valueLabel = [NSTextField labelWithString:@"暂无数据"];
        _valueLabel.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
        _valueLabel.textColor = [NSColor labelColor];
        _valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _valueLabel.maximumNumberOfLines = 2;

        NSStackView *content = [NSStackView stackViewWithViews:@[_titleLabel, _valueLabel]];
        content.orientation = NSUserInterfaceLayoutOrientationVertical;
        content.alignment = NSLayoutAttributeWidth;
        content.spacing = 4;
        content.edgeInsets = NSEdgeInsetsMake(9, 11, 8, 11);
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [content.topAnchor constraintEqualToAnchor:self.topAnchor],
            [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
        [self.heightAnchor constraintEqualToConstant:62].active = YES;
    }
    return self;
}

- (void)setValueText:(NSString *)value severity:(UISeverity)severity {
    NSColor *color = UISeverityColor(severity);
    _valueLabel.stringValue = value;
    _valueLabel.textColor = severity == UISeverityNormal ? [NSColor labelColor] : color;
    self.borderColor = [color colorWithAlphaComponent:severity == UISeverityNormal ? 0.2 : 0.5];
    self.accessibilityValue = value;
}

@end

@interface StatusBannerView : RoundedPanelView
- (void)setTitle:(NSString *)title detail:(NSString *)detail severity:(UISeverity)severity;
@end

@implementation StatusBannerView {
    NSView *_dot;
    NSTextField *_titleLabel;
    NSTextField *_detailLabel;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _dot = [[NSView alloc] initWithFrame:NSZeroRect];
        _dot.wantsLayer = YES;
        _dot.translatesAutoresizingMaskIntoConstraints = NO;
        [_dot.widthAnchor constraintEqualToConstant:10].active = YES;
        [_dot.heightAnchor constraintEqualToConstant:10].active = YES;

        _titleLabel = [NSTextField labelWithString:@"系统状态正常"];
        _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        _titleLabel.textColor = [NSColor labelColor];

        _detailLabel = [NSTextField labelWithString:@"正在读取系统状态…"];
        _detailLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
        _detailLabel.textColor = [NSColor secondaryLabelColor];
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        NSStackView *text = [NSStackView stackViewWithViews:@[_titleLabel, _detailLabel]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeWidth;
        text.spacing = 2;

        NSStackView *content = [NSStackView stackViewWithViews:@[_dot, text]];
        content.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        content.alignment = NSLayoutAttributeCenterY;
        content.spacing = 9;
        content.edgeInsets = NSEdgeInsetsMake(10, 13, 10, 13);
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [content.topAnchor constraintEqualToAnchor:self.topAnchor],
            [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
    }
    return self;
}

- (void)setTitle:(NSString *)title detail:(NSString *)detail severity:(UISeverity)severity {
    NSColor *color = UISeverityColor(severity);
    _titleLabel.stringValue = title;
    _detailLabel.stringValue = detail;
    _dot.layer.backgroundColor = color.CGColor;
    _dot.layer.cornerRadius = 5.0;
    self.fillColor = [color colorWithAlphaComponent:0.08];
    self.borderColor = [color colorWithAlphaComponent:0.34];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", title, detail];
}

@end

@interface SparklineView : NSView
@property(nonatomic, copy) NSArray<NSNumber *> *values;
@property(nonatomic) NSColor *strokeColor;
@end

@implementation SparklineView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _values = @[];
        _strokeColor = [NSColor systemBlueColor];
        self.accessibilityRole = NSAccessibilityImageRole;
        self.accessibilityLabel = @"CPU 60 秒走势";
    }
    return self;
}

- (void)setValues:(NSArray<NSNumber *> *)values {
    _values = [values copy];
    [self setNeedsDisplay:YES];
}

- (void)setStrokeColor:(NSColor *)strokeColor {
    _strokeColor = strokeColor;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 2, 4);
    [[NSColor.separatorColor colorWithAlphaComponent:0.4] setStroke];
    NSBezierPath *baseline = [NSBezierPath bezierPath];
    [baseline moveToPoint:NSMakePoint(NSMinX(bounds), NSMinY(bounds))];
    [baseline lineToPoint:NSMakePoint(NSMaxX(bounds), NSMinY(bounds))];
    baseline.lineWidth = 1.0;
    [baseline stroke];

    if (_values.count == 0)
        return;

    CGFloat width = NSWidth(bounds);
    CGFloat height = NSHeight(bounds);
    NSBezierPath *line = [NSBezierPath bezierPath];
    NSPoint lastPoint = NSZeroPoint;
    for (NSUInteger i = 0; i < _values.count; i++) {
        CGFloat value = MIN(100.0, MAX(0.0, _values[i].doubleValue));
        CGFloat x = NSMinX(bounds) + (_values.count == 1 ? width / 2.0
                                                        : width * i / (_values.count - 1));
        CGFloat y = NSMinY(bounds) + height * value / 100.0;
        NSPoint point = NSMakePoint(x, y);
        lastPoint = point;
        if (i == 0)
            [line moveToPoint:point];
        else
            [line lineToPoint:point];
    }

    NSBezierPath *fill = [line copy];
    [fill lineToPoint:NSMakePoint(NSMaxX(bounds), NSMinY(bounds))];
    [fill lineToPoint:NSMakePoint(NSMinX(bounds), NSMinY(bounds))];
    [fill closePath];
    [[_strokeColor colorWithAlphaComponent:0.12] setFill];
    [fill fill];

    [_strokeColor setStroke];
    line.lineWidth = 2.0;
    [line stroke];
    [[_strokeColor colorWithAlphaComponent:0.8] setFill];
    NSRect marker = NSMakeRect(lastPoint.x - 3, lastPoint.y - 3, 6, 6);
    [[NSBezierPath bezierPathWithOvalInRect:marker] fill];
}

@end

@interface MacMonitorApp : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic) monitor_core_t *core;
@property(nonatomic) core_snapshot_t snapshot;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSMutableArray<MetricCardView *> *metricCards;
@property(nonatomic) StatusBannerView *healthBanner;
@property(nonatomic) InfoTileView *loadTile;
@property(nonatomic) InfoTileView *processTile;
@property(nonatomic) InfoTileView *uptimeTile;
@property(nonatomic) InfoTileView *fanTile;
@property(nonatomic) SparklineView *sparkline;
@property(nonatomic) NSTextField *history;
@property(nonatomic) NSTextField *chartValue;
@property(nonatomic) NSTextField *subtitle;
@property(nonatomic) NSTextField *processSectionHint;
@property(nonatomic) NSTextField *emptyState;
@property(nonatomic) NSTableView *table;
@property(nonatomic) proc_sort_t sort;
@end

@implementation MacMonitorApp

- (NSTextField *)label:(NSString *)text size:(CGFloat)size {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:NSFontWeightRegular];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSTextField *)valueLabel:(NSString *)text size:(CGFloat)size {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
    label.textColor = [NSColor secondaryLabelColor];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSTextField *)sectionLabel:(NSString *)text {
    NSTextField *label = [self label:text size:11];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSBox *)separator {
    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    return separator;
}

- (NSString *)fanSummary {
    if (_snapshot.stale_mask & CORE_STALE_FAN)
        return @"数据陈旧";
    if (!_snapshot.has_fans || _snapshot.fans.count <= 0)
        return @"无传感器或不可用";

    NSMutableString *summary = [NSMutableString string];
    for (int i = 0; i < _snapshot.fans.count && i < SMC_MAX_FANS; i++) {
        if (i > 0)
            [summary appendString:@"   "];
        [summary appendFormat:@"风扇 %d %.0f RPM", i + 1, _snapshot.fans.rpm[i]];
    }
    return summary;
}

- (NSString *)uptimeSummary {
    if (_snapshot.uptime < 0)
        return @"运行时间不可用";
    long uptime = _snapshot.uptime;
    return [NSString stringWithFormat:@"%ldd %02ldh %02ldm", uptime / 86400,
        (uptime % 86400) / 3600, (uptime % 3600) / 60];
}

- (void)updateTableHeaders {
    NSDictionary *titles = @{
        @"pid": @"进程号",
        @"name": @"进程",
        @"cpu": @"CPU 占用",
        @"mem": @"内存",
    };
    for (NSTableColumn *column in self.table.tableColumns) {
        NSString *title = titles[column.identifier] ?: column.identifier;
        if ((self.sort == PROC_SORT_MEM && [column.identifier isEqualToString:@"mem"]) ||
            (self.sort == PROC_SORT_CPU && [column.identifier isEqualToString:@"cpu"]))
            title = [title stringByAppendingString:@" ↓"];
        column.title = title;
    }
    self.processSectionHint.stringValue = self.sort == PROC_SORT_MEM
        ? @"按内存占用排序" : @"按 CPU 占用排序";
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

    NSRect frame = NSMakeRect(0, 0, 980, 760);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    window.title = @"MacMonitor";
    window.minSize = NSMakeSize(520, 360);

    NSScrollView *mainScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    mainScroll.hasVerticalScroller = YES;
    mainScroll.hasHorizontalScroller = NO;
    mainScroll.autohidesScrollers = YES;
    mainScroll.borderType = NSNoBorder;
    mainScroll.drawsBackground = NO;
    mainScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:mainScroll];
    [NSLayoutConstraint activateConstraints:@[
        [mainScroll.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
        [mainScroll.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
        [mainScroll.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
        [mainScroll.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor]
    ]];

    NSView *document = [[NSView alloc] initWithFrame:NSZeroRect];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [mainScroll setDocumentView:document];
    [NSLayoutConstraint activateConstraints:@[
        [document.leadingAnchor constraintEqualToAnchor:mainScroll.contentView.leadingAnchor],
        [document.trailingAnchor constraintEqualToAnchor:mainScroll.contentView.trailingAnchor],
        [document.topAnchor constraintEqualToAnchor:mainScroll.contentView.topAnchor],
        [document.widthAnchor constraintEqualToAnchor:mainScroll.contentView.widthAnchor]
    ]];

    NSStackView *root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeWidth;
    root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(22, 24, 24, 24);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:document.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:document.bottomAnchor]
    ]];

    NSStackView *header = [NSStackView stackViewWithViews:@[]];
    header.orientation = NSUserInterfaceLayoutOrientationVertical;
    header.alignment = NSLayoutAttributeLeading;
    header.spacing = 3;
    NSTextField *title = [self label:@"MacMonitor" size:26];
    title.font = [NSFont systemFontOfSize:26 weight:NSFontWeightSemibold];
    [header addArrangedSubview:title];
    self.subtitle = [self label:@"实时系统状态 · 实时更新" size:12];
    self.subtitle.textColor = [NSColor secondaryLabelColor];
    [header addArrangedSubview:self.subtitle];
    [root addArrangedSubview:header];

    self.healthBanner = [[StatusBannerView alloc] initWithFrame:NSZeroRect];
    [self.healthBanner setTitle:@"正在读取系统状态…"
                          detail:@"等待采样核心发布快照"
                        severity:UISeverityNeutral];
    [root addArrangedSubview:self.healthBanner];

    [root addArrangedSubview:[self sectionLabel:@"系统资源"]];
    self.metricCards = [NSMutableArray arrayWithCapacity:METRIC_COUNT];
    for (NSString *titleText in @[@"CPU", @"内存", @"交换空间", @"磁盘"])
        [self.metricCards addObject:[[MetricCardView alloc] initWithTitle:titleText]];
    AdaptiveGridView *metrics = [[AdaptiveGridView alloc]
        initWithItems:self.metricCards wideColumns:2 compactColumns:2 compactThreshold:760
        itemHeight:104 spacing:10 columnSpacing:12];
    [root addArrangedSubview:metrics];

    [root addArrangedSubview:[self separator]];
    [root addArrangedSubview:[self sectionLabel:@"运行状态"]];
    self.loadTile = [[InfoTileView alloc] initWithTitle:@"系统负载"];
    self.processTile = [[InfoTileView alloc] initWithTitle:@"进程数量"];
    self.uptimeTile = [[InfoTileView alloc] initWithTitle:@"运行时间"];
    self.fanTile = [[InfoTileView alloc] initWithTitle:@"风扇转速"];
    AdaptiveGridView *statusTiles = [[AdaptiveGridView alloc]
        initWithItems:@[self.loadTile, self.processTile, self.uptimeTile, self.fanTile]
        wideColumns:4 compactColumns:2 compactThreshold:760
        itemHeight:62 spacing:10 columnSpacing:10];
    [root addArrangedSubview:statusTiles];

    [root addArrangedSubview:[self separator]];
    [root addArrangedSubview:[self sectionLabel:@"CPU 走势（60 秒）"]];
    RoundedPanelView *chartPanel = [[RoundedPanelView alloc] initWithFrame:NSZeroRect];
    NSStackView *chartContent = [NSStackView stackViewWithViews:@[]];
    chartContent.orientation = NSUserInterfaceLayoutOrientationVertical;
    chartContent.alignment = NSLayoutAttributeWidth;
    chartContent.spacing = 5;
    chartContent.edgeInsets = NSEdgeInsetsMake(10, 13, 10, 13);
    chartContent.translatesAutoresizingMaskIntoConstraints = NO;
    [chartPanel addSubview:chartContent];
    [NSLayoutConstraint activateConstraints:@[
        [chartContent.leadingAnchor constraintEqualToAnchor:chartPanel.leadingAnchor],
        [chartContent.trailingAnchor constraintEqualToAnchor:chartPanel.trailingAnchor],
        [chartContent.topAnchor constraintEqualToAnchor:chartPanel.topAnchor],
        [chartContent.bottomAnchor constraintEqualToAnchor:chartPanel.bottomAnchor]
    ]];
    NSStackView *chartHeader = [NSStackView stackViewWithViews:@[]];
    chartHeader.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    chartHeader.alignment = NSLayoutAttributeCenterY;
    chartHeader.distribution = NSStackViewDistributionFill;
    NSTextField *chartTitle = [self label:@"最近 60 秒 CPU 使用率" size:12];
    chartTitle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.chartValue = [self valueLabel:@"暂无数据" size:11];
    self.chartValue.alignment = NSTextAlignmentRight;
    [self.chartValue setContentHuggingPriority:NSLayoutPriorityRequired
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    [chartHeader addArrangedSubview:chartTitle];
    [chartHeader addArrangedSubview:self.chartValue];
    [chartContent addArrangedSubview:chartHeader];
    self.sparkline = [[SparklineView alloc] initWithFrame:NSZeroRect];
    [self.sparkline.heightAnchor constraintEqualToConstant:58].active = YES;
    [chartContent addArrangedSubview:self.sparkline];
    self.history = [self valueLabel:@"暂无数据" size:10];
    self.history.textColor = [NSColor tertiaryLabelColor];
    [chartContent addArrangedSubview:self.history];
    [chartPanel.heightAnchor constraintGreaterThanOrEqualToConstant:110].active = YES;
    [root addArrangedSubview:chartPanel];

    [root addArrangedSubview:[self separator]];
    NSStackView *processHeader = [NSStackView stackViewWithViews:@[]];
    processHeader.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    processHeader.alignment = NSLayoutAttributeCenterY;
    NSTextField *processTitle = [self sectionLabel:@"进程列表"];
    [processTitle setContentHuggingPriority:NSLayoutPriorityRequired
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.processSectionHint = [self valueLabel:@"按 CPU 占用排序" size:10];
    self.processSectionHint.alignment = NSTextAlignmentLeft;
    [self.processSectionHint setContentHuggingPriority:NSLayoutPriorityRequired
                                                forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSView *processSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [processSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [processSpacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    [processHeader addArrangedSubview:processTitle];
    [processHeader addArrangedSubview:self.processSectionHint];
    [processHeader addArrangedSubview:processSpacer];
    [root addArrangedSubview:processHeader];

    self.table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    self.table.rowHeight = 27;
    self.table.intercellSpacing = NSMakeSize(12, 0);
    self.table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    self.table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    NSArray *specs = @[
        @[@"pid", @"进程号", @70], @[@"name", @"进程", @300],
        @[@"cpu", @"CPU 占用", @100], @[@"mem", @"内存", @100]
    ];
    for (NSArray *spec in specs) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        column.headerCell.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        column.headerCell.textColor = [NSColor secondaryLabelColor];
        column.headerCell.alignment = [column.identifier isEqualToString:@"name"]
            ? NSTextAlignmentLeft : NSTextAlignmentRight;
        [self.table addTableColumn:column];
    }

    NSScrollView *tableScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    tableScroll.documentView = self.table;
    tableScroll.hasVerticalScroller = YES;
    tableScroll.autohidesScrollers = YES;
    tableScroll.drawsBackground = NO;
    tableScroll.borderType = NSNoBorder;
    tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *tableWrapper = [[NSView alloc] initWithFrame:NSZeroRect];
    tableWrapper.translatesAutoresizingMaskIntoConstraints = NO;
    [tableWrapper addSubview:tableScroll];
    [NSLayoutConstraint activateConstraints:@[
        [tableScroll.leadingAnchor constraintEqualToAnchor:tableWrapper.leadingAnchor],
        [tableScroll.trailingAnchor constraintEqualToAnchor:tableWrapper.trailingAnchor],
        [tableScroll.topAnchor constraintEqualToAnchor:tableWrapper.topAnchor],
        [tableScroll.bottomAnchor constraintEqualToAnchor:tableWrapper.bottomAnchor]
    ]];
    self.emptyState = [self label:@"暂无进程数据" size:13];
    self.emptyState.alignment = NSTextAlignmentCenter;
    self.emptyState.textColor = [NSColor secondaryLabelColor];
    self.emptyState.translatesAutoresizingMaskIntoConstraints = NO;
    [tableWrapper addSubview:self.emptyState];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyState.leadingAnchor constraintGreaterThanOrEqualToAnchor:tableWrapper.leadingAnchor
                                                                   constant:20],
        [self.emptyState.trailingAnchor constraintLessThanOrEqualToAnchor:tableWrapper.trailingAnchor
                                                                    constant:-20],
        [self.emptyState.centerXAnchor constraintEqualToAnchor:tableWrapper.centerXAnchor],
        [self.emptyState.centerYAnchor constraintEqualToAnchor:tableWrapper.centerYAnchor]
    ]];
    [root addArrangedSubview:tableWrapper];
    [tableWrapper.heightAnchor constraintGreaterThanOrEqualToConstant:170].active = YES;

    [self updateTableHeaders];
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

    const BOOL cpuAvailable = !(_snapshot.stale_mask & CORE_STALE_CPU);
    const BOOL memAvailable = !(_snapshot.stale_mask & CORE_STALE_MEM) && _snapshot.mem.total > 0;
    const BOOL swapAvailable = !(_snapshot.stale_mask & CORE_STALE_MEM) && _snapshot.mem.swap_total > 0;
    const BOOL diskAvailable = !(_snapshot.stale_mask & CORE_STALE_DISK) && _snapshot.disk.total > 0;
    const BOOL cpuStale = (_snapshot.stale_mask & CORE_STALE_CPU) != 0;
    const BOOL memStale = (_snapshot.stale_mask & CORE_STALE_MEM) != 0;
    const BOOL diskStale = (_snapshot.stale_mask & CORE_STALE_DISK) != 0;

    double memUsed = (double)(_snapshot.mem.app + _snapshot.mem.wired + _snapshot.mem.compressed);
    double memPct = memAvailable ? 100.0 * memUsed / _snapshot.mem.total : 0.0;
    double swapPct = swapAvailable ? 100.0 * _snapshot.mem.swap_used / _snapshot.mem.swap_total : 0.0;
    double diskPct = diskAvailable ? 100.0 * _snapshot.disk.used / _snapshot.disk.total : 0.0;

    NSString *cpuValue = cpuAvailable
        ? [NSString stringWithFormat:@"%.1f%%", _snapshot.cpu.busy] : @"数据陈旧";
    NSString *cpuDetail = cpuAvailable
        ? [NSString stringWithFormat:@"用户 %.1f · 系统 %.1f · 空闲 %.1f",
            _snapshot.cpu.user, _snapshot.cpu.system, _snapshot.cpu.idle]
        : @"本项数据暂不可用";
    [self.metricCards[METRIC_CPU] setPercent:_snapshot.cpu.busy value:cpuValue detail:cpuDetail
        state:cpuStale ? @"数据陈旧" : (cpuAvailable ? @"正常" : @"不可用")
        severity:cpuStale ? UISeverityWarning : (cpuAvailable ? UISeverityNormal : UISeverityError)];

    NSString *memValue = memAvailable
        ? [NSString stringWithFormat:@"%.1f%%", memPct]
        : (memStale ? @"数据陈旧" : @"不可用");
    NSString *memDetail = memAvailable
        ? [NSString stringWithFormat:@"已用 %.1fG / %.1fG", memUsed / 1073741824.0,
            _snapshot.mem.total / 1073741824.0] : @"本项数据暂不可用";
    [self.metricCards[METRIC_MEMORY] setPercent:memPct value:memValue detail:memDetail
        state:memStale ? @"数据陈旧" : (memAvailable ? @"正常" : @"不可用")
        severity:memStale ? UISeverityWarning : (memAvailable ? UISeverityNormal : UISeverityError)];

    NSString *swapValue = swapAvailable
        ? [NSString stringWithFormat:@"%.1f%%", swapPct] : @"未启用";
    NSString *swapDetail = swapAvailable
        ? [NSString stringWithFormat:@"已用 %.1fG / %.1fG", _snapshot.mem.swap_used / 1073741824.0,
            _snapshot.mem.swap_total / 1073741824.0] : @"系统未配置交换空间";
    [self.metricCards[METRIC_SWAP] setPercent:swapPct value:swapValue detail:swapDetail
        state:memStale ? @"数据陈旧" : (swapAvailable ? @"正常" : @"未启用")
        severity:memStale ? UISeverityWarning : (swapAvailable ? UISeverityNormal : UISeverityNeutral)];

    NSString *diskValue = diskAvailable
        ? [NSString stringWithFormat:@"%.1f%%", diskPct]
        : (diskStale ? @"数据陈旧" : @"不可用");
    NSString *diskDetail = diskAvailable
        ? [NSString stringWithFormat:@"已用 %.1fG / %.1fG", _snapshot.disk.used / 1073741824.0,
            _snapshot.disk.total / 1073741824.0] : @"本项数据暂不可用";
    [self.metricCards[METRIC_DISK] setPercent:diskPct value:diskValue detail:diskDetail
        state:diskStale ? @"数据陈旧" : (diskAvailable ? @"正常" : @"不可用")
        severity:diskStale ? UISeverityWarning : (diskAvailable ? UISeverityNormal : UISeverityError)];

    NSInteger availableCount = (cpuAvailable ? 1 : 0) + (memAvailable ? 1 : 0) +
        (swapAvailable ? 1 : 0) + (diskAvailable ? 1 : 0);
    UISeverity overallSeverity = availableCount == 0 ? UISeverityError
        : ((_snapshot.stale_mask || _snapshot.paused || availableCount < METRIC_COUNT)
            ? UISeverityWarning : UISeverityNormal);
    NSString *overallTitle = availableCount == 0 ? @"数据不可用"
        : (_snapshot.paused ? @"采样已暂停"
        : (_snapshot.stale_mask || availableCount < METRIC_COUNT ? @"部分数据需要关注" : @"系统状态正常"));
    NSString *overallDetail = [NSString stringWithFormat:@"%ld/4 项指标可用 · %d 个进程 · %@",
        (long)availableCount, _snapshot.proc_total,
        _snapshot.paused ? @"暂停中" : @"实时更新"];
    [self.healthBanner setTitle:overallTitle detail:overallDetail severity:overallSeverity];

    UISeverity loadSeverity = (_snapshot.stale_mask & CORE_STALE_LOAD)
        ? UISeverityWarning : UISeverityNormal;
    NSString *loadValue = loadSeverity == UISeverityNormal
        ? [NSString stringWithFormat:@"%.2f  %.2f  %.2f", _snapshot.load[0], _snapshot.load[1],
            _snapshot.load[2]] : @"数据陈旧";
    [self.loadTile setValueText:loadValue severity:loadSeverity];

    UISeverity processSeverity = (_snapshot.stale_mask & CORE_STALE_PROC)
        ? UISeverityWarning : UISeverityNormal;
    [self.processTile setValueText:processSeverity == UISeverityNormal
        ? [NSString stringWithFormat:@"%d 个", _snapshot.proc_total] : @"数据陈旧"
        severity:processSeverity];

    UISeverity uptimeSeverity = (_snapshot.stale_mask & CORE_STALE_UP) || _snapshot.uptime < 0
        ? UISeverityWarning : UISeverityNormal;
    [self.uptimeTile setValueText:uptimeSeverity == UISeverityNormal
        ? [self uptimeSummary] : @"运行时间不可用" severity:uptimeSeverity];

    BOOL fanAvailable = _snapshot.has_fans && _snapshot.fans.count > 0;
    UISeverity fanSeverity = (_snapshot.stale_mask & CORE_STALE_FAN)
        ? UISeverityWarning : (fanAvailable ? UISeverityNormal : UISeverityNeutral);
    [self.fanTile setValueText:[self fanSummary] severity:fanSeverity];

    NSMutableArray<NSNumber *> *historyValues = [NSMutableArray arrayWithCapacity:_snapshot.history_len];
    for (int i = 0; i < _snapshot.history_len; i++) {
        int index = (_snapshot.history_head - _snapshot.history_len + i + CORE_CPU_HISTORY)
            % CORE_CPU_HISTORY;
        [historyValues addObject:@(_snapshot.history[index])];
    }
    self.sparkline.values = historyValues;
    self.sparkline.strokeColor = cpuStale ? [NSColor systemOrangeColor] : [NSColor systemBlueColor];
    self.chartValue.stringValue = cpuAvailable
        ? [NSString stringWithFormat:@"当前 %.1f%%", _snapshot.cpu.busy] : @"当前不可用";
    self.history.stringValue = _snapshot.history_len > 0
        ? [NSString stringWithFormat:@"已收集 %d 秒 · 数值范围 0–100%%", _snapshot.history_len]
        : @"暂无历史数据";

    BOOL processStale = (_snapshot.stale_mask & CORE_STALE_PROC) != 0;
    self.emptyState.hidden = _snapshot.proc_count > 0;
    if (_snapshot.proc_count == 0)
        self.emptyState.stringValue = processStale ? @"进程数据陈旧，暂时无法显示" : @"暂无进程数据";
    if (processStale)
        self.processSectionHint.stringValue = [NSString stringWithFormat:@"%@ · 数据陈旧",
            self.sort == PROC_SORT_MEM ? @"按内存占用排序" : @"按 CPU 占用排序"];
    else
        [self updateTableHeaders];
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
        text.translatesAutoresizingMaskIntoConstraints = NO;
        text.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:text];
        cell.textField = text;
        [NSLayoutConstraint activateConstraints:@[
            [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:5],
            [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-5],
            [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    proc_info_t p = _snapshot.procs[row];
    BOOL nameColumn = [column.identifier isEqualToString:@"name"];
    cell.textField.font = nameColumn
        ? [NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
        : [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    cell.textField.alignment = nameColumn ? NSTextAlignmentLeft : NSTextAlignmentRight;
    cell.textField.textColor = [NSColor labelColor];
    if ([column.identifier isEqualToString:@"pid"])
        cell.textField.stringValue = [NSString stringWithFormat:@"%d", p.pid];
    else if (nameColumn)
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
    [self updateTableHeaders];
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
