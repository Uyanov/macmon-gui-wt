#import <Cocoa/Cocoa.h>
#include "core.h"
#include "history.h"
#include <math.h>

enum {
    METRIC_CPU = 0,
    METRIC_MEMORY,
    METRIC_SWAP,
    METRIC_DISK,
    METRIC_NETWORK,
    METRIC_TEMPERATURE,
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
        return [NSColor colorWithSRGBRed:0.20 green:0.64 blue:0.40 alpha:1];
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
        _cornerRadius = 8.0;
        _borderWidth = 0.5;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    self.layer.cornerRadius = self.cornerRadius;
    self.layer.masksToBounds = YES;
    NSBezierPath *panel = [NSBezierPath bezierPathWithRoundedRect:
        NSInsetRect(self.bounds, self.borderWidth / 2, self.borderWidth / 2)
        xRadius:self.cornerRadius yRadius:self.cornerRadius];
    [self.fillColor setFill];
    [panel fill];
    [self.borderColor setStroke];
    panel.lineWidth = self.borderWidth;
    [panel stroke];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
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

@interface MonitorDocumentView : NSView
@end

@implementation MonitorDocumentView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(dirtyRect);
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
        [self rebuildRows:_wideColumns];
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
        [_stack addArrangedSubview:row];
        [row.heightAnchor constraintEqualToConstant:_itemHeight].active = YES;
        [row.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
        for (NSInteger index = start; index < start + columns && index < (NSInteger)_items.count;
             index++) {
            [row addArrangedSubview:_items[index]];
            [_items[index].heightAnchor constraintEqualToAnchor:row.heightAnchor].active = YES;
            if (index > start)
                [_items[index].widthAnchor constraintEqualToAnchor:_items[start].widthAnchor].active = YES;
        }
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

typedef NS_ENUM(NSInteger, CardIconKind) {
    CardIconCPU = 0,
    CardIconMemory,
    CardIconSwap,
    CardIconDisk,
    CardIconLoad,
    CardIconProcesses,
    CardIconUptime,
    CardIconFan,
    CardIconNetwork,
    CardIconTemperature,
};

/* 资源颜色用于识别指标，橙色和红色仍用于提示异常。 */
static NSColor *CardAccentColor(CardIconKind kind) {
    switch (kind) {
    case CardIconCPU: return NSColor.systemBlueColor;
    case CardIconMemory: return NSColor.systemTealColor;
    case CardIconSwap: return NSColor.systemPurpleColor;
    case CardIconDisk: return NSColor.systemIndigoColor;
    case CardIconLoad: return NSColor.systemBlueColor;
    case CardIconProcesses: return NSColor.systemTealColor;
    case CardIconUptime: return NSColor.systemIndigoColor;
    case CardIconFan: return NSColor.systemPurpleColor;
    case CardIconNetwork: return NSColor.systemTealColor;
    case CardIconTemperature: return NSColor.systemOrangeColor;
    }
    return NSColor.controlAccentColor;
}

@interface ResourceMeterView : NSView
@property(nonatomic) double doubleValue;
@property(nonatomic) NSColor *color;
@end

@implementation ResourceMeterView
- (void)setDoubleValue:(double)value {
    _doubleValue = value;
    self.needsDisplay = YES;
}
- (void)setColor:(NSColor *)color {
    _color = color;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSColor *color = self.color ?: NSColor.controlAccentColor;
    [[color colorWithAlphaComponent:0.12] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:3 yRadius:3] fill];
    NSRect fill = self.bounds;
    fill.size.width *= MIN(100.0, MAX(0.0, self.doubleValue)) / 100.0;
    if (fill.size.width > 0) {
        [color setFill];
        [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:3 yRadius:3] fill];
    }
}
@end

@interface CardIconView : NSImageView
- (instancetype)initWithKind:(CardIconKind)kind;
- (void)setKind:(CardIconKind)kind severity:(UISeverity)severity;
@end

@implementation CardIconView

- (instancetype)initWithKind:(CardIconKind)kind {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.imageScaling = NSImageScaleProportionallyDown;
        self.accessibilityRole = NSAccessibilityImageRole;
        [self.widthAnchor constraintEqualToConstant:20].active = YES;
        [self.heightAnchor constraintEqualToConstant:20].active = YES;
        [self setKind:kind severity:UISeverityNormal];
    }
    return self;
}

- (void)setKind:(CardIconKind)kind severity:(UISeverity)severity {
    NSArray<NSString *> *symbols = @[@"cpu", @"memorychip", @"arrow.left.arrow.right",
        @"internaldrive", @"waveform.path", @"list.bullet.rectangle", @"clock", @"fanblades",
        @"network", @"thermometer"];
    NSArray<NSString *> *labels = @[@"CPU", @"内存", @"交换空间", @"磁盘",
        @"系统负载", @"进程数量", @"运行时间", @"风扇转速", @"网络吞吐量", @"CPU 温度"];
    NSImage *image = [NSImage imageWithSystemSymbolName:symbols[kind]
                              accessibilityDescription:labels[kind]];
    self.image = [image imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightMedium]];
    self.contentTintColor = severity == UISeverityNormal ? CardAccentColor(kind)
                                                         : UISeverityColor(severity);
    self.accessibilityLabel = labels[kind];
    self.toolTip = labels[kind];
}

@end

@interface SparklineView : NSView
@property(nonatomic, copy) NSArray<NSArray<NSNumber *> *> *series;
@property(nonatomic) NSColor *strokeColor;
@property(nonatomic, copy) NSArray<NSColor *> *strokeColors;
@property(nonatomic) double minimumValue;
@property(nonatomic) double maximumValue;
@property(nonatomic, copy) NSString *emptyText;
@property(nonatomic) BOOL durationStyle;
@property(nonatomic, copy) NSArray<NSNumber *> *times;
@property(nonatomic, copy) NSArray<NSArray<NSNumber *> *> *breaks;
@property(nonatomic) double windowEnd;
- (void)setValues:(NSArray<NSNumber *> *)values
          minimum:(double)minimum
          maximum:(double)maximum
        emptyText:(NSString *)emptyText;
- (void)setSeries:(NSArray<NSArray<NSNumber *> *> *)series
          minimum:(double)minimum
          maximum:(double)maximum
        emptyText:(NSString *)emptyText;
@end

@implementation SparklineView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _series = @[];
        _strokeColor = [NSColor systemBlueColor];
        _strokeColors = @[];
        _minimumValue = 0.0;
        _maximumValue = 100.0;
        _emptyText = @"暂无历史";
        self.accessibilityRole = NSAccessibilityImageRole;
        self.accessibilityLabel = @"卡片趋势图";
    }
    return self;
}

