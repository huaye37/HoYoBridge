#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// Opt-in, process-local adapter. No game files or system display modes are changed.
static const void *MGBStateKey = &MGBStateKey;

// Enabled only for the dedicated downloader prefix, never a game process.
@interface NSApplication (MGBBackgroundEngine)
- (BOOL)mgb_enginePolicy:(NSApplicationActivationPolicy)policy;
@end
@implementation NSApplication (MGBBackgroundEngine)
- (BOOL)mgb_enginePolicy:(NSApplicationActivationPolicy)policy {
    (void)policy;
    return [self mgb_enginePolicy:NSApplicationActivationPolicyAccessory];
}
@end
@interface NSWindow (MGBBackgroundEngine)
- (void)mgb_engineOrder:(NSWindowOrderingMode)place relativeTo:(NSInteger)other;
@end
@implementation NSWindow (MGBBackgroundEngine)
- (void)mgb_engineOrder:(NSWindowOrderingMode)place relativeTo:(NSInteger)other {
    if (place==NSWindowOut) [self mgb_engineOrder:place relativeTo:other];
}
@end
static NSRect MGBFit(NSRect frame, NSRect visible) {
    frame.size.width = MIN(MAX(frame.size.width, 320), visible.size.width);
    frame.size.height = MIN(MAX(frame.size.height, 200), visible.size.height);
    frame.origin.x = MAX(NSMinX(visible), MIN(frame.origin.x, NSMaxX(visible)-frame.size.width));
    frame.origin.y = MAX(NSMinY(visible), MIN(frame.origin.y, NSMaxY(visible)-frame.size.height));
    return frame;
}

// Forward Wine's delegate callbacks unchanged, except the native toolbar policy.
@interface MGBWindowDelegate : NSObject <NSWindowDelegate>
@property (weak) id<NSWindowDelegate> original;
@end
@implementation MGBWindowDelegate
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.original respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector { return self.original; }
- (NSApplicationPresentationOptions)window:(NSWindow *)window
        willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)options {
    if ([self.original respondsToSelector:_cmd])
        options=[self.original window:window willUseFullScreenPresentationOptions:options];
    return options | NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideToolbar;
}
@end

@interface MGBWindowState : NSObject
@property NSRect savedFrame;
@property BOOL transitioning;
@property BOOL fullscreen;
@property BOOL updating;
@property NSMutableArray *observers;
@property (weak) NSWindow *window;
@property MGBWindowDelegate *delegateProxy;
@property NSTimer *toolbarTimer;
@property NSPanel *controlsPanel;
@property BOOL minimizeAfterExit;
- (void)toggle:(id)sender;
- (void)recover:(id)sender;
- (void)closeGame:(id)sender;
- (void)minimizeGame:(id)sender;
@end
static void MGBRestore(NSWindow *window, MGBWindowState *state);
@implementation MGBWindowState
- (instancetype)init { if ((self=[super init])) _observers=[NSMutableArray new]; return self; }
- (void)dealloc {
    [_toolbarTimer invalidate];
    for (id token in _observers) [[NSNotificationCenter defaultCenter] removeObserver:token];
}
- (void)toggle:(id)sender {
    (void)sender;
    if (!self.transitioning) {
        fprintf(stderr,"MGB_WINDOW command=toggle\n");
        [self.window toggleFullScreen:nil];
    }
}
- (void)closeGame:(id)sender { (void)sender; [self.window performClose:nil]; }
- (void)minimizeGame:(id)sender {
    (void)sender;
    if (self.transitioning) return;
    if (self.fullscreen) { self.minimizeAfterExit=YES; [self.window toggleFullScreen:nil]; }
    else [self.window miniaturize:nil];
}
- (void)recover:(id)sender {
    (void)sender;
    if (self.transitioning || !self.window) return;
    fprintf(stderr,"MGB_WINDOW command=recover\n");
    NSScreen *screen=self.window.screen ?: NSScreen.mainScreen;
    self.savedFrame=MGBFit(NSMakeRect(NSMinX(screen.visibleFrame)+40,NSMinY(screen.visibleFrame)+40,1280,720),screen.visibleFrame);
    if (self.window.styleMask & NSWindowStyleMaskFullScreen) [self.window toggleFullScreen:nil];
    else MGBRestore(self.window,self);
}
@end

static void MGBRestore(NSWindow *window, MGBWindowState *state) {
    if (!window || state.updating) return;
    NSScreen *screen = window.screen ?: NSScreen.mainScreen;
    if (!screen) return;
    state.updating = YES;
    // Wine can retain a fixed content min/max size after leaving fullscreen.
    window.contentMinSize = NSMakeSize(320, 200);
    window.contentMaxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    NSRect fitted=MGBFit(state.savedFrame, screen.visibleFrame);
    if (!NSEqualRects(window.frame,fitted)) [window setFrame:fitted display:YES];
    state.updating = NO;
}

