#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>
#import <unistd.h>
static void event(NSString *s) { NSString *p=[NSTemporaryDirectory() stringByAppendingPathComponent:@"hoyobridge-real-update-events.log"]; NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:p]; if(!h){ [[NSFileManager defaultManager] createFileAtPath:p contents:nil attributes:nil]; h=[NSFileHandle fileHandleForWritingAtPath:p]; } [h seekToEndOfFile]; [h writeData:[[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
@interface Driver : NSObject <SPUUserDriver>
@end
@implementation Driver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)r reply:(void (^)(SUUpdatePermissionResponse *))reply { (void)r; reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))c { (void)c; event(@"checking"); }
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)i state:(SPUUserUpdateState *)s reply:(void (^)(SPUUserUpdateChoice))reply { (void)i;(void)s;event(@"found");reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)d { (void)d; }
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)e { event([@"notes-error " stringByAppendingString:e.localizedDescription]); }
- (void)showUpdateNotFoundWithError:(NSError *)e acknowledgement:(void (^)(void))a { event([@"not-found " stringByAppendingString:e.localizedDescription]);a();[NSApp terminate:nil]; }
- (void)showUpdaterError:(NSError *)e acknowledgement:(void (^)(void))a { event([@"error " stringByAppendingString:e.localizedDescription]);a();[NSApp terminate:nil]; }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))c {(void)c;event(@"download");}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)n {(void)n;}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)n {(void)n;}
- (void)showDownloadDidStartExtractingUpdate {event(@"extract");}
- (void)showExtractionReceivedProgress:(double)p {(void)p;}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {event(@"install");reply(SPUUserUpdateChoiceInstall);}
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)b retryTerminatingApplication:(void (^)(void))r {(void)b;(void)r;event(@"installing");}
- (void)showUpdateInstalledAndRelaunched:(BOOL)b acknowledgement:(void (^)(void))a {(void)b;event(@"installed");a();}
- (void)dismissUpdateInstallation {event(@"dismiss");}
@end
@interface App : NSObject <NSApplicationDelegate,SPUUpdaterDelegate>
@property Driver *driver;
@property SPUUpdater *updater;
@end
@implementation App
- (NSString *)feedURLStringForUpdater:(SPUUpdater *)u { (void)u; return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"MGBTestFeed"]; }
- (void)applicationDidFinishLaunching:(NSNotification *)n { (void)n; NSString *path=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"MGBTestTarget"]; NSBundle *host=[NSBundle bundleWithPath:path]; NSString *v=[host objectForInfoDictionaryKey:@"CFBundleVersion"]; NSString *expected=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"MGBTestVersion"] ?: @"0.1.5"; event([@"started " stringByAppendingString:v ?: @"missing"]); if ([v isEqualToString:expected]) {event(@"relaunch-success");[NSApp terminate:nil];return;} self.driver=[Driver new]; self.updater=[[SPUUpdater alloc] initWithHostBundle:host applicationBundle:NSBundle.mainBundle userDriver:self.driver delegate:self]; NSError *error=nil; if(![self.updater startUpdater:&error]) {event([@"start-error " stringByAppendingString:error.localizedDescription]);[NSApp terminate:nil];return;} [self.updater checkForUpdates]; }
@end
int main(void) { @autoreleasepool { [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; App *delegate=[App new]; NSApp.delegate=delegate; [NSApp run]; }}
