#import <Cocoa/Cocoa.h>
#import <signal.h>

#import "JitouchAppDelegate.h"
#import "SingleInstance.h"

int main(int argc, const char *argv[]) {
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
