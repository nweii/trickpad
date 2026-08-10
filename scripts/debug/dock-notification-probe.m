// Reports which CoreDockSendNotification call form current macOS honors, by
// counting Dock-owned windows before and after each one. App Expose opens Dock
// windows, so a rise in the count means that call form did something. The
// private interface takes a second argument; a release that moves it again
// shows up here as both forms reporting no change.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>

static long dockWindows(void) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    long n = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
        NSDictionary *w = (NSDictionary *)CFArrayGetValueAtIndex(list, i);
        if ([[w objectForKey:(id)kCGWindowOwnerName] isEqualToString:@"Dock"]) n++;
    }
    CFRelease(list);
    return n;
}

int main(void) {
    void *sym = dlsym(RTLD_DEFAULT, "CoreDockSendNotification");
    if (!sym) { printf("symbol missing\n"); return 1; }
    long base = dockWindows();
    printf("baseline Dock windows: %ld\n", base);

    void (*one)(CFStringRef) = sym;
    one(CFSTR("com.apple.expose.front.awake"));
    usleep(700000);
    long afterOne = dockWindows();
    printf("after one-arg call:  %ld  %s\n", afterOne, afterOne > base ? "OPENED" : "no change");
    one(CFSTR("com.apple.expose.front.awake"));
    usleep(700000);

    void (*two)(CFStringRef, int) = sym;
    two(CFSTR("com.apple.expose.front.awake"), 0);
    usleep(700000);
    long afterTwo = dockWindows();
    printf("after two-arg call:  %ld  %s\n", afterTwo, afterTwo > base ? "OPENED" : "no change");
    two(CFSTR("com.apple.expose.front.awake"), 0);
    usleep(300000);
    return 0;
}
