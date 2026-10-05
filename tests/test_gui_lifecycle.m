#define main macmon_application_main
#import "../src/gui.m"
#undef main
#include <stdlib.h>
#include <string.h>

@interface LifecycleTestApp : MacMonitorApp
@property(nonatomic) BOOL drainAfterClose;
@end

@implementation LifecycleTestApp
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return self.drainAfterClose ? NO : [super applicationShouldTerminateAfterLastWindowClosed:sender];
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    NSTimer *refreshTimer = self.timer;
    [super applicationWillTerminate:notification];
    if (refreshTimer.valid || self.core != NULL) {
        fprintf(stderr, "FAIL: refresh or sampling still active at termination\n");
        _Exit(1);
    }
    fprintf(stderr, "PASS: GUI shutdown\n");
}
@end

int main(int argc, const char *argv[]) {
    BOOL quit = argc > 1 && strcmp(argv[1], "quit") == 0;
    BOOL drain = argc > 1 && strcmp(argv[1], "drain") == 0;
    double delay = argc > 2 ? atof(argv[2]) : 0.1;
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app finishLaunching];
        __attribute__((objc_precise_lifetime)) LifecycleTestApp *delegate = [[LifecycleTestApp alloc] init];
        delegate.drainAfterClose = drain;
        app.delegate = delegate;
        __weak NSWindow *window;
        // Launch notifications normally run in an event-local autorelease pool.
        @autoreleasepool {
            [delegate applicationDidFinishLaunching:
                [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:app]];
            window = app.windows.firstObject;
        }
        if (!window) {
            fprintf(stderr, "FAIL: GUI window was not created\n");
            return 1;
        }
        for (NSInteger kind = CardIconCPU; kind <= CardIconFan; kind++) {
            CardIconView *icon = [[CardIconView alloc] initWithKind:kind];
            if (!icon.image) {
                fprintf(stderr, "FAIL: missing GUI symbol %ld\n", (long)kind);
                return 1;
            }
        }
        [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            if (quit) {
                [app terminate:nil];
            } else {
                [window performClose:nil];
                if (window.visible) {
                    fprintf(stderr, "FAIL: GUI window did not close\n");
                    _Exit(1);
                }
            }
        }];
        if (drain) {
            // Keep the loop alive so invalid releases cannot be hidden by exit().
            [NSTimer scheduledTimerWithTimeInterval:delay + 0.3 repeats:NO block:^(NSTimer *timer) {
                (void)timer;
                [app terminate:nil];
            }];
        }
        [NSTimer scheduledTimerWithTimeInterval:delay + 5 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            fprintf(stderr, "FAIL: GUI did not terminate\n");
            _Exit(1);
        }];
        [app run];
    }
    return 0;
}