static void MGBObserve(NSWindow *window) {
    if (objc_getAssociatedObject(window, MGBStateKey)) return;
    MGBWindowState *state=[MGBWindowState new];
    state.window=window;
    state.savedFrame=window.frame;
    state.delegateProxy=[MGBWindowDelegate new];
    state.delegateProxy.original=window.delegate;
    window.delegate=state.delegateProxy;
    objc_setAssociatedObject(window, MGBStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak NSWindow *weakWindow=window;
    __weak MGBWindowState *weakState=state;
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    NSArray *names=@[NSWindowWillEnterFullScreenNotification, NSWindowDidEnterFullScreenNotification,
                     NSWindowWillExitFullScreenNotification, NSWindowDidExitFullScreenNotification,
                     NSWindowDidResizeNotification, NSWindowDidMoveNotification];
    for (NSNotificationName name in names) {
        id token=[center addObserverForName:name object:window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSWindow *w=weakWindow; MGBWindowState *s=weakState;
            if (!w || !s || s.updating) return;
            if ([note.name isEqual:NSWindowWillEnterFullScreenNotification]) {
                s.savedFrame=w.frame; s.transitioning=YES;
            } else if ([note.name isEqual:NSWindowDidEnterFullScreenNotification]) {
                s.fullscreen=YES; s.transitioning=NO;
                fprintf(stderr,"MGB_WINDOW entered_fullscreen\n");
                // Keep a native control panel independent of AppKit's detached
                // toolbar animation, which Wine leaves offscreen and transparent.
                NSPanel *panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,NSWidth(w.frame),0)
                    styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskNonactivatingPanel
                    backing:NSBackingStoreBuffered defer:NO];
                panel.title=w.title; panel.movable=NO; panel.hidesOnDeactivate=NO;
                panel.hasShadow=NO;
                panel.collectionBehavior=NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorTransient;
                panel.level=NSFloatingWindowLevel;
                [w addChildWindow:panel ordered:NSWindowAbove];
                s.controlsPanel=panel;
                NSArray *actions=@[NSStringFromSelector(@selector(closeGame:)),NSStringFromSelector(@selector(minimizeGame:)),NSStringFromSelector(@selector(toggle:))];
                for (NSUInteger i=0;i<3;i++) {
                    NSButton *button=[panel standardWindowButton:(NSWindowButton)i];
                    button.target=s; button.action=NSSelectorFromString(actions[i]); button.enabled=YES;
                }
                [s.toolbarTimer invalidate];
                __block BOOL controlsShown=NO;
                s.toolbarTimer=[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
                    NSWindow *game=weakWindow; MGBWindowState *current=weakState;
                    if (!game || !current || !current.fullscreen) { [timer invalidate]; return; }
                    NSWindow *controls=current.controlsPanel;
                    NSScreen *screen=game.screen;
                    if (!controls || controls==game || !screen || NSHeight(controls.frame)>100) return;
                    NSPoint mouse=NSEvent.mouseLocation;
                    CGFloat height=NSHeight(controls.frame);
                    CGFloat menuHeight=NSApp.mainMenu.menuBarHeight;
                    BOOL reveal=game.onActiveSpace &&
                        mouse.x>=NSMinX(screen.frame) && mouse.x<=NSMaxX(screen.frame) &&
                        mouse.y>=NSMaxY(screen.frame)-menuHeight-height-8 && mouse.y<=NSMaxY(screen.frame);
                    if (reveal) {
                        NSPoint origin=NSMakePoint(NSMinX(screen.frame),NSMaxY(screen.frame)-menuHeight-height);
                        [controls orderWindow:NSWindowAbove relativeTo:game.windowNumber];
                        if (!NSEqualPoints(controls.frame.origin,origin)) [controls setFrameOrigin:origin];
                        controls.alphaValue=1;
                    } else if (controls.visible) [controls orderOut:nil];
                    if (controlsShown!=reveal) {
                        controlsShown=reveal;
                        fprintf(stderr,"MGB_WINDOW controls_shown=%d frame=%s\n",reveal,NSStringFromRect(controls.frame).UTF8String);
                    }
                }];
#ifdef MGB_WINDOW_SELFTEST
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [w toggleFullScreen:nil]; });
#endif
            } else if ([note.name isEqual:NSWindowWillExitFullScreenNotification]) {
                s.transitioning=YES;
                [s.toolbarTimer invalidate]; s.toolbarTimer=nil;
                [w removeChildWindow:s.controlsPanel]; [s.controlsPanel orderOut:nil]; s.controlsPanel=nil;
            } else if ([note.name isEqual:NSWindowDidExitFullScreenNotification]) {
                s.fullscreen=NO;
                // Restore after Wine's delegate has completed its own frame update.
                dispatch_async(dispatch_get_main_queue(), ^{
                    MGBRestore(w,s); s.transitioning=NO;
                    if (s.minimizeAfterExit) { s.minimizeAfterExit=NO; [w miniaturize:nil]; }
                    fprintf(stderr,"MGB_WINDOW restored=%.0fx%.0f\n",w.frame.size.width,w.frame.size.height);
#ifdef MGB_WINDOW_SELFTEST
                    BOOL valid=NSEqualRects(w.frame,MGBFit(s.savedFrame,(w.screen ?: NSScreen.mainScreen).visibleFrame));
                    fprintf(stderr,"MGB_WINDOW full_cycle=%s\n",valid?"PASS":"FAIL");
                    [w performClose:nil];
#endif
                });
            } else if (!s.fullscreen && !s.transitioning && !(w.styleMask & NSWindowStyleMaskFullScreen)) {
                s.savedFrame=w.frame;
            }
        }];
        [state.observers addObject:token];
    }
    window.styleMask |= NSWindowStyleMaskResizable;
    // A real native toolbar keeps the system window controls available in
    // fullscreen. Do not draw replacement traffic lights over the game view.
    if (!window.toolbar) {
        NSToolbar *toolbar=[[NSToolbar alloc] initWithIdentifier:@"MGBWindowToolbar"];
        toolbar.allowsUserCustomization=NO;
        window.toolbarStyle=NSWindowToolbarStyleUnifiedCompact;
        window.toolbar=toolbar;
    }
    window.collectionBehavior = (window.collectionBehavior | NSWindowCollectionBehaviorFullScreenPrimary)
        & ~NSWindowCollectionBehaviorFullScreenAuxiliary;
    MGBRestore(window,state);
    if (NSApp.mainMenu) {
        NSMenuItem *root=[[NSMenuItem alloc] initWithTitle:@"窗口适配" action:nil keyEquivalent:@""];
        NSMenu *menu=[[NSMenu alloc] initWithTitle:root.title];
        NSMenuItem *toggle=[[NSMenuItem alloc] initWithTitle:@"切换原生全屏" action:@selector(toggle:) keyEquivalent:@"f"];
        toggle.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagControl;
        toggle.target=state; [menu addItem:toggle];
        NSMenuItem *recover=[[NSMenuItem alloc] initWithTitle:@"恢复到屏幕内的小窗口" action:@selector(recover:) keyEquivalent:@"0"];
        recover.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagControl;
        recover.target=state; [menu addItem:recover];
        root.submenu=menu; [NSApp.mainMenu addItem:root];
    }
    fprintf(stderr,"MGB_WINDOW attached; scale=%.1f\n",window.backingScaleFactor);
    const char *initialFullscreen=getenv("MGB_NATIVE_FULLSCREEN");
    if (initialFullscreen && !strcmp(initialFullscreen,"1")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if (window.visible && !(window.styleMask & NSWindowStyleMaskFullScreen)) [state toggle:nil];
        });
    }