- (void)setValues:(NSArray<NSNumber *> *)values
          minimum:(double)minimum
          maximum:(double)maximum
        emptyText:(NSString *)emptyText {
    [self setSeries:values.count > 0 ? @[values] : @[] minimum:minimum maximum:maximum
          emptyText:emptyText];
}

- (void)setSeries:(NSArray<NSArray<NSNumber *> *> *)series
          minimum:(double)minimum
          maximum:(double)maximum
        emptyText:(NSString *)emptyText {
    _series = [series copy] ?: @[];
    _times = @[];
    _breaks = @[];
    _minimumValue = minimum;
    _maximumValue = maximum;
    _emptyText = [emptyText copy] ?: @"暂无历史";
    [self setNeedsDisplay:YES];
}

- (void)setStrokeColor:(NSColor *)strokeColor {
    _strokeColor = strokeColor ?: [NSColor systemBlueColor];
    [self setNeedsDisplay:YES];
}

- (void)setStrokeColors:(NSArray<NSColor *> *)strokeColors {
    _strokeColors = [strokeColors copy] ?: @[];
    [self setNeedsDisplay:YES];
}

- (void)drawDurationStyleInBounds:(NSRect)bounds {
    NSColor *color = self.strokeColor;
    [color setStroke];
    NSBezierPath *line = [NSBezierPath bezierPath];
    line.lineWidth = 1.4;
    [line moveToPoint:NSMakePoint(NSMinX(bounds), NSMidY(bounds))];
    [line lineToPoint:NSMakePoint(NSMaxX(bounds), NSMidY(bounds))];
    [line stroke];
    for (NSInteger i = 0; i < 5; i++) {
        CGFloat x = NSMinX(bounds) + (NSWidth(bounds) * i / 4.0);
        NSBezierPath *tick = [NSBezierPath bezierPath];
        [tick moveToPoint:NSMakePoint(x, NSMidY(bounds) - 4)];
        [tick lineToPoint:NSMakePoint(x, NSMidY(bounds) + 4)];
        tick.lineWidth = i == 4 ? 2.0 : 1.0;
        [tick stroke];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 3, 3);
    if (self.durationStyle) {
        [self drawDurationStyleInBounds:bounds];
        return;
    }

    [[NSColor.separatorColor colorWithAlphaComponent:0.35] setStroke];
    NSBezierPath *baseline = [NSBezierPath bezierPath];
    [baseline moveToPoint:NSMakePoint(NSMinX(bounds), NSMinY(bounds))];
    [baseline lineToPoint:NSMakePoint(NSMaxX(bounds), NSMinY(bounds))];
    baseline.lineWidth = 1.0;
    [baseline stroke];

    if (self.series.count == 0) {
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:9],
            NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
        };
        [self.emptyText drawAtPoint:NSMakePoint(NSMinX(bounds), NSMinY(bounds) + 1)
                      withAttributes:attributes];
        return;
    }

    double minimum = self.minimumValue;
    double maximum = self.maximumValue;
    if (!isfinite(minimum)) minimum = 0.0;
    if (!isfinite(maximum) || maximum <= minimum) {
        maximum = minimum + 1.0;
        for (NSArray<NSNumber *> *values in self.series) {
            for (NSNumber *number in values) {
                if (isfinite(number.doubleValue))
                    maximum = MAX(maximum, number.doubleValue);
            }
        }
        if (maximum <= minimum)
            maximum = minimum + 1.0;
    }

    CGFloat width = NSWidth(bounds);
    CGFloat height = NSHeight(bounds);
    for (NSUInteger seriesIndex = 0; seriesIndex < self.series.count; seriesIndex++) {
        NSArray<NSNumber *> *values = self.series[seriesIndex];
        if (values.count == 0)
            continue;
        NSColor *color = seriesIndex < self.strokeColors.count
            ? self.strokeColors[seriesIndex] : self.strokeColor;
        NSBezierPath *line = [NSBezierPath bezierPath];
        line.lineWidth = self.series.count > 1 ? 1.5 : 2.0;
        line.lineJoinStyle = NSLineJoinStyleRound;
        line.lineCapStyle = NSLineCapStyleRound;
        NSPoint firstPoint = NSZeroPoint;
        NSPoint lastPoint = NSZeroPoint;
        BOOL hasPoint = NO;
        BOOL segmentStarted = NO;
        BOOL continuous = YES;
        for (NSUInteger i = 0; i < values.count; i++) {
            double raw = values[i].doubleValue;
            if (!isfinite(raw)) {
                segmentStarted = NO;
                continuous = NO;
                continue;
            }
            double normalized = (raw - minimum) / (maximum - minimum);
            normalized = MIN(1.0, MAX(0.0, normalized));
            CGFloat x = NSMinX(bounds) + (values.count == 1 ? width / 2.0
                                                   : width * i / (values.count - 1));
            if (self.times.count == values.count)
                x = NSMinX(bounds) + width * MIN(1.0, MAX(0.0,
                    (self.times[i].doubleValue - self.windowEnd + METRIC_HISTORY_SECONDS) / METRIC_HISTORY_SECONDS));
            CGFloat y = NSMinY(bounds) + height * normalized;
            NSPoint point = NSMakePoint(x, y);
            BOOL breakBefore = seriesIndex < self.breaks.count && i < self.breaks[seriesIndex].count &&
                self.breaks[seriesIndex][i].boolValue;
            if (breakBefore) continuous = NO;
            if (!hasPoint) firstPoint = point;
            if (!segmentStarted || breakBefore) {
                [line moveToPoint:point];
            } else
                [line lineToPoint:point];
            lastPoint = point;
            hasPoint = YES;
            segmentStarted = YES;
        }
        if (!hasPoint)
            continue;
        if (continuous && self.series.count == 1 && values.count > 1) {
            NSBezierPath *area = [line copy];
            [area lineToPoint:NSMakePoint(lastPoint.x, NSMinY(bounds))];
            [area lineToPoint:NSMakePoint(firstPoint.x, NSMinY(bounds))];
            [area closePath];
            NSGradient *gradient = [[NSGradient alloc]
                initWithStartingColor:[color colorWithAlphaComponent:0.02]
                          endingColor:[color colorWithAlphaComponent:0.20]];
            [gradient drawInBezierPath:area angle:90];
        }
        [color setStroke];
        [line stroke];
        NSRect marker = NSMakeRect(lastPoint.x - 2, lastPoint.y - 2, 4, 4);
        [color setFill];
        [[NSBezierPath bezierPathWithOvalInRect:marker] fill];
    }
}

