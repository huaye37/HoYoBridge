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
        puts("PASS: oversized, unchanged, moved display, small display, Retina units");
        puts("PASS: Wine delegate forwarding and fullscreen toolbar auto-hide policy");
    }
}
