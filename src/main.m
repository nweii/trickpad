#import <Cocoa/Cocoa.h>
#import <errno.h>
#import <limits.h>
#import <mach-o/dyld.h>
#import <signal.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#import "JitouchAppDelegate.h"
#import "SingleInstance.h"

// dyld searches DYLD_LIBRARY_PATH and DYLD_FRAMEWORK_PATH by leaf name before
// a library's install path. ImageIO loads its private libPng.dylib on the first
// PNG decode, so a shell that points these at Homebrew's lib folder hands
// ImageIO a foreign libpng, and decoding the app icon in Sparkle's update
// windows crashes with EXC_ARM_DA_ALIGN in PNGReadPlugin. dyld reads the
// variables only at launch, so the process restarts itself without them.
static void MGRelaunchWithoutLibraryPathOverrides(const char *argv[]) {
    static const char *const overrides[] = {"DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH"};
    BOOL overridden = NO;
    for (size_t i = 0; i < sizeof overrides / sizeof overrides[0]; i++) {
        if (getenv(overrides[i]) == NULL)
            continue;
        unsetenv(overrides[i]);
        overridden = YES;
    }
    if (!overridden)
        return;

    char path[PATH_MAX];
    uint32_t size = sizeof path;
    if (_NSGetExecutablePath(path, &size) != 0)
        return;
    execv(path, (char *const *)argv);
    fprintf(stderr, "Trickpad: relaunch without DYLD library path overrides failed: %s\n", strerror(errno));
}

int main(int argc, const char *argv[]) {
    MGRelaunchWithoutLibraryPathOverrides(argv);

    @autoreleasepool {
        // An update has two things starting the app: the updater relaunches it,
        // and the login agent's KeepAlive restarts what it saw exit. Two copies
        // both watch the devices, so every gesture would dispatch twice.
        // Checked before the status item exists, so no second icon appears.
        if (MGAnotherInstanceOwnsThisBundle())
            return 0;

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        JitouchAppDelegate *delegate = [[JitouchAppDelegate alloc] init];
        [app setDelegate:delegate];

        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGHUP, 0, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
        dispatch_source_set_event_handler(source, ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate reload];
            });
        });
        dispatch_resume(source);
        signal(SIGHUP, SIG_IGN);

        [app run];
    }
    return 0;
}