#ifdef MGB_WINDOW_SELFTEST
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ [window toggleFullScreen:nil]; });
#endif
}

__attribute__((constructor)) static void MGBStart(void) {
    const char *background=getenv("MGB_BACKGROUND_ENGINE");
    if (background && !strcmp(background,"1")) {
        method_exchangeImplementations(class_getInstanceMethod(NSApplication.class,@selector(setActivationPolicy:)),
            class_getInstanceMethod(NSApplication.class,@selector(mgb_enginePolicy:)));
        method_exchangeImplementations(class_getInstanceMethod(NSWindow.class,@selector(orderWindow:relativeTo:)),
            class_getInstanceMethod(NSWindow.class,@selector(mgb_engineOrder:relativeTo:)));
        dispatch_async(dispatch_get_main_queue(), ^{
            __block NSUInteger attempts=0;
            [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
                if (NSApp) {
                    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
                    for (NSWindow *window in NSApp.windows) [window orderOut:nil];
                    if (NSApp.activationPolicy==NSApplicationActivationPolicyAccessory) {
                        fprintf(stderr,"MGB_BACKGROUND policy=accessory\n");
                        [timer invalidate];
                    }
                }
                if (++attempts>=120) [timer invalidate];
            }];
        });
        return;
    }
    const char *enabled=getenv("MGB_NATIVE_WINDOW");
    const char *title=getenv("MGB_NATIVE_WINDOW_TITLE");
    if (!enabled || strcmp(enabled,"1") || !title || !*title) return;
    NSArray<NSString *> *targets=[[NSString stringWithUTF8String:title] componentsSeparatedByString:@"|"];
    dispatch_async(dispatch_get_main_queue(), ^{
        // A launch-time timer discovers the game window without accessibility permission.
        __block NSUInteger ticks=0;
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            for (NSWindow *window in NSApp.windows) {
                if (window.visible && !window.parentWindow && [targets containsObject:window.title]
                    && (window.styleMask & NSWindowStyleMaskResizable)) {
                    MGBObserve(window);
                    [timer invalidate];
                    return;
                }
            }
            if (++ticks >= 240) [timer invalidate];
        }];
    });
}
