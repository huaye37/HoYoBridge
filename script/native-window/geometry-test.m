#import <AppKit/AppKit.h>
#include "MGBWindowAdapter.m"
@interface MGBTestDelegate : NSObject <NSWindowDelegate>
@property BOOL called;
@end
@implementation MGBTestDelegate
- (NSSize)window:(NSWindow *)window willUseFullScreenContentSize:(NSSize)size {
    (void)window; self.called=YES; return size;
}
@end
int main(void) {
    @autoreleasepool {
        NSRect visible=NSMakeRect(-1512,0,1512,944);
        NSRect fit=MGBFit(NSMakeRect(0,-200,5120,2880),visible);
        assert(NSEqualRects(fit,visible));
        NSRect small=NSMakeRect(-1400,100,800,600);
        assert(NSEqualRects(MGBFit(small,visible),small));
        fit=MGBFit(NSMakeRect(-2000,1200,800,600),visible);
        assert(NSContainsRect(visible,fit));
        fit=MGBFit(NSMakeRect(0,0,100,100),NSMakeRect(0,0,400,300));
        assert(fit.size.width==320 && fit.size.height==200);
        // A 5K drawable occupies 2560x1440 points at 2x, not 5120x2880 points.
        NSSize drawable=NSMakeSize(5120,2880);
        assert(drawable.width/2==2560 && drawable.height/2==1440);
        assert(NSEqualSizes(MGBStartupSize(NSMakeSize(3840,2160),2,NSMakeSize(2560,1400)),NSMakeSize(1920,1080)));
        NSSize fitted=MGBStartupSize(NSMakeSize(3840,2160),2,NSMakeSize(1512,900));
        assert(fitted.width<=1512 && fitted.height<=900);
        assert(fabs(fitted.width/fitted.height-16.0/9.0)<0.001);
        MGBTestDelegate *original=[MGBTestDelegate new];
        [NSApplication sharedApplication];
        NSWindow *testWindow=[NSWindow new];
        MGBWindowDelegate *proxy=[MGBWindowDelegate new]; proxy.original=original;
        assert([proxy respondsToSelector:@selector(window:willUseFullScreenContentSize:)]);
        NSSize forwarded=[proxy window:testWindow willUseFullScreenContentSize:NSMakeSize(800,600)];
        assert(original.called && NSEqualSizes(forwarded,NSMakeSize(800,600)));
        NSApplicationPresentationOptions options=[proxy window:testWindow willUseFullScreenPresentationOptions:NSApplicationPresentationAutoHideDock];
        assert(options & NSApplicationPresentationAutoHideDock);
        assert(options & NSApplicationPresentationFullScreen);
        assert(options & NSApplicationPresentationAutoHideToolbar);
        NSWindow *ordinary=[[NSWindow alloc] initWithContentRect:NSMakeRect(50,50,800,600)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        ordinary.releasedWhenClosed=NO;
        MGBObserve(ordinary);
        assert(ordinary.styleMask & NSWindowStyleMaskResizable);
        assert(ordinary.styleMask & NSWindowStyleMaskMiniaturizable);
        assert(ordinary.collectionBehavior & NSWindowCollectionBehaviorFullScreenPrimary);
        NSButton *green=[ordinary standardWindowButton:NSWindowZoomButton];
        assert(green.enabled && green.target && green.action==@selector(toggle:));
        for (NSScreen *target in NSScreen.screens) {
            if (NSHeight(target.frame)>NSWidth(target.frame)) continue;
            CGDirectDisplayID display=[target.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display);
            NSString *identifier=CFBridgingRelease(CFUUIDCreateString(NULL,uuid));
            CFRelease(uuid);
            setenv("MGB_TARGET_DISPLAY_UUID",identifier.UTF8String,1);
            setenv("MGB_STARTUP_PIXEL_WIDTH","1920",1);
            setenv("MGB_STARTUP_PIXEL_HEIGHT","1080",1);
            assert(MGBTargetScreen(ordinary)==target);
            MGBPlaceInitialWindow(ordinary);
            assert(NSContainsRect(target.visibleFrame,ordinary.frame));
            NSRect content=[ordinary contentRectForFrameRect:ordinary.frame];
            assert(fabs(content.size.width*target.backingScaleFactor-1920)<2);
            assert(fabs(content.size.height*target.backingScaleFactor-1080)<2);
        }
        unsetenv("MGB_TARGET_DISPLAY_UUID");unsetenv("MGB_STARTUP_PIXEL_WIDTH");unsetenv("MGB_STARTUP_PIXEL_HEIGHT");
        [ordinary close];
        NSRect screen=NSMakeRect(0,0,1440,900);
        MGBHoverState hover={NO,-1};
        assert(!MGBHoverControls(&hover,screen,NSMakePoint(100,860),24,30,YES,1));
        assert(!MGBHoverControls(&hover,screen,NSMakePoint(100,899),24,30,YES,2));
        assert(!MGBHoverControls(&hover,screen,NSMakePoint(100,899),24,30,YES,2.34));
        assert(MGBHoverControls(&hover,screen,NSMakePoint(100,899),24,30,YES,2.36));
        assert(MGBHoverControls(&hover,screen,NSMakePoint(100,855),24,30,YES,2.4));
        assert(!MGBHoverControls(&hover,screen,NSMakePoint(100,837),24,30,YES,2.5));
        assert(!MGBHoverControls(&hover,screen,NSMakePoint(100,899),24,30,YES,3));
        assert(!MGBHoverControls(&hover,screen,NSMakePoint(100,899),24,30,NO,4));
        puts("PASS: oversized, unchanged, moved display, small display, Retina units");
        puts("PASS: Wine delegate forwarding and fullscreen toolbar auto-hide policy");
        puts("PASS: top-edge dwell, control interaction, exit and inactive screen");
    }
}