@end

@interface MetricCardView : RoundedPanelView
@property(nonatomic, readonly) NSString *metricTitle;
- (instancetype)initWithTitle:(NSString *)title kind:(CardIconKind)kind;
- (void)setPercent:(double)percent
             value:(NSString *)value
            detail:(NSString *)detail
             state:(NSString *)state
          severity:(UISeverity)severity;
- (void)setChartValues:(NSArray<NSNumber *> *)values
                minimum:(double)minimum
                maximum:(double)maximum
              emptyText:(NSString *)emptyText;
- (void)setTimedHistory:(const metric_history_t *)history network:(BOOL)network emptyText:(NSString *)text;
@end

@implementation MetricCardView {
    CardIconKind _kind;
    CardIconView *_icon;
    SparklineView *_sparkline;
    NSTextField *_titleLabel;
    NSTextField *_stateLabel;
    NSTextField *_valueLabel;
    NSTextField *_detailLabel;
    ResourceMeterView *_progress;
}

- (instancetype)initWithTitle:(NSString *)title kind:(CardIconKind)kind {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _metricTitle = [title copy];
        _kind = kind;
        self.accessibilityRole = NSAccessibilityGroupRole;

        _icon = [[CardIconView alloc] initWithKind:kind];
        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        _titleLabel.textColor = [NSColor secondaryLabelColor];
        _titleLabel.alignment = NSTextAlignmentLeft;
        [_titleLabel setContentHuggingPriority:NSLayoutPriorityRequired
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];

        _stateLabel = [NSTextField labelWithString:@"正常"];
        _stateLabel.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
        _stateLabel.alignment = NSTextAlignmentLeft;
        [_stateLabel setContentHuggingPriority:NSLayoutPriorityRequired
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSView *titleSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
        [titleSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        [titleSpacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *titleRow = [NSStackView stackViewWithViews:@[_icon, _titleLabel, titleSpacer, _stateLabel]];
        titleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        titleRow.alignment = NSLayoutAttributeCenterY;
        titleRow.spacing = 5;
        titleRow.distribution = NSStackViewDistributionFill;

        _valueLabel = [NSTextField labelWithString:@"不可用"];
        _valueLabel.font = [NSFont monospacedDigitSystemFontOfSize:28 weight:NSFontWeightSemibold];
        _valueLabel.textColor = [NSColor labelColor];
        _valueLabel.alignment = NSTextAlignmentLeft;
        _valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        if (kind == CardIconNetwork) {
        _valueLabel.font = [NSFont monospacedDigitSystemFontOfSize:16 weight:NSFontWeightSemibold];
            _valueLabel.maximumNumberOfLines = 2;
        }

        _progress = [[ResourceMeterView alloc] initWithFrame:NSZeroRect];
        _progress.color = CardAccentColor(kind);
        _progress.translatesAutoresizingMaskIntoConstraints = NO;
        [_progress.heightAnchor constraintEqualToConstant:5].active = YES;

        _sparkline = [[SparklineView alloc] initWithFrame:NSZeroRect];
        [_sparkline.heightAnchor constraintEqualToConstant:32].active = YES;
        _detailLabel = [NSTextField labelWithString:@"暂无数据"];
        _detailLabel.font = [NSFont systemFontOfSize:10 weight:NSFontWeightRegular];
        _detailLabel.textColor = [NSColor secondaryLabelColor];
        _detailLabel.alignment = NSTextAlignmentLeft;
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _detailLabel.maximumNumberOfLines = 1;

        NSStackView *content = [NSStackView stackViewWithViews:@[
            titleRow, _valueLabel, _progress, _sparkline, _detailLabel
        ]];
        content.orientation = NSUserInterfaceLayoutOrientationVertical;
        content.alignment = NSLayoutAttributeLeading;
        content.spacing = 6;
        content.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [content.topAnchor constraintEqualToAnchor:self.topAnchor],
            [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
        [NSLayoutConstraint activateConstraints:@[
            [titleRow.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-28],
            [_valueLabel.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-28],
            [_progress.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-28],
            [_sparkline.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-28],
            [_detailLabel.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-28]
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
    _valueLabel.toolTip = value;
    _detailLabel.stringValue = detail;
    _detailLabel.toolTip = detail;
    _valueLabel.textColor = severity == UISeverityNormal ? [NSColor labelColor] : color;
    NSColor *accent = severity == UISeverityNormal ? CardAccentColor(_kind) : color;
    _sparkline.strokeColor = accent;
    _progress.color = accent;
    _progress.doubleValue = MIN(100.0, MAX(0.0, percent));
    /* 陈旧或缺失的读数不显示占用条；高占用仍应显示完整读数。 */
    _progress.hidden = ![value hasSuffix:@"%"];
    [_icon setKind:_kind severity:severity];
    self.borderColor = severity == UISeverityNormal ? NSColor.separatorColor
        : [color colorWithAlphaComponent:0.4];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@ %@，%@，%@", _metricTitle, value, detail, state];
}

- (void)setChartValues:(NSArray<NSNumber *> *)values
                minimum:(double)minimum
                maximum:(double)maximum
              emptyText:(NSString *)emptyText {
    [_sparkline setValues:values minimum:minimum maximum:maximum emptyText:emptyText];
}

- (void)setTimedHistory:(const metric_history_t *)history network:(BOOL)network emptyText:(NSString *)text {
    NSMutableArray *times = [NSMutableArray array];
    NSMutableArray *series = [NSMutableArray array];
    NSMutableArray *breaks = [NSMutableArray array];
    BOOL hasValid = NO;
    double minimum = 0, maximum = network ? NAN : 120;
    for (int metric = network ? HISTORY_DOWNLOAD : HISTORY_TEMPERATURE;
         metric <= (network ? HISTORY_UPLOAD : HISTORY_TEMPERATURE); metric++) {
        NSMutableArray *values = [NSMutableArray array];
        NSMutableArray *gaps = [NSMutableArray array];
        for (size_t i = 0; i < history->count; i++) {
            [values addObject:@(history->points[i].values[metric])];
            [gaps addObject:@((history->points[i].breaks & (1u << metric)) != 0)];
            if (isfinite(history->points[i].values[metric])) {
                hasValid = YES;
                minimum = MIN(minimum, history->points[i].values[metric]);
                if (!network) maximum = MAX(maximum, history->points[i].values[metric]);
            }
        }
        [series addObject:values];
        [breaks addObject:gaps];
    }
    for (size_t i = 0; i < history->count; i++) [times addObject:@(history->points[i].time)];
    [_sparkline setSeries:hasValid ? series : @[] minimum:minimum maximum:maximum emptyText:text];
    _sparkline.times = times;
    _sparkline.breaks = breaks;
    _sparkline.windowEnd = history->count ? history->points[history->count - 1].time : 0;
    _sparkline.strokeColors = network ? @[NSColor.systemBlueColor, NSColor.systemGreenColor] : @[];
    _sparkline.accessibilityLabel = network ? @"最近 60 秒，蓝色下载，绿色上传" : @"最近 60 秒 CPU 温度，单位摄氏度";
}

@end

@interface InfoTileView : RoundedPanelView
- (instancetype)initWithTitle:(NSString *)title kind:(CardIconKind)kind;
- (void)setValueText:(NSString *)value severity:(UISeverity)severity;
- (void)setChartSeries:(NSArray<NSArray<NSNumber *> *> *)series
               minimum:(double)minimum
               maximum:(double)maximum
             emptyText:(NSString *)emptyText;
- (void)setDurationChart;
@end

@implementation InfoTileView {
    CardIconKind _kind;
    CardIconView *_icon;
    SparklineView *_sparkline;
    NSTextField *_titleLabel;
    NSTextField *_valueLabel;
}

- (instancetype)initWithTitle:(NSString *)title kind:(CardIconKind)kind {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _kind = kind;
        _icon = [[CardIconView alloc] initWithKind:kind];
        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        _titleLabel.textColor = [NSColor secondaryLabelColor];
        _titleLabel.alignment = NSTextAlignmentLeft;
        NSView *titleSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
        [titleSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        [titleSpacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *titleRow = [NSStackView stackViewWithViews:@[_icon, _titleLabel, titleSpacer]];
        titleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        titleRow.alignment = NSLayoutAttributeCenterY;
        titleRow.spacing = 4;

        _valueLabel = [NSTextField labelWithString:@"暂无数据"];
        _valueLabel.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium];
        _valueLabel.textColor = [NSColor labelColor];
        _valueLabel.alignment = NSTextAlignmentLeft;
        _valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _valueLabel.maximumNumberOfLines = 1;
        _sparkline = [[SparklineView alloc] initWithFrame:NSZeroRect];
        [_sparkline.heightAnchor constraintEqualToConstant:22].active = YES;

        NSStackView *content = [NSStackView stackViewWithViews:@[titleRow, _valueLabel, _sparkline]];
        content.orientation = NSUserInterfaceLayoutOrientationVertical;
        content.alignment = NSLayoutAttributeLeading;
        content.spacing = 6;
        content.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [content.topAnchor constraintEqualToAnchor:self.topAnchor],
            [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
        [NSLayoutConstraint activateConstraints:@[
            [titleRow.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-28],
            [_valueLabel.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-28],
            [_sparkline.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-28]
        ]];

    }
    return self;
}

- (void)setValueText:(NSString *)value severity:(UISeverity)severity {
    NSColor *color = UISeverityColor(severity);
    _valueLabel.stringValue = value;
    _valueLabel.toolTip = value;
    _valueLabel.textColor = severity == UISeverityNormal ? [NSColor labelColor] : color;
    [_icon setKind:_kind severity:severity];
    self.borderColor = severity == UISeverityNormal ? NSColor.separatorColor
        : [color colorWithAlphaComponent:0.4];
    _sparkline.strokeColor = severity == UISeverityNormal ? CardAccentColor(_kind) : color;
    self.accessibilityValue = value;
}

- (void)setChartSeries:(NSArray<NSArray<NSNumber *> *> *)series
               minimum:(double)minimum
               maximum:(double)maximum
             emptyText:(NSString *)emptyText {
    _sparkline.durationStyle = NO;
    _sparkline.strokeColors = series.count > 1
        ? @[[NSColor systemBlueColor], [NSColor systemOrangeColor], [NSColor systemPurpleColor]]
        : @[];
    [_sparkline setSeries:series minimum:minimum maximum:maximum emptyText:emptyText];
}

- (void)setDurationChart {
    _sparkline.durationStyle = YES;
    [_sparkline setSeries:@[] minimum:0 maximum:1 emptyText:@""];
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
        _titleLabel.alignment = NSTextAlignmentLeft;

        _detailLabel = [NSTextField labelWithString:@"正在读取系统状态…"];
        _detailLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
        _detailLabel.textColor = [NSColor secondaryLabelColor];
        _detailLabel.alignment = NSTextAlignmentLeft;
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        NSStackView *text = [NSStackView stackViewWithViews:@[_titleLabel, _detailLabel]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeLeading;
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
    _detailLabel.toolTip = detail;
    _dot.layer.backgroundColor = color.CGColor;
    _dot.layer.cornerRadius = 5.0;
    self.fillColor = [color colorWithAlphaComponent:0.08];
    self.borderColor = [color colorWithAlphaComponent:0.34];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", title, detail];
}

@end

@interface MacMonitorApp : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic) monitor_core_t *core;
@property(nonatomic) core_snapshot_t snapshot;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSMutableArray<MetricCardView *> *metricCards;
@property(nonatomic) StatusBannerView *healthBanner;
@property(nonatomic) InfoTileView *loadTile;
@property(nonatomic) InfoTileView *processTile;
@property(nonatomic) InfoTileView *uptimeTile;
@property(nonatomic) InfoTileView *fanTile;
@property(nonatomic) NSTextField *subtitle;
@property(nonatomic) NSTextField *processSectionHint;
@property(nonatomic) NSTextField *emptyState;
@property(nonatomic) NSTableView *table;
@property(nonatomic) proc_sort_t sort;
@property(nonatomic) uint64_t lastHistorySequence;
@property(nonatomic) NSMutableArray<NSNumber *> *memoryHistory;
@property(nonatomic) NSMutableArray<NSNumber *> *swapHistory;
@property(nonatomic) NSMutableArray<NSNumber *> *diskHistory;
@property(nonatomic) NSMutableArray<NSNumber *> *load1History;
@property(nonatomic) NSMutableArray<NSNumber *> *load5History;
@property(nonatomic) NSMutableArray<NSNumber *> *load15History;
@property(nonatomic) NSMutableArray<NSNumber *> *processHistory;
@property(nonatomic) NSMutableArray<NSNumber *> *fanHistory;
@property(nonatomic) metric_history_t extendedHistory;
@end

@implementation MacMonitorApp

- (NSTextField *)label:(NSString *)text size:(CGFloat)size {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:NSFontWeightRegular];
    label.alignment = NSTextAlignmentLeft;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSTextField *)valueLabel:(NSString *)text size:(CGFloat)size {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
    label.textColor = [NSColor secondaryLabelColor];
    label.alignment = NSTextAlignmentLeft;
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

- (UISeverity)severityForAvailable:(BOOL)available
                              stale:(BOOL)stale
                            percent:(double)percent {
    if (stale)
        return UISeverityWarning;
    if (!available)
        return UISeverityError;
    if (percent >= 85.0)
        return UISeverityError;
    if (percent >= 60.0)
        return UISeverityWarning;
    return UISeverityNormal;
}

- (void)appendHistoryValue:(double)value toArray:(NSMutableArray<NSNumber *> *)history {
    if (!history || !isfinite(value))
        return;
    if (history.count >= CORE_CPU_HISTORY)
        [history removeObjectAtIndex:0];
    [history addObject:@(value)];
}

- (NSArray<NSNumber *> *)cpuHistoryValues {
    NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:_snapshot.history_len];
    for (int i = 0; i < _snapshot.history_len; i++) {
        int index = (_snapshot.history_head - _snapshot.history_len + i + CORE_CPU_HISTORY)
            % CORE_CPU_HISTORY;
        [values addObject:@(_snapshot.history[index])];
    }
    return values;
}

- (double)fanAverage {
    if (!_snapshot.has_fans || _snapshot.fans.count <= 0)
        return NAN;
    double total = 0.0;
    int count = MIN(_snapshot.fans.count, SMC_MAX_FANS);
    for (int i = 0; i < count; i++)
        total += _snapshot.fans.rpm[i];
    return count > 0 ? total / count : NAN;
}

- (void)recordHistoryForSnapshot:(BOOL)cpuAvailable
                   memoryAvailable:(BOOL)memoryAvailable
                      swapAvailable:(BOOL)swapAvailable
                      diskAvailable:(BOOL)diskAvailable
                     fanAvailable:(BOOL)fanAvailable {
    if (_snapshot.sequence == 0 || _snapshot.sequence == self.lastHistorySequence)
        return;
    self.lastHistorySequence = _snapshot.sequence;
    if (memoryAvailable) {
        double used = (double)(_snapshot.mem.app + _snapshot.mem.wired + _snapshot.mem.compressed);
        [self appendHistoryValue:100.0 * used / _snapshot.mem.total toArray:self.memoryHistory];
    }
    if (swapAvailable)
        [self appendHistoryValue:100.0 * _snapshot.mem.swap_used / _snapshot.mem.swap_total
                         toArray:self.swapHistory];
    if (diskAvailable)
        [self appendHistoryValue:100.0 * _snapshot.disk.used / _snapshot.disk.total
                         toArray:self.diskHistory];
    if (!(_snapshot.stale_mask & CORE_STALE_LOAD)) {
        [self appendHistoryValue:_snapshot.load[0] toArray:self.load1History];
        [self appendHistoryValue:_snapshot.load[1] toArray:self.load5History];
        [self appendHistoryValue:_snapshot.load[2] toArray:self.load15History];
    }
    if (!(_snapshot.stale_mask & CORE_STALE_PROC))
        [self appendHistoryValue:_snapshot.proc_total toArray:self.processHistory];
    if (fanAvailable)
        [self appendHistoryValue:[self fanAverage] toArray:self.fanHistory];
    (void)cpuAvailable;
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
    return [NSString stringWithFormat:@"%ld天 %02ld时 %02ld分", uptime / 86400,
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
        BOOL ascending = self.sort == PROC_SORT_CPU_ASC || self.sort == PROC_SORT_MEM_ASC;
        BOOL memory = self.sort == PROC_SORT_MEM || self.sort == PROC_SORT_MEM_ASC;
        if (self.sort != PROC_SORT_DEFAULT &&
            [column.identifier isEqualToString:memory ? @"mem" : @"cpu"])
            title = [title stringByAppendingString:ascending ? @" ↑" : @" ↓"];
        column.title = title;
        if ([column.identifier isEqualToString:@"cpu"] || [column.identifier isEqualToString:@"mem"])
            column.headerToolTip = @"点击切换：↓ 从大到小 → ↑ 从小到大 → 默认排序";
    }
    NSString *hint = @"默认排序";
    if (self.sort != PROC_SORT_DEFAULT) {
        BOOL memory = self.sort == PROC_SORT_MEM || self.sort == PROC_SORT_MEM_ASC;
        BOOL ascending = self.sort == PROC_SORT_CPU_ASC || self.sort == PROC_SORT_MEM_ASC;
        hint = [NSString stringWithFormat:@"%@占用从%@到%@", memory ? @"内存" : @"CPU ",
            ascending ? @"小" : @"大", ascending ? @"大" : @"小"];
    }
    self.processSectionHint.stringValue = (_snapshot.stale_mask & CORE_STALE_PROC)
        ? [hint stringByAppendingString:@" · 数据陈旧"] : hint;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    self.sort = PROC_SORT_DEFAULT;
    self.core = core_create(1.0, self.sort);
    if (!self.core || core_start(self.core) != 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法启动采样核心";
        alert.informativeText = @"请检查系统权限后重试。";
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }

    NSRect frame = NSMakeRect(0, 0, 1040, 800);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    // ARC owns this window; AppKit must not also release it on close.
    window.releasedWhenClosed = NO;
    self.window = window;
    window.title = @"MacMonitor";
    window.titlebarAppearsTransparent = YES;
    window.backgroundColor = NSColor.windowBackgroundColor;
    window.minSize = NSMakeSize(520, 380);

    self.memoryHistory = [NSMutableArray arrayWithCapacity:CORE_CPU_HISTORY];
    self.swapHistory = [NSMutableArray arrayWithCapacity:CORE_CPU_HISTORY];
    self.diskHistory = [NSMutableArray arrayWithCapacity:CORE_CPU_HISTORY];
    self.load1History = [NSMutableArray arrayWithCapacity:CORE_CPU_HISTORY];
    self.load5History = [NSMutableArray arrayWithCapacity:CORE_CPU_HISTORY];
    self.load15History = [NSMutableArray arrayWithCapacity:CORE_CPU_HISTORY];
    self.processHistory = [NSMutableArray arrayWithCapacity:CORE_CPU_HISTORY];
    self.fanHistory = [NSMutableArray arrayWithCapacity:CORE_CPU_HISTORY];

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

    NSView *document = [[MonitorDocumentView alloc] initWithFrame:NSZeroRect];
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
    root.spacing = 14;
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
    self.subtitle = [self label:@"系统概览 · 每秒更新" size:12];
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
    NSArray *metricSpecs = @[
        @[@"CPU", @(CardIconCPU)], @[@"内存", @(CardIconMemory)],
        @[@"交换空间", @(CardIconSwap)], @[@"磁盘", @(CardIconDisk)],
        @[@"网络吞吐量", @(CardIconNetwork)], @[@"CPU 温度", @(CardIconTemperature)]
    ];
    for (NSArray *spec in metricSpecs)
        [self.metricCards addObject:[[MetricCardView alloc] initWithTitle:spec[0]
                                                                       kind:[spec[1] integerValue]]];
    AdaptiveGridView *metrics = [[AdaptiveGridView alloc]
        initWithItems:self.metricCards wideColumns:3 compactColumns:2 compactThreshold:900
        itemHeight:166 spacing:12 columnSpacing:12];
    [root addArrangedSubview:metrics];

    [root addArrangedSubview:[self separator]];
    [root addArrangedSubview:[self sectionLabel:@"运行状态"]];
    self.loadTile = [[InfoTileView alloc] initWithTitle:@"系统负载" kind:CardIconLoad];
    self.processTile = [[InfoTileView alloc] initWithTitle:@"进程数量" kind:CardIconProcesses];
    self.uptimeTile = [[InfoTileView alloc] initWithTitle:@"运行时间" kind:CardIconUptime];
    self.fanTile = [[InfoTileView alloc] initWithTitle:@"风扇转速" kind:CardIconFan];
    AdaptiveGridView *statusTiles = [[AdaptiveGridView alloc]
        initWithItems:@[self.loadTile, self.processTile, self.uptimeTile, self.fanTile]
        wideColumns:4 compactColumns:2 compactThreshold:760
        itemHeight:100 spacing:12 columnSpacing:12];
    [root addArrangedSubview:statusTiles];

    [root addArrangedSubview:[self separator]];
    NSStackView *processHeader = [NSStackView stackViewWithViews:@[]];
    processHeader.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    processHeader.alignment = NSLayoutAttributeCenterY;
    NSTextField *processTitle = [self sectionLabel:@"进程列表"];
    [processTitle setContentHuggingPriority:NSLayoutPriorityRequired
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.processSectionHint = [self valueLabel:@"默认排序" size:10];
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
    self.table.gridStyleMask = NSTableViewGridNone;
    self.table.style = NSTableViewStyleFullWidth;
    self.table.rowHeight = 32;
    self.table.intercellSpacing = NSMakeSize(12, 0);
    self.table.columnAutoresizingStyle = NSTableViewSequentialColumnAutoresizingStyle;
    self.table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    NSArray *specs = @[
        @[@"pid", @"进程号", @64], @[@"name", @"进程", @260],
        @[@"cpu", @"CPU 占用", @90], @[@"mem", @"内存", @90]
    ];
    for (NSArray *spec in specs) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        BOOL isName = [column.identifier isEqualToString:@"name"];
        column.minWidth = isName ? 140 : column.width;
        column.resizingMask = isName ? NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask
                                    : NSTableColumnNoResizing;
        column.headerCell.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        column.headerCell.textColor = [NSColor secondaryLabelColor];
        column.headerCell.alignment = isName ? NSTextAlignmentLeft : NSTextAlignmentRight;
        [self.table addTableColumn:column];
    }

    NSScrollView *tableScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    tableScroll.documentView = self.table;
    tableScroll.hasVerticalScroller = YES;
    tableScroll.autohidesScrollers = YES;
    tableScroll.drawsBackground = NO;
    tableScroll.borderType = NSNoBorder;
    tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    RoundedPanelView *tableWrapper = [[RoundedPanelView alloc] initWithFrame:NSZeroRect];
    tableWrapper.translatesAutoresizingMaskIntoConstraints = NO;
    [tableWrapper addSubview:tableScroll];
    [NSLayoutConstraint activateConstraints:@[
        [tableScroll.leadingAnchor constraintEqualToAnchor:tableWrapper.leadingAnchor],
        [tableScroll.trailingAnchor constraintEqualToAnchor:tableWrapper.trailingAnchor],
        [tableScroll.topAnchor constraintEqualToAnchor:tableWrapper.topAnchor],
        [tableScroll.bottomAnchor constraintEqualToAnchor:tableWrapper.bottomAnchor]
    ]];
    self.emptyState = [self label:@"暂无进程数据" size:13];
    self.emptyState.alignment = NSTextAlignmentLeft;
    self.emptyState.textColor = [NSColor secondaryLabelColor];
    self.emptyState.translatesAutoresizingMaskIntoConstraints = NO;
    [tableWrapper addSubview:self.emptyState];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyState.leadingAnchor constraintEqualToAnchor:tableWrapper.leadingAnchor constant:12],
        [self.emptyState.trailingAnchor constraintLessThanOrEqualToAnchor:tableWrapper.trailingAnchor
                                                                    constant:-12],
        [self.emptyState.centerYAnchor constraintEqualToAnchor:tableWrapper.centerYAnchor]
    ]];
    [root addArrangedSubview:tableWrapper];
    [tableWrapper.heightAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;

    for (NSView *section in root.arrangedSubviews) {
        section.translatesAutoresizingMaskIntoConstraints = NO;
        [section.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-48].active = YES;
    }

    [self updateTableHeaders];
    [window center];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self
        selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (void)refreshExtendedMetrics {
    metric_history_record(&_extendedHistory, &_snapshot);
    char download[32], upload[32];
    network_format_rate(_snapshot.network.download, download, sizeof(download));
    network_format_rate(_snapshot.network.upload, upload, sizeof(upload));
    BOOL networkAvailable = _snapshot.network.status == NETWORK_OK;
    NSString *networkState = [NSString stringWithUTF8String:network_status_text(_snapshot.network.status)];
    NSString *networkValue = networkAvailable ? [NSString stringWithFormat:@"下载 %s\n上传 %s", download, upload] : networkState;
    [self.metricCards[METRIC_NETWORK] setPercent:0 value:networkValue
        detail:@"实体接口 · 60 秒 · 蓝下载／绿上传" state:networkAvailable ? @"实时" : @"暂无读数"
        severity:networkAvailable ? UISeverityNormal : (_snapshot.network.status == NETWORK_ERROR ? UISeverityWarning : UISeverityNeutral)];
    BOOL temperatureAvailable = _snapshot.temperature.status == TEMPERATURE_OK;
    NSString *temperatureState = [NSString stringWithUTF8String:smc_temperature_status_text(_snapshot.temperature.status)];
    NSString *temperatureValue = temperatureAvailable ? [NSString stringWithFormat:@"%.1f°C", _snapshot.temperature.celsius] : temperatureState;
    NSString *temperatureDetail = _snapshot.temperature.key[0]
        ? [NSString stringWithFormat:@"%@ · %s · 60 秒",
            [NSString stringWithUTF8String:smc_temperature_source_text(_snapshot.temperature.source)], _snapshot.temperature.key]
        : @"暂无可确认的 CPU 温度来源";
    [self.metricCards[METRIC_TEMPERATURE] setPercent:0 value:temperatureValue detail:temperatureDetail
        state:temperatureAvailable ? @"实时" : @"暂无读数"
        severity:temperatureAvailable ? UISeverityNormal : (_snapshot.temperature.status == TEMPERATURE_ERROR ? UISeverityWarning : UISeverityNeutral)];
    [self.metricCards[METRIC_NETWORK] setTimedHistory:&_extendedHistory network:YES emptyText:networkState];
    [self.metricCards[METRIC_TEMPERATURE] setTimedHistory:&_extendedHistory network:NO emptyText:temperatureState];

}

- (void)refresh:(NSTimer *)timer {
    (void)timer;
    if (core_snapshot(self.core, &_snapshot) != 0)
        return;
    proclist_sort(_snapshot.procs, _snapshot.proc_count, self.sort);

    const BOOL cpuStale = (_snapshot.stale_mask & CORE_STALE_CPU) != 0;
    const BOOL memStale = (_snapshot.stale_mask & CORE_STALE_MEM) != 0;
    const BOOL diskStale = (_snapshot.stale_mask & CORE_STALE_DISK) != 0;
    const BOOL cpuAvailable = !cpuStale;
    const BOOL memAvailable = !memStale && _snapshot.mem.total > 0;
    const BOOL swapConfigured = _snapshot.mem.swap_total > 0;
    const BOOL swapAvailable = !memStale && swapConfigured;
    const BOOL diskAvailable = !diskStale && _snapshot.disk.total > 0;
    const BOOL fanAvailable = !(_snapshot.stale_mask & CORE_STALE_FAN) &&
        _snapshot.has_fans && _snapshot.fans.count > 0;

    double memUsed = (double)(_snapshot.mem.app + _snapshot.mem.wired + _snapshot.mem.compressed);
    double memPct = memAvailable ? 100.0 * memUsed / _snapshot.mem.total : 0.0;
    double swapPct = swapAvailable ? 100.0 * _snapshot.mem.swap_used / _snapshot.mem.swap_total : 0.0;
    double diskPct = diskAvailable ? 100.0 * _snapshot.disk.used / _snapshot.disk.total : 0.0;
    memPct = MIN(100.0, MAX(0.0, memPct));
    swapPct = MIN(100.0, MAX(0.0, swapPct));
    diskPct = MIN(100.0, MAX(0.0, diskPct));

    UISeverity cpuSeverity = [self severityForAvailable:cpuAvailable stale:cpuStale
                                                  percent:_snapshot.cpu.busy];
    UISeverity memSeverity = [self severityForAvailable:memAvailable stale:memStale percent:memPct];
    UISeverity swapSeverity = memStale ? UISeverityWarning
        : (swapConfigured ? [self severityForAvailable:swapAvailable stale:NO percent:swapPct]
                          : UISeverityNeutral);
    UISeverity diskSeverity = [self severityForAvailable:diskAvailable stale:diskStale percent:diskPct];

    NSString *cpuValue = cpuStale ? @"数据陈旧" : (cpuAvailable
        ? [NSString stringWithFormat:@"%.1f%%", _snapshot.cpu.busy] : @"不可用");
    NSString *cpuDetail = cpuStale ? @"本项数据暂不可用"
        : [NSString stringWithFormat:@"用户 %.1f · 系统 %.1f · 空闲 %.1f",
            _snapshot.cpu.user, _snapshot.cpu.system, _snapshot.cpu.idle];
    [self.metricCards[METRIC_CPU] setPercent:_snapshot.cpu.busy value:cpuValue detail:cpuDetail
        state:cpuStale ? @"数据陈旧" : (cpuSeverity == UISeverityError ? @"高占用"
            : (cpuSeverity == UISeverityWarning ? @"注意" : @"正常")) severity:cpuSeverity];

    NSString *memValue = memStale ? @"数据陈旧" : (memAvailable
        ? [NSString stringWithFormat:@"%.1f%%", memPct] : @"不可用");
    NSString *memDetail = memAvailable
        ? [NSString stringWithFormat:@"已用 %.1fG / %.1fG", memUsed / 1073741824.0,
            _snapshot.mem.total / 1073741824.0] : @"本项数据暂不可用";
    [self.metricCards[METRIC_MEMORY] setPercent:memPct value:memValue detail:memDetail
        state:memStale ? @"数据陈旧" : (memSeverity == UISeverityError ? @"高占用"
            : (memSeverity == UISeverityWarning ? @"注意" : @"正常")) severity:memSeverity];

    NSString *swapValue = memStale ? @"数据陈旧" : (swapAvailable
        ? [NSString stringWithFormat:@"%.1f%%", swapPct] : @"未启用");
    NSString *swapDetail = swapAvailable
        ? [NSString stringWithFormat:@"已用 %.1fG / %.1fG", _snapshot.mem.swap_used / 1073741824.0,
            _snapshot.mem.swap_total / 1073741824.0] : (memStale ? @"本项数据暂不可用" : @"系统未配置交换空间");
    [self.metricCards[METRIC_SWAP] setPercent:swapPct value:swapValue detail:swapDetail
        state:memStale ? @"数据陈旧" : (swapConfigured && swapSeverity == UISeverityError ? @"高占用"
            : (swapConfigured && swapSeverity == UISeverityWarning ? @"注意"
                : (swapConfigured ? @"正常" : @"未启用")))
        severity:swapSeverity];

    NSString *diskValue = diskStale ? @"数据陈旧" : (diskAvailable
        ? [NSString stringWithFormat:@"%.1f%%", diskPct] : @"不可用");
    NSString *diskDetail = diskAvailable
        ? [NSString stringWithFormat:@"已用 %.1fG / %.1fG", _snapshot.disk.used / 1073741824.0,
            _snapshot.disk.total / 1073741824.0] : @"本项数据暂不可用";
    [self.metricCards[METRIC_DISK] setPercent:diskPct value:diskValue detail:diskDetail
        state:diskStale ? @"数据陈旧" : (diskSeverity == UISeverityError ? @"高占用"
            : (diskSeverity == UISeverityWarning ? @"注意" : @"正常")) severity:diskSeverity];

    [self refreshExtendedMetrics];

    [self recordHistoryForSnapshot:cpuAvailable memoryAvailable:memAvailable
                     swapAvailable:swapAvailable diskAvailable:diskAvailable
                      fanAvailable:fanAvailable];

    NSArray *cpuHistory = cpuStale ? @[] : [self cpuHistoryValues];
    [self.metricCards[METRIC_CPU] setChartValues:cpuHistory minimum:0 maximum:100
                                         emptyText:cpuStale ? @"数据陈旧" : @"暂无历史"];
    [self.metricCards[METRIC_MEMORY] setChartValues:memAvailable ? self.memoryHistory : @[]
                                             minimum:0 maximum:100
                                           emptyText:memStale ? @"数据陈旧" : @"暂无历史"];
    [self.metricCards[METRIC_SWAP] setChartValues:swapAvailable ? self.swapHistory : @[]
                                             minimum:0 maximum:100
                                           emptyText:memStale ? @"数据陈旧" : @"未启用"];
    [self.metricCards[METRIC_DISK] setChartValues:diskAvailable ? self.diskHistory : @[]
                                             minimum:0 maximum:100
                                           emptyText:diskStale ? @"数据陈旧" : @"暂无历史"];

    /* 未配置交换空间是中性状态，不应把整机健康度变成警告。 */
    NSInteger availableCount = (cpuAvailable ? 1 : 0) + (memAvailable ? 1 : 0) +
        (swapAvailable || (!memStale && !swapConfigured) ? 1 : 0) + (diskAvailable ? 1 : 0);
    UISeverity overallSeverity = UISeverityNormal;
    for (NSNumber *severityValue in @[@(cpuSeverity), @(memSeverity), @(swapSeverity), @(diskSeverity)]) {
        UISeverity severity = (UISeverity)severityValue.integerValue;
        if (severity == UISeverityError)
            overallSeverity = UISeverityError;
        else if (severity == UISeverityWarning && overallSeverity != UISeverityError)
            overallSeverity = UISeverityWarning;
    }
    if (_snapshot.paused || _snapshot.stale_mask || availableCount < METRIC_NETWORK)
        if (overallSeverity != UISeverityError)
            overallSeverity = UISeverityWarning;
    NSString *overallTitle = overallSeverity == UISeverityError
        ? (availableCount < METRIC_NETWORK ? @"部分数据不可用" : @"资源占用较高")
        : (_snapshot.paused ? @"采样已暂停"
        : (overallSeverity == UISeverityWarning ? @"部分数据需要关注" : @"系统状态正常"));
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
    [self.loadTile setChartSeries:loadSeverity == UISeverityNormal
        ? @[self.load1History, self.load5History, self.load15History] : @[]
        minimum:0 maximum:0 emptyText:loadSeverity == UISeverityNormal ? @"暂无历史" : @"数据陈旧"];

    UISeverity processSeverity = (_snapshot.stale_mask & CORE_STALE_PROC)
        ? UISeverityWarning : UISeverityNormal;
    [self.processTile setValueText:processSeverity == UISeverityNormal
        ? [NSString stringWithFormat:@"%d 个", _snapshot.proc_total] : @"数据陈旧"
        severity:processSeverity];
    [self.processTile setChartSeries:processSeverity == UISeverityNormal ? @[self.processHistory] : @[]
        minimum:0 maximum:0 emptyText:processSeverity == UISeverityNormal ? @"暂无历史" : @"数据陈旧"];

    UISeverity uptimeSeverity = (_snapshot.stale_mask & CORE_STALE_UP) || _snapshot.uptime < 0
        ? UISeverityWarning : UISeverityNormal;
    [self.uptimeTile setValueText:uptimeSeverity == UISeverityNormal
        ? [self uptimeSummary] : @"运行时间不可用" severity:uptimeSeverity];
    if (uptimeSeverity == UISeverityNormal)
        [self.uptimeTile setDurationChart];
    else
        [self.uptimeTile setChartSeries:@[] minimum:0 maximum:1 emptyText:@"不可用"];

    UISeverity fanSeverity = (_snapshot.stale_mask & CORE_STALE_FAN)
        ? UISeverityWarning : (fanAvailable ? UISeverityNormal : UISeverityNeutral);
    [self.fanTile setValueText:[self fanSummary] severity:fanSeverity];
    [self.fanTile setChartSeries:fanAvailable ? @[self.fanHistory] : @[] minimum:0 maximum:0
        emptyText:(fanSeverity == UISeverityWarning ? @"数据陈旧" : @"无传感器")];

    BOOL processStale = (_snapshot.stale_mask & CORE_STALE_PROC) != 0;
    self.emptyState.hidden = _snapshot.proc_count > 0;
    if (_snapshot.proc_count == 0)
        self.emptyState.stringValue = processStale ? @"进程数据陈旧，暂时无法显示" : @"暂无进程数据";
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
        cell.textField.stringValue = [NSString stringWithFormat:@"%.1f%%", p.cpu];
    else
        cell.textField.stringValue = p.mem >= 1073741824ULL
            ? [NSString stringWithFormat:@"%.1f GB", p.mem / 1073741824.0]
            : [NSString stringWithFormat:@"%.1f MB", p.mem / 1048576.0];
    if ([column.identifier isEqualToString:@"pid"])
        cell.textField.textColor = NSColor.secondaryLabelColor;
    if ([column.identifier isEqualToString:@"cpu"] && p.cpu >= 60.0)
        cell.textField.textColor = p.cpu >= 85.0 ? NSColor.systemRedColor : NSColor.systemOrangeColor;
    cell.textField.toolTip = cell.textField.stringValue;
    return cell;
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)column {
    (void)tableView;
    if (![column.identifier isEqualToString:@"mem"] &&
        ![column.identifier isEqualToString:@"cpu"])
        return;
    proc_sort_t descending = [column.identifier isEqualToString:@"mem"] ? PROC_SORT_MEM : PROC_SORT_CPU;
    proc_sort_t ascending = [column.identifier isEqualToString:@"mem"] ? PROC_SORT_MEM_ASC : PROC_SORT_CPU_ASC;
    self.sort = self.sort == descending ? ascending
        : (self.sort == ascending ? PROC_SORT_DEFAULT : descending);
    core_set_sort(self.core, self.sort);
    proclist_sort(_snapshot.procs, _snapshot.proc_count, self.sort);
    [self updateTableHeaders];
    [self.table reloadData];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.timer invalidate];
    self.timer = nil;
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
        __attribute__((objc_precise_lifetime)) MacMonitorApp *delegate = [[MacMonitorApp alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
