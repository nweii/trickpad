//
//  JitouchAppDelegate.m
//  Jitouch
//
//  Copyright 2021 Supasorn Suwajanakorn and Sukolsak Sakshuwong. All rights reserved.
//  Modified work Copyright 2021 Aaron Kollasch. All rights reserved.
//  Modified work Copyright 2026 Nathan Cheng. All rights reserved.
//

#import "JitouchAppDelegate.h"
#import "Settings.h"
#import "Gesture.h"
#import "ApplicationScopeCache.h"
#import "CursorWindow.h"
#import <Carbon/Carbon.h>
#import <CoreFoundation/CFPreferences.h>
#import "SystemPreferences.h"
#import "Config.h"
#import "SystemGestureClaims.h"
#import "KeyUtility.h"
#import "TraceRecorder.h"
#import "UpdaterController.h"
#import "TraceSessionModel.h"

static NSMenuItem *MGMenuSectionHeader(NSString *title);
#include <pwd.h>
#include <unistd.h>
#include <fcntl.h>

static NSArray *lastConfigProblems = nil;
static NSInteger lastConfigBindingCount = 0;
static NSArray *lastConfigConflicts = nil;
static BOOL lastConfigRejected = NO;
static dispatch_source_t configWatcher = nil;
static int configWatcherFD = -1;
static NSInteger traceProtocolIndex = -1;
static NSPanel *tracePanel = nil;
static MGTraceSessionModel *traceSession = nil;
static NSTextField *traceHeading = nil;
static NSTextField *traceDetail = nil;
static NSTextField *traceProgress = nil;
static NSProgressIndicator *traceProgressBar = nil;
static NSView *traceSurface = nil;
static NSButton *tracePrimaryButton = nil;
static NSArray *traceLabelButtons = nil;
static NSButton *traceStopButton = nil;
static NSButton *traceExportButton = nil;
static NSTimer *tracePollTimer = nil;
static NSString *completedTracePath = nil;
static BOOL traceHeldLiftCueScheduled = NO;
static BOOL traceHeldLiftCuePlayed = NO;
static NSArray *activeTraceProtocol = nil;
static NSString *activeTraceProtocolTitle = nil;
static NSString *activeTraceProtocolOverview = nil;
static NSString *activeTraceObservedGesture = nil;

static BOOL internalTraceDiagnosticsEnabled(void) {
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:@"InternalTraceDiagnostics"];
}

static BOOL internalGestureDispatchToneEnabled(void) {
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:@"InternalGestureDispatchTone"];
}

static NSArray *magicMousePhysicalClickTraceProtocol(void) {
    static NSArray *steps = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        steps = [@[
            @{@"id": @"control-one-r1", @"requested": @"ordinary-click", @"expected": @0,
              @"instruction": @"Click naturally with one finger and lift at your usual speed."},
            @{@"id": @"control-one-r2", @"requested": @"ordinary-click", @"expected": @0,
              @"instruction": @"Repeat one natural one-finger click at your usual speed."},
            @{@"id": @"two-click-r1", @"requested": @"two-finger-click", @"expected": @1,
              @"instruction": @"Click naturally with two fingers and lift at your usual speed."},
            @{@"id": @"two-click-r2", @"requested": @"two-finger-click", @"expected": @1,
              @"instruction": @"Repeat one natural two-finger click at your usual speed."},
            @{@"id": @"two-click-r3", @"requested": @"two-finger-click", @"expected": @1,
              @"instruction": @"One final natural two-finger click at your usual speed."},
            @{@"id": @"two-click-held", @"requested": @"two-finger-click-held", @"expected": @1,
              @"lift_mode": @"held",
              @"instruction": @"Click with two fingers. Release the physical click but keep both fingers touching until the second tone, then lift."},
            @{@"id": @"quick-lift", @"requested": @"two-finger-click-immediate-lift", @"expected": @1,
              @"instruction": @"Release the click and remove both fingers together as quickly as comfortably possible."},
            @{@"id": @"two-click-upper", @"requested": @"two-finger-click-upper-surface", @"expected": @1,
              @"instruction": @"Place both fingertips naturally in the upper half of the touch surface. Click once and lift at your usual speed."},
            @{@"id": @"two-click-lower", @"requested": @"two-finger-click-lower-surface", @"expected": @1,
              @"instruction": @"Place both fingertips naturally in the lower half of the touch surface. Click once and lift at your usual speed."},
            @{@"id": @"three-click-r1", @"requested": @"three-finger-click", @"expected": @1,
              @"instruction": @"Click naturally with three fingers and lift at your usual speed."},
            @{@"id": @"three-click-r2", @"requested": @"three-finger-click", @"expected": @1,
              @"instruction": @"Repeat one natural three-finger click at your usual speed."},
            @{@"id": @"drag-control", @"requested": @"two-finger-drag", @"expected": @0,
              @"instruction": @"Press with two fingers, drag right a short distance, then release."},
            @{@"id": @"rear-contact", @"requested": @"ordinary-click-with-rear-contact", @"expected": @0,
              @"instruction": @"Ordinary click with your usual loose rear-palm contact. Do not contort your grip."},
            @{@"id": @"edge-contact", @"requested": @"ordinary-click-with-edge-contact", @"expected": @0,
              @"instruction": @"Ordinary click with one natural narrow side contact."},
            @{@"id": @"scroll-control", @"requested": @"native-scroll", @"expected": @0,
              @"instruction": @"Perform one normal horizontal scroll without clicking."},
            @{@"id": @"tap-control", @"requested": @"two-finger-tap", @"expected": @0,
              @"instruction": @"Perform one two-finger tap without physically clicking."},
            @{@"id": @"rapid-pair", @"requested": @"two-finger-click-pair", @"expected": @2,
              @"instruction": @"Perform two natural two-finger clicks in quick succession. Lift normally after each click."},
        ] retain];
    });
    return steps;
}

static NSArray *magicMouseTapCalibrationTraceProtocol(void) {
    static NSArray *steps = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        steps = [@[
            @{@"id": @"tap-natural-r1", @"requested": @"two-finger-tap", @"expected": @1,
              @"instruction": @"Tap with two fingers together. Do not physically click."},
            @{@"id": @"tap-natural-r2", @"requested": @"two-finger-tap", @"expected": @1,
              @"instruction": @"Repeat one natural two-finger tap. Do not physically click."},
            @{@"id": @"tap-natural-r3", @"requested": @"two-finger-tap", @"expected": @1,
              @"instruction": @"Perform one final natural two-finger tap. Do not physically click."},
            @{@"id": @"tap-edge-r1", @"requested": @"two-finger-tap-near-edge", @"expected": @1,
              @"instruction": @"Deliberately tap with two fingers near the side edge. Place both fingers together; do not physically click."},
            @{@"id": @"tap-edge-r2", @"requested": @"two-finger-tap-near-edge", @"expected": @1,
              @"instruction": @"Repeat one deliberate two-finger tap near the side edge. Do not physically click."},
            @{@"id": @"resting-edge-click-r1", @"requested": @"ordinary-click-with-resting-edge-contact", @"expected": @0,
              @"instruction": @"Rest one finger in your usual edge position. With another finger, make one ordinary click. Keep the resting finger down throughout."},
            @{@"id": @"resting-edge-click-r2", @"requested": @"ordinary-click-with-resting-edge-contact", @"expected": @0,
              @"instruction": @"Repeat the ordinary click with your usual resting edge finger present throughout."},
            @{@"id": @"resting-edge-scroll-r1", @"requested": @"ordinary-scroll-with-resting-edge-contact", @"expected": @0,
              @"instruction": @"Keep one natural edge contact resting. With another finger, scroll vertically a few lines. Do not click."},
            @{@"id": @"resting-edge-scroll-r2", @"requested": @"ordinary-scroll-with-resting-edge-contact", @"expected": @0,
              @"instruction": @"Repeat the scroll with your usual resting edge finger present throughout."},
            @{@"id": @"resting-edge-touch-r1", @"requested": @"resting-edge-contact-plus-touch", @"expected": @0,
              @"instruction": @"Rest one finger in your usual edge position. Briefly touch and lift another finger without clicking or scrolling."},
        ] retain];
    });
    return steps;
}

static NSArray *magicMouseAmbientGestureTraceProtocol(void) {
    static NSArray *steps = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        steps = [@[
            @{@"id": @"ambient-use", @"requested": @"ordinary-mouse-use", @"expected": @0,
              @"manual_capture": @YES,
              @"instruction": @"Use the mouse normally for up to two minutes. Click, scroll, and reposition as you usually would. Trickpad actions are suppressed while recording."},
        ] retain];
    });
    return steps;
}

static NSArray *magicMouseGestureCatalogAuditProtocol(void) {
    static NSArray *steps = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        steps = [@[
            @{@"id": @"catalog-audit", @"requested": @"gesture-catalog-audit", @"expected": @0,
              @"manual_capture": @YES, @"catalog_audit": @YES,
              @"instruction": @"Use the mouse normally for up to two minutes. Click, scroll, reposition, and switch Spaces as usual. Do not intentionally perform a Trickpad gesture. Actions and native-scroll suppression are disabled for shadow recognitions."},
        ] retain];
    });
    return steps;
}

// Builds one repetition per step for a motion that has no recognizer. Nothing
// is expected to dispatch, so every step records raw contact frames and a
// human execution-quality label only.
static NSArray *candidateGestureTraceProtocol(NSString *candidate, NSInteger repetitions) {
    NSMutableArray *steps = [NSMutableArray array];
    for (NSInteger repetition = 1; repetition <= repetitions; repetition++) {
        [steps addObject:@{
            @"id": [NSString stringWithFormat:@"candidate-r%ld", (long)repetition],
            // The name stays out of every step field the recorder writes into an
            // event. Only the panel heading shows it.
            @"requested": @"candidate-gesture",
            @"heading": candidate,
            @"expected": @0,
            @"instruction": [NSString stringWithFormat:
                @"Perform the candidate motion once, the same way each time. Repetition %ld of %ld.",
                (long)repetition, (long)repetitions]}];
    }
    return steps;
}

static NSArray *currentTraceProtocol(void) {
    return activeTraceProtocol ?: magicMousePhysicalClickTraceProtocol();
}

static NSString *traceObservedGestureForStep(NSDictionary *step) {
    if (activeTraceObservedGesture != nil) return activeTraceObservedGesture;
    return [[step objectForKey:@"requested"] hasPrefix:@"three-finger-click"]
        ? @"Three-Finger Click" : @"Two-Finger Click";
}

CursorWindow *cursorWindow;
CGKeyCode keyMap[128]; // for dvorak support

@interface JitouchAppDelegate ()
- (void)populateDiagnosticsMenu:(NSMenu *)menu;
- (void)populateGestureTestingMenu:(NSMenu *)menu;
@end

@implementation JitouchAppDelegate

@synthesize window;

// The launchd job that starts the app at login.
static NSString *const kLoginAgentLabel = @"fyi.thirdwind.trickpad.agent";
static NSString *const kLoginAgentPlistPath = @"~/Library/LaunchAgents/fyi.thirdwind.trickpad.agent.plist";
static NSString *const kDidChooseLoginItem = @"DidChooseLoginItem";
static BOOL runLaunchctl(NSArray *arguments);

// Removes the launchd job by label rather than plist path, so a job whose
// plist has already been deleted still stops instead of being respawned by
// KeepAlive after quit.
- (void)unloadJitouchLaunchAgent {
    NSString *target = [NSString stringWithFormat:@"gui/%d/%@", (int)getuid(), kLoginAgentLabel];
    NSArray *unloadArgs = [NSArray arrayWithObjects:@"bootout",
                           target,
                           nil];
    NSTask *unloadTask = [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:unloadArgs];
    [unloadTask waitUntilExit];
}

#pragma mark - Menu

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return YES;
}

// Tags identify menu items whose titles or check marks are updated after the
// menu is created.
enum {
    kMenuTagToggle = 1,
    kMenuTagLoginItem = 2,
    kMenuTagAccessibility = 3,
    kMenuTagBindings = 4,
    kMenuTagAgents = 5,
    kMenuTagDiagnostics = 7,
    kMenuTagConflicts = 8,
};

static NSString *shellQuote(NSString *s) {
    NSString *escaped = [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

// These directories are checked when the login shell cannot find a tool. They
// cover Homebrew on both architectures, user-local binaries, and common
// JavaScript runtime installers.
static NSArray *fallbackToolDirectories(void) {
    NSString *home = NSHomeDirectory();
    return @[[home stringByAppendingPathComponent:@".local/bin"],
             @"/opt/homebrew/bin",
             @"/usr/local/bin",
             @"/usr/bin",
             [home stringByAppendingPathComponent:@".bun/bin"],
             [home stringByAppendingPathComponent:@".deno/bin"],
             [home stringByAppendingPathComponent:@".cargo/bin"],
             [home stringByAppendingPathComponent:@".volta/bin"],
             [home stringByAppendingPathComponent:@".npm-global/bin"],
             [home stringByAppendingPathComponent:@".yarn/bin"],
             [home stringByAppendingPathComponent:@"bin"]];
}

// A launchd-started GUI app does not inherit SHELL or the user's PATH, so the
// login shell is read from the account record.
static NSString *loginShellPath(void) {
    struct passwd *pw = getpwuid(getuid());
    if (pw != NULL && pw->pw_shell != NULL) {
        NSString *shell = [NSString stringWithUTF8String:pw->pw_shell];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:shell])
            return shell;
    }
    return @"/bin/zsh";
}


// Describes a binding from its keycode and modifier flags. Labels describe an
// app-dependent purpose and may not match the focused app.
static NSString *describeBinding(NSDictionary *g) {
    if (![[g objectForKey:@"Enable"] boolValue])
        return @"Off";
    NSString *script = [g objectForKey:@"ScriptPath"];
    if ([script length] > 0)
        return [@"Run " stringByAppendingString:[script lastPathComponent]];
    NSString *sound = [g objectForKey:@"PlaySound"];
    if ([sound length] > 0)
        return [NSString stringWithFormat:@"Play sound \"%@\"", sound];
    NSString *speech = [g objectForKey:@"SpeakText"];
    if ([speech length] > 0) {
        const NSUInteger maxLength = 32;
        NSString *shown = [speech length] > maxLength
            ? [[speech substringToIndex:maxLength] stringByAppendingString:@"…"]
            : speech;
        return [NSString stringWithFormat:@"Say \"%@\"", shown];
    }
    NSString *url = [g objectForKey:@"OpenURL"];
    if ([url length] > 0) {
        const NSUInteger maxLength = 52;
        NSString *shown = [url length] > maxLength
            ? [[url substringToIndex:maxLength - 1] stringByAppendingString:@"…"]
            : url;
        return [@"Open " stringByAppendingString:shown];
    }
    if ([[g objectForKey:@"IsAction"] boolValue])
        return [g objectForKey:@"Command"] ?: @"";

    return [Config keystrokeDisplayNameForBinding:g];
}

// Two levels above the bundle, which is the project root when the app was built
// from a source checkout into its build directory. Anywhere else the path is
// meaningless and its contents are absent.
- (NSString *)projectRoot {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    if (bundlePath == nil || [bundlePath length] == 0)
        return nil;
    NSString *buildRoot = [bundlePath stringByDeletingLastPathComponent];
    return [[buildRoot stringByDeletingLastPathComponent] stringByStandardizingPath];
}

- (NSString *)loginAgentPlistPath {
    return [kLoginAgentPlistPath stringByStandardizingPath];
}

- (BOOL)isLoginItemInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self loginAgentPlistPath]];
}

// The menu bar is the only interface, so a menu action that fails says so in an
// alert naming the file or script involved.
- (void)reportFailure:(NSString *)message detail:(NSString *)detail {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:message];
    if ([detail length] > 0)
        [alert setInformativeText:detail];
    [alert setAlertStyle:NSAlertStyleWarning];
    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
    [alert release];
}

// Runs launchctl and returns YES when it exits cleanly. Failures are ignored by
// callers that only need a best effort.
static BOOL runLaunchctl(NSArray *arguments) {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/launchctl"];
    [task setArguments:arguments];
    [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];

    BOOL ok = NO;
    @try {
        [task launch];
        [task waitUntilExit];
        ok = ([task terminationStatus] == 0);
    } @catch (NSException *e) {
        ok = NO;
    }
    [task release];
    return ok;
}

// The launchd job runs the executable of whichever copy of the app wrote the
// plist, so the login item follows the app wherever it is installed.
- (NSString *)loginAgentPlistContents {
    NSString *executable = [[NSBundle mainBundle] executablePath];
    if (executable == nil)
        return nil;
    NSString *escaped = [[executable stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
                         stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    return [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<!--\n"
        @"  Trickpad maps Magic Mouse and Magic Trackpad gestures to keystrokes.\n"
        @"\n"
        @"  This file starts it at login and restarts it if it exits. It is written by\n"
        @"  the app's own Open at Login menu item. Deleting it stops the agent from\n"
        @"  starting at login and leaves the app itself untouched.\n"
        @"-->\n"
        @"<plist version=\"1.0\">\n"
        @"<dict>\n"
        @"  <key>Label</key>\n"
        @"  <string>%@</string>\n"
        @"  <key>ProgramArguments</key>\n"
        @"  <array>\n"
        @"    <string>%@</string>\n"
        @"  </array>\n"
        @"  <key>RunAtLoad</key>\n"
        @"  <true/>\n"
        @"  <key>KeepAlive</key>\n"
        @"  <true/>\n"
        @"  <key>ProcessType</key>\n"
        @"  <string>Interactive</string>\n"
        @"</dict>\n"
        @"</plist>\n", kLoginAgentLabel, escaped];
}

// Writes or removes the login item plist without changing the running launchd
// job. Returns a description when the requested state could not be reached.
- (NSString *)setLoginItemInstalled:(BOOL)install {
    NSString *plistPath = [self loginAgentPlistPath];
    NSString *guiTarget = [NSString stringWithFormat:@"gui/%d/%@", (int)getuid(), kLoginAgentLabel];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSString *failure = nil;

    if (!install) {
        // No bootout here: when the app was started by launchd, the job is this
        // process, and booting it out would quit the app mid-toggle. Removing
        // the plist is enough to stop the next login from starting it.
        if (![fm removeItemAtPath:plistPath error:&error])
            failure = [NSString stringWithFormat:@"%@ could not be removed. %@", plistPath, [error localizedDescription]];
    } else {
        NSString *contents = [self loginAgentPlistContents];
        NSString *dir = [plistPath stringByDeletingLastPathComponent];
        if (contents == nil) {
            failure = @"The app could not find its own program to start at login.";
        } else if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) {
            failure = [NSString stringWithFormat:@"%@ could not be created. %@", dir, [error localizedDescription]];
        } else if (![contents writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            failure = [NSString stringWithFormat:@"%@ could not be written. %@", plistPath, [error localizedDescription]];
        } else {
            // `launchctl disable` persists across logins, so a previously
            // disabled job would stay disabled without this.
            runLaunchctl(@[@"enable", guiTarget]);
        }
    }

    // Writing or removing the file can stop partway, so the resulting state is
    // read back from disk instead of assumed.
    if (failure == nil && [self isLoginItemInstalled] != install)
        failure = [NSString stringWithFormat:@"The login item is still %@.",
                   install ? @"missing" : @"in place"];

    return failure;
}

// The app is only useful while running, so a fresh installation starts at
// login. Recording the choice separately preserves a later opt-out.
- (void)enableLoginItemOnFirstLaunch {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kDidChooseLoginItem])
        return;

    [defaults setBool:YES forKey:kDidChooseLoginItem];
    [defaults synchronize];

    if (![self isLoginItemInstalled]) {
        NSString *failure = [self setLoginItemInstalled:YES];
        if (failure != nil)
            [self reportFailure:@"Can't turn on Open at Login." detail:failure];
    }
}

// The running process is left alone: bootstrapping the job here would start a
// second copy, and booting it out would terminate this one.
- (void)toggleLoginItem:(id)sender {
    NSString *failure = [self setLoginItemInstalled:![self isLoginItemInstalled]];

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kDidChooseLoginItem];

    [self refreshMenu];

    if (failure != nil)
        [self reportFailure:@"Can't change Open at Login." detail:failure];
}

// Reads the configuration file and applies it to the running gesture engine.
// The previous configuration stays in effect when the file cannot be read.
- (void)reloadConfiguration:(id)sender {
    NSString *path = [Config resolvedPath];
    if (path == nil) {
        [self reportFailure:@"No configuration file found."
                     detail:[NSString stringWithFormat:@"Expected it at %@/config.toml. Nothing changed.",
                             [Config configDirectory]]];
        return;
    }

    NSArray *problems = nil;
    NSDictionary *parsed = [Config settingsFromFile:path problems:&problems];
    if (parsed == nil) {
        [self setConfigProblems:problems];
        lastConfigRejected = YES;
        [self refreshMenu];
        NSString *detail = [problems count] > 0
            ? [[problems componentsJoinedByString:@"\n\n"] stringByAppendingString:@"\n\nNothing changed."]
            : [NSString stringWithFormat:@"%@ could not be opened. Nothing changed.", path];
        [self reportFailure:@"Could not apply the configuration." detail:detail];
        return;
    }

    [self setConfigProblems:problems];
    lastConfigRejected = NO;
    [self adoptConfiguration:parsed];
    [Settings loadSettings2:parsed];
    [self refreshMenu];
    if (!enAll)
        turnOffGestures();

    if ([problems count] > 0)
        [self showConfigProblems:nil];
}

// Applies the configuration file without reporting skipped lines. A save while
// a line is half-typed would otherwise raise an alert about work in progress.
- (void)applyConfigurationQuietly {
    NSString *path = [Config resolvedPath];
    if (path == nil)
        return;
    NSArray *problems = nil;
    NSDictionary *parsed = [Config settingsFromFile:path problems:&problems];
    if (parsed == nil) {
        [self setConfigProblems:problems];
        lastConfigRejected = YES;
        [self refreshMenu];
        return;
    }
    [self setConfigProblems:problems];
    lastConfigRejected = NO;
    [self adoptConfiguration:parsed];
    [Settings loadSettings2:parsed];
    [self refreshMenu];
    if (!enAll)
        turnOffGestures();
}

// Opening an already-running menu bar app restores its icon. This is the way
// back if the item was hidden and the setting to show it is gone.
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag {
    if (theItem == nil)
        [self showIcon];
    return YES;
}

- (void)startWatchingConfig {
    if (configWatcher != nil)
        return;

    NSString *dir = [Config configDirectory];
    configWatcherFD = open([dir fileSystemRepresentation], O_EVTONLY);
    if (configWatcherFD < 0)
        return;

    configWatcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, configWatcherFD,
                                           DISPATCH_VNODE_WRITE | DISPATCH_VNODE_RENAME |
                                           DISPATCH_VNODE_DELETE | DISPATCH_VNODE_ATTRIB,
                                           dispatch_get_main_queue());
    __block dispatch_source_t source = configWatcher;
    dispatch_source_set_event_handler(source, ^{
        // Coalesce the several events one save produces.
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(applyConfigurationQuietly)
                                                   object:nil];
        [self performSelector:@selector(applyConfigurationQuietly) withObject:nil afterDelay:0.3];
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(configWatcherFD);
        configWatcherFD = -1;
    });
    dispatch_resume(source);
}

- (void)setConfigProblems:(NSArray *)problems {
    [problems retain];
    [lastConfigProblems release];
    lastConfigProblems = problems;
}

// Every path that puts a parsed configuration into service records what the
// menu reports about it, so a new one cannot show a stale conflict list.
- (void)adoptConfiguration:(NSDictionary *)parsed {
    lastConfigBindingCount = [[parsed objectForKey:@"BindingCount"] integerValue];
    NSArray *conflicts = [parsed objectForKey:@"SystemGestureConflicts"];
    [conflicts retain];
    [lastConfigConflicts release];
    lastConfigConflicts = conflicts;
}

// macOS keeps its own gesture assignments, and a binding that shares a motion
// with one fires alongside it rather than instead of it.
- (void)showConfigConflicts:(id)sender {
    if ([lastConfigConflicts count] == 0)
        return;

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithFormat:@"%lu gesture%@ macOS also uses",
                           (unsigned long)[lastConfigConflicts count],
                           [lastConfigConflicts count] == 1 ? @"" : @"s"]];
    [alert setInformativeText:[NSString stringWithFormat:@"%@\n\n%@",
                               [lastConfigConflicts componentsJoinedByString:@"\n\n"],
                               MGSystemGestureSettingsProvenance()]];
    [alert setAlertStyle:NSAlertStyleInformational];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Edit Settings..."];
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse r = [alert runModal];
    [alert release];
    if (r == NSAlertSecondButtonReturn)
        [self preferences:nil];
}

// Skipped lines are the common failure in a hand-edited file, and nothing else
// in the app would show them.
- (void)showConfigProblems:(id)sender {
    if ([lastConfigProblems count] == 0)
        return;

    NSString *body = [lastConfigProblems componentsJoinedByString:@"\n\n"];
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithFormat:@"%lu line%@ skipped in config.toml",
                           (unsigned long)[lastConfigProblems count],
                           [lastConfigProblems count] == 1 ? @"" : @"s"]];
    [alert setInformativeText:[NSString stringWithFormat:@"%@\n\nEverything else was applied.", body]];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Edit Settings..."];
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse r = [alert runModal];
    [alert release];
    if (r == NSAlertSecondButtonReturn)
        [self preferences:nil];
}

- (void)about:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://thirdwind.fyi/trickpad/"]];
}

- (void)getLatestVersion:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://thirdwind.fyi/trickpad/download"]];
}

- (void)checkForUpdates:(id)sender {
    MGUpdaterCheckForUpdates();
}

// Sparkle keeps this setting in the host bundle's user defaults and its
// documentation says not to hold a second copy, so the menu reads the state
// back rather than tracking it. That is the reason this is not a config.toml
// key, and the one deliberate exception to the everything-in-TOML idiom.
//
// The same state sits behind Sparkle's own checkbox on the update alert, so
// the row reflects a choice made there, and can undo one.
- (void)toggleAutomaticUpdates:(id)sender {
    MGUpdaterSetUpdatesAutomatically(!MGUpdaterUpdatesAutomatically());
    [sender setState:MGUpdaterUpdatesAutomatically() ? NSOnState : NSOffState];
}

- (void)openDocs:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://thirdwind.fyi/trickpad/docs"]];
}

- (void)openAccessibilitySettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

// The event tap requires Accessibility access. The menu shows whether the
// process has this access because gestures do nothing without it.
- (void)refreshAccessibilityItem {
    NSMenuItem *item = [theMenu itemWithTag:kMenuTagAccessibility];
    if (item == nil)
        return;

    if (AXIsProcessTrusted()) {
        [item setTitle:@"Accessibility access granted"];
        [item setAction:NULL];
    } else {
        [item setTitle:@"Accessibility access needed..."];
        [item setAction:@selector(openAccessibilitySettings:)];
    }
}

// The binding count titles the submenu that lists what it counts, so one row
// carries the configuration state. A failed or partial reload changes the
// headline; the clickable details live on the submenu's first row.
- (void)refreshProblemsItem {
    NSMenuItem *item = [theMenu itemWithTag:kMenuTagBindings];
    if (item == nil)
        return;

    NSUInteger n = [lastConfigProblems count];
    if (lastConfigRejected) {
        [item setTitle:[NSString stringWithFormat:@"Reload failed, %ld binding%@ still active",
                        (long)lastConfigBindingCount,
                        lastConfigBindingCount == 1 ? @"" : @"s"]];
    } else if (n == 0) {
        [item setTitle:[NSString stringWithFormat:@"%ld binding%@ loaded",
                        (long)lastConfigBindingCount,
                        lastConfigBindingCount == 1 ? @"" : @"s"]];
    } else {
        [item setTitle:[NSString stringWithFormat:@"%ld binding%@ loaded, %lu skipped",
                        (long)lastConfigBindingCount,
                        lastConfigBindingCount == 1 ? @"" : @"s",
                        (unsigned long)n]];
    }
}

// A configuration with no shared motions has nothing to say, so the row stays
// hidden rather than reporting a clean result nobody asked for.
- (void)refreshConflictsItem {
    NSMenuItem *item = [theMenu itemWithTag:kMenuTagConflicts];
    if (item == nil)
        return;

    NSUInteger n = [lastConfigConflicts count];
    [item setHidden:n == 0];
    if (n == 0)
        return;
    [item setTitle:[NSString stringWithFormat:@"%lu gesture%@ macOS also uses...",
                    (unsigned long)n, n == 1 ? @"" : @"s"]];
}

// The trailing comment of one line, with # inside quoted TOML strings left
// alone.
static NSString *trailingLineComment(NSString *line) {
    BOOL inBasic = NO, inLiteral = NO, escaped = NO;
    for (NSUInteger i = 0; i < [line length]; i++) {
        unichar c = [line characterAtIndex:i];
        if (inBasic) {
            if (escaped) escaped = NO;
            else if (c == '\\') escaped = YES;
            else if (c == '"') inBasic = NO;
        } else if (inLiteral) {
            if (c == '\'') inLiteral = NO;
        } else if (c == '"') {
            inBasic = YES;
        } else if (c == '\'') {
            inLiteral = YES;
        } else if (c == '#') {
            return [[line substringFromIndex:i + 1] stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
        }
    }
    return nil;
}

// The comment on a binding's own configuration line, located by its section
// and key rather than a recorded line number: parsing reconstructs the file
// out of order in places, so recorded numbers can drift, while a TOML table
// cannot repeat a key. Costs one pass over the small file per menu rebuild,
// at launch and on reload, never during gesture recognition.
static NSString *commentForBindingLine(NSArray *configLines, NSString *device,
                                       NSString *application, NSString *bindingKey) {
    if ([bindingKey length] == 0)
        return nil;
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    BOOL inSection = NO;
    for (NSString *raw in configLines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:whitespace];
        if ([line hasPrefix:@"["]) {
            NSRange close = [line rangeOfString:@"]"];
            if (close.location == NSNotFound) { inSection = NO; continue; }
            NSString *header = [line substringWithRange:NSMakeRange(1, close.location - 1)];
            NSString *sectionDevice = header;
            NSString *sectionApp = nil;
            NSRange dot = [header rangeOfString:@"."];
            if (dot.location != NSNotFound) {
                sectionDevice = [header substringToIndex:dot.location];
                sectionApp = [[header substringFromIndex:dot.location + 1]
                    stringByTrimmingCharactersInSet:
                        [NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
            }
            BOOL deviceMatches = [sectionDevice caseInsensitiveCompare:device] == NSOrderedSame;
            BOOL appMatches = [application isEqualToString:@"All Applications"]
                ? sectionApp == nil
                : (sectionApp != nil && [sectionApp isEqualToString:application]);
            inSection = deviceMatches && appMatches;
            continue;
        }
        if (!inSection || ![line hasPrefix:bindingKey])
            continue;
        NSString *afterKey = [line substringFromIndex:[bindingKey length]];
        if ([afterKey length] == 0 ||
            !([afterKey hasPrefix:@"="] || [afterKey hasPrefix:@" "] ||
              [afterKey hasPrefix:@"\t"]))
            continue;
        return trailingLineComment(raw);
    }
    return nil;
}

// Where a skipped line belongs in the Current Gestures list, from its problem
// report ("line N:  text\n          reason"). Recorded line numbers can drift
// from the file, so placement demands the file still show a matching
// binding-shaped line at that number inside a device section; a problem that
// fails the match stays behind the details row rather than landing on the
// wrong group. Returns nil, or @{@"Device", @"Title", @"Reason"}.
static NSDictionary *skippedLinePlacement(NSString *problem, NSArray *configLines) {
    if (![problem hasPrefix:@"line "])
        return nil;
    NSRange newline = [problem rangeOfString:@"\n"];
    NSRange colon = [problem rangeOfString:@":  "];
    if (newline.location == NSNotFound || colon.location == NSNotFound ||
        colon.location > newline.location)
        return nil;
    NSInteger lineNumber = [[problem substringWithRange:
        NSMakeRange(5, colon.location - 5)] integerValue];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    NSString *text = [[problem substringWithRange:
        NSMakeRange(colon.location + 3, newline.location - colon.location - 3)]
        stringByTrimmingCharactersInSet:whitespace];
    NSString *reason = [[problem substringFromIndex:newline.location + 1]
        stringByTrimmingCharactersInSet:whitespace];
    if (lineNumber < 1 || (NSUInteger)lineNumber > [configLines count])
        return nil;

    // A binding line names a key before = or {; section headers and prose from
    // the structural checks do not qualify.
    if ([text hasPrefix:@"["])
        return nil;
    NSUInteger keyEnd = NSNotFound;
    for (NSUInteger i = 0; i < [text length]; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '=' || c == '{' || [whitespace characterIsMember:c]) { keyEnd = i; break; }
    }
    if (keyEnd == NSNotFound || keyEnd == 0)
        return nil;
    NSString *key = [text substringToIndex:keyEnd];
    NSString *fileLine = [configLines[(NSUInteger)lineNumber - 1]
        stringByTrimmingCharactersInSet:whitespace];
    if (![fileLine hasPrefix:key])
        return nil;

    for (NSInteger i = lineNumber - 1; i >= 0; i--) {
        NSString *line = [configLines[(NSUInteger)i]
            stringByTrimmingCharactersInSet:whitespace];
        if (![line hasPrefix:@"["])
            continue;
        NSString *header = [[line substringFromIndex:1] uppercaseString];
        if ([header hasPrefix:@"MOUSE"])
            return @{@"Device": @"Mouse", @"Title": text, @"Reason": reason};
        if ([header hasPrefix:@"TRACKPAD"])
            return @{@"Device": @"Trackpad", @"Title": text, @"Reason": reason};
        return nil;
    }
    return nil;
}

static NSArray *configFileLines(void) {
    NSString *path = [Config resolvedPath];
    NSString *text = path != nil
        ? [NSString stringWithContentsOfFile:path
                                    encoding:NSUTF8StringEncoding error:NULL]
        : nil;
    return text != nil ? [text componentsSeparatedByString:@"\n"] : @[];
}

- (void)refreshBindingsSubmenu {
    NSMenuItem *parent = [theMenu itemWithTag:kMenuTagBindings];
    if (parent == nil)
        return;

    NSMenu *sub = [[[NSMenu alloc] initWithTitle:@"Current Gestures"] autorelease];
    // Binding rows carry no action, and automatic validation would gray them
    // out. They stay enabled so the text reads at full contrast; clicking one
    // does nothing. Section headers and the empty row opt out individually.
    [sub setAutoenablesItems:NO];
    NSArray *configLines = configFileLines();

    if (lastConfigRejected || [lastConfigProblems count] > 0) {
        NSString *detailsTitle = lastConfigRejected
            ? @"Reload failed — details…"
            : [NSString stringWithFormat:@"%lu line%@ skipped — details…",
               (unsigned long)[lastConfigProblems count],
               [lastConfigProblems count] == 1 ? @"" : @"s"];
        NSMenuItem *details = [sub addItemWithTitle:detailsTitle
                                             action:@selector(showConfigProblems:)
                                      keyEquivalent:@""];
        [details setTarget:self];
        [sub addItem:[NSMenuItem separatorItem]];
    }
    NSArray *sources = @[@[@"Mouse", magicMouseCommands ?: @[], [Config mouseGestureSlugs]],
                         @[@"Trackpad", trackpadCommands ?: @[], [Config trackpadGestureSlugs]]];
    BOOL any = NO;

    // Skipped binding lines join their device group dimmed so the gap shows
    // where the user expects the binding. A rejected reload keeps the previous
    // configuration's bindings on screen, so its problems, which describe the
    // rejected file, stay behind the details row alone.
    NSMutableDictionary *skippedByDevice = [NSMutableDictionary dictionary];
    if (!lastConfigRejected) {
        for (NSString *problem in lastConfigProblems) {
            NSDictionary *placed = skippedLinePlacement(problem, configLines);
            if (placed == nil)
                continue;
            NSMutableArray *rows = [skippedByDevice objectForKey:placed[@"Device"]];
            if (rows == nil) {
                rows = [NSMutableArray array];
                [skippedByDevice setObject:rows forKey:placed[@"Device"]];
            }
            [rows addObject:placed];
        }
    }

    for (NSArray *pair in sources) {
        NSMutableArray *lines = [NSMutableArray array];
        for (NSDictionary *app in pair[1]) {
            NSMutableArray *appLines = [NSMutableArray array];
            NSString *application = [app objectForKey:@"Application"];
            NSString *scope = [application isEqualToString:@"All Applications"]
                ? @"" : [NSString stringWithFormat:@"%@ · ", application];
            NSMutableSet *seenGestures = [NSMutableSet set];
            for (NSDictionary *g in [[app objectForKey:@"Gestures"] reverseObjectEnumerator]) {
                NSString *gestureName = [g objectForKey:@"Gesture"];
                if (gestureName == nil)
                    continue;
                gestureName = [Config canonicalGestureName:gestureName inSlugs:pair[2]];
                if ([seenGestures containsObject:gestureName])
                    continue;
                NSString *fires = describeBinding(g);
                if ([fires length] == 0)
                    continue;
                [seenGestures addObject:gestureName];
                NSString *sourceText = [g objectForKey:@"SourceText"] ?: @"";
                NSString *bindingKey = [[sourceText componentsSeparatedByCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]] firstObject] ?: @"";
                NSString *comment = commentForBindingLine(configLines, pair[0],
                                                          application, bindingKey);
                [appLines insertObject:@[[NSString stringWithFormat:@"%@%@  →  %@", scope,
                                          [Config humanNameForGesture:gestureName], fires],
                                         comment ?: @""]
                                 atIndex:0];
            }
            [lines addObjectsFromArray:appLines];
        }
        NSArray *skipped = [skippedByDevice objectForKey:pair[0]] ?: @[];
        if ([lines count] == 0 && [skipped count] == 0)
            continue;

        if (any)
            [sub addItem:[NSMenuItem separatorItem]];
        any = YES;

        [sub addItem:MGMenuSectionHeader(pair[0])];
        for (NSArray *line in lines) {
            NSMenuItem *row = [sub addItemWithTitle:line[0] action:NULL keyEquivalent:@""];
            [row setIndentationLevel:1];
            // The user's own note from the binding's line, the way they wrote
            // it. The dimmed suffix keeps the row scannable; the tooltip
            // carries the note in full when it is long.
            NSString *comment = line[1];
            if ([comment length] > 0) {
                [row setToolTip:comment];
                // The cut lands on a composed-character boundary so an emoji
                // or accented letter at the limit is dropped whole rather
                // than split into a broken glyph.
                NSString *shown = comment;
                if ([comment length] > 40) {
                    NSRange safe = [comment rangeOfComposedCharacterSequenceAtIndex:40];
                    shown = [[comment substringToIndex:safe.location]
                             stringByAppendingString:@"…"];
                }
                // Parentheses at full menu size separate the user's note from
                // the binding while skimming; shrunken text read as noise, and
                // color alone cannot carry the boundary. The binding renders
                // at full label strength like its neighbors; the dimmed note
                // marks where the user's own words begin.
                NSMutableAttributedString *title = [[[NSMutableAttributedString alloc]
                    initWithString:[NSString stringWithFormat:@"%@  (%@)", line[0], shown]]
                    autorelease];
                NSUInteger mainLength = [(NSString *)line[0] length];
                [title addAttributes:@{
                        NSFontAttributeName: [NSFont menuFontOfSize:0],
                        NSForegroundColorAttributeName: [NSColor labelColor],
                    } range:NSMakeRange(0, mainLength)];
                [title addAttributes:@{
                        NSFontAttributeName: [NSFont menuFontOfSize:0],
                        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                    } range:NSMakeRange(mainLength,
                                        [[title string] length] - mainLength)];
                [row setAttributedTitle:title];
            }
        }
        // The whole row dims where a note only dims its parenthetical, so a
        // skipped line reads as absent rather than active; the reason it was
        // skipped rides on the tooltip.
        for (NSDictionary *placed in skipped) {
            NSMenuItem *row = [sub addItemWithTitle:placed[@"Title"] action:NULL keyEquivalent:@""];
            [row setIndentationLevel:1];
            [row setToolTip:placed[@"Reason"]];
            NSAttributedString *title = [[[NSAttributedString alloc]
                initWithString:placed[@"Title"]
                    attributes:@{
                        NSFontAttributeName: [NSFont menuFontOfSize:0],
                        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                    }] autorelease];
            [row setAttributedTitle:title];
        }
    }

    if (!any) {
        NSMenuItem *empty = [sub addItemWithTitle:@"Nothing configured yet" action:NULL keyEquivalent:@""];
        [empty setEnabled:NO];
    }

    [parent setSubmenu:sub];
}

- (NSString *)debugInformation {
    NSString *version = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *stamp = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"TrickpadBuildStamp"];
    if (stamp != nil)
        version = [NSString stringWithFormat:@"%@ (%@)", version, stamp];
    NSString *configPath = [Config resolvedPath] ?: @"missing";
    return [NSString stringWithFormat:
        @"Trickpad %@\nmacOS %@\nAccessibility: %@\nConfiguration: %@\n"
         "%ld binding%@ loaded\n%lu line%@ skipped\nGestures: %@\n"
         "Mouse: %@\nTrackpad: %@\nVerbose logging: %@\n",
        version,
        [[NSProcessInfo processInfo] operatingSystemVersionString],
        AXIsProcessTrusted() ? @"granted" : @"needed",
        configPath,
        (long)lastConfigBindingCount, lastConfigBindingCount == 1 ? @"" : @"s",
        (unsigned long)[lastConfigProblems count], [lastConfigProblems count] == 1 ? @"" : @"s",
        enAll ? @"on" : @"off",
        enMMAll ? @"on" : @"off",
        enTPAll ? @"on" : @"off",
        logLevel >= LOG_LEVEL_DEBUG ? @"on" : @"off"];
}

- (void)copyDebugInfo:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:[self debugInformation] forType:NSPasteboardTypeString];
}

- (void)openRecentLogs:(id)sender {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSTask *task = [[NSTask alloc] init];
            NSPipe *output = [NSPipe pipe];
            [task setLaunchPath:@"/usr/bin/log"];
            [task setArguments:@[@"show", @"--style", @"compact", @"--last", @"15m",
                                 @"--predicate", @"process == \"Trickpad\""]];
            [task setStandardOutput:output];
            [task setStandardError:output];

            NSData *data = nil;
            NSString *failure = nil;
            @try {
                [task launch];
                data = [[output fileHandleForReading] readDataToEndOfFile];
                [task waitUntilExit];
            } @catch (NSException *exception) {
                failure = [exception reason];
            }

            NSString *path = [NSTemporaryDirectory()
                stringByAppendingPathComponent:@"Trickpad-Recent.log"];
            NSError *error = nil;
            BOOL wrote = failure == nil &&
                [data writeToFile:path options:NSDataWritingAtomic error:&error];
            [task release];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!wrote || ![[NSWorkspace sharedWorkspace]
                        openURL:[NSURL fileURLWithPath:path]])
                    [self reportFailure:@"Could not open recent logs."
                                 detail:failure ?: [error localizedDescription] ?: path];
            });
        }
    });
}

- (void)toggleVerboseLogging:(id)sender {
    logLevel = logLevel >= LOG_LEVEL_DEBUG ? LOG_LEVEL_INFO : LOG_LEVEL_DEBUG;
    [self refreshMenu];
}

- (void)toggleGestureDispatchTone:(id)sender {
    [[NSUserDefaults standardUserDefaults]
        setBool:!internalGestureDispatchToneEnabled()
         forKey:@"InternalGestureDispatchTone"];
    [self refreshMenu];
}

static NSTextField *traceText(NSRect frame, CGFloat size, BOOL bold) {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setEditable:NO]; [field setSelectable:NO]; [field setBezeled:NO];
    [field setDrawsBackground:NO]; [field setUsesSingleLineMode:NO];
    [field setFont:bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size]];
    return field;
}

- (void)updateTraceWindow {
    if (tracePanel == nil || traceSession == nil) return;
    MGTraceSessionPhase phase = [traceSession phase];
    NSInteger index = [traceSession stepIndex];
    NSUInteger count = [[traceSession steps] count];
    NSDictionary *step = index >= 0 && index < (NSInteger)count
        ? [[traceSession steps] objectAtIndex:index] : nil;
    BOOL manualCapture = [[step objectForKey:@"manual_capture"] boolValue];
    BOOL catalogAudit = [[step objectForKey:@"catalog_audit"] boolValue];
    NSArray *phaseNames = @[@"Overview", @"Preparing", @"Neutral countdown",
        @"Recording", @"Waiting for full lift", @"Ready for label", @"Complete"];
    [traceProgress setStringValue:phase == MGTraceSessionOverview
        ? (manualCapture ? @"1 capture · up to 2 minutes" :
            [NSString stringWithFormat:@"%lu steps · about 4 minutes", (unsigned long)count])
        : phase == MGTraceSessionComplete
            ? [NSString stringWithFormat:@"%lu of %lu complete", (unsigned long)count, (unsigned long)count]
        : [NSString stringWithFormat:@"Step %ld of %lu · %@", (long)index + 1,
            (unsigned long)count, phaseNames[phase]]];
    [traceProgressBar setDoubleValue:phase == MGTraceSessionComplete ? count : MAX(index, 0)];

    if (phase == MGTraceSessionOverview) {
        [traceHeading setStringValue:activeTraceProtocolTitle ?: @"Magic Mouse trace session"];
        [traceDetail setStringValue:activeTraceProtocolOverview ?: @"Trickpad reports detection automatically. You only label whether your physical attempt matched the instruction.\n\nUse Return, M, U, or K so the pointer can stay in the gray surface. After each label, the next three-second countdown starts automatically. Configured Trickpad actions are suppressed; native mouse behavior remains active."];
    } else if (phase == MGTraceSessionComplete) {
        [traceHeading setStringValue:@"Trace complete"];
        [traceDetail setStringValue:[NSString stringWithFormat:
            @"All %lu steps are labeled. The redacted bundle is ready to export.\n\nTemporary bundle: %@",
            (unsigned long)count,
            completedTracePath ?: @"Analysis is finishing…"]];
    } else {
        [traceHeading setStringValue:[step objectForKey:@"heading"]
            ?: [step objectForKey:@"requested"] ?: @"Trace step"];
        NSDictionary *status = MGTraceStatus();
        NSString *stateInstruction = phase == MGTraceSessionPreparing
            ? (manualCapture
                ? @"Lift fully, then click the gray test surface or press Space. After the tone, use the mouse in any app as you normally would."
                : @"Place the pointer in the gray test surface, lift fully, then click anywhere in the surface or press Space.")
            : phase == MGTraceSessionCountdown
                ? [NSString stringWithFormat:@"Keep fully lifted and still. Recording begins in %ld…",
                    (long)[traceSession countdown]]
                : phase == MGTraceSessionRecording
                    ? (manualCapture
                        ? [NSString stringWithFormat:@"%@: %@ observed so far. Keep using the mouse normally, then choose Stop and Export Partial.",
                            [status objectForKey:catalogAudit ? @"catalog_candidate_count" : @"observed_dispatch_count"],
                            [[status objectForKey:catalogAudit ? @"catalog_candidate_count" : @"observed_dispatch_count"] unsignedIntegerValue] == 1
                                ? (catalogAudit ? @"potential gesture" : @"configured gesture")
                                : (catalogAudit ? @"potential gestures" : @"configured gestures")]
                        : ([[step objectForKey:@"lift_mode"] isEqualToString:@"held"] && traceHeldLiftCuePlayed
                        ? @"The second tone sounded. Lift both fingers now."
                        : @"Perform the motion now."))
                : phase == MGTraceSessionWaitingForLift
                    ? ([[step objectForKey:@"lift_mode"] isEqualToString:@"held"] && !traceHeldLiftCuePlayed
                        ? @"Keep both fingers touching. Lift only after the second tone."
                        : @"Lift every contact and wait.")
                : [NSString stringWithFormat:
                    @"Detected %@ of %@ expected. Now label only the quality of your physical attempt.",
                    [status objectForKey:@"observed_dispatch_count"],
                    [status objectForKey:@"expected_dispatch_count"]];
        [traceDetail setStringValue:[NSString stringWithFormat:@"%@\n\n%@",
            [step objectForKey:@"instruction"], stateInstruction]];
    }

    BOOL overview = phase == MGTraceSessionOverview;
    BOOL preparing = phase == MGTraceSessionPreparing;
    [tracePrimaryButton setHidden:!overview];
    [tracePrimaryButton setTitle:@"Begin session ↩"];
    [tracePrimaryButton setKeyEquivalent:@"\r"];
    for (NSButton *button in traceLabelButtons) {
        [button setEnabled:[traceSession labelsEnabled]];
        [button setHidden:![traceSession labelsEnabled]];
    }
    [traceExportButton setHidden:phase != MGTraceSessionComplete];
    [traceStopButton setHidden:NO];
    [traceStopButton setTitle:phase == MGTraceSessionComplete ? @"Close Esc" : @"Stop Esc"];
    [traceStopButton setAction:phase == MGTraceSessionComplete
        ? @selector(closeTraceWindow:) : @selector(stopTraceSession:)];
}

- (void)tracePoll:(NSTimer *)timer {
    if (!MGTraceIsActive() || traceSession == nil) return;
    NSDictionary *status = MGTraceStatus();
    NSInteger index = [traceSession stepIndex];
    NSArray *steps = [traceSession steps];
    NSDictionary *step = index >= 0 && index < (NSInteger)[steps count]
        ? [steps objectAtIndex:index] : nil;
    BOOL manualCapture = [[step objectForKey:@"manual_capture"] boolValue];
    [traceSession observeCapturing:[[status objectForKey:@"capturing"] boolValue]
                     awaitingLabel:[[status objectForKey:@"awaiting_label"] boolValue]
                       sawContacts:manualCapture ? NO : [[status objectForKey:@"saw_contacts"] boolValue]];
    if ([[step objectForKey:@"lift_mode"] isEqualToString:@"held"] &&
        [[status objectForKey:@"capturing"] boolValue] &&
        [[status objectForKey:@"saw_mouse_up"] boolValue] && !traceHeldLiftCueScheduled) {
        traceHeldLiftCueScheduled = YES;
        NSInteger cueStep = index;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (MGTraceIsActive() && [traceSession stepIndex] == cueStep &&
                [[MGTraceStatus() objectForKey:@"capturing"] boolValue]) {
                traceHeldLiftCuePlayed = YES;
                NSBeep();
                [self updateTraceWindow];
            }
        });
    }
    [self updateTraceWindow];
}

- (void)traceCountdownTick {
    if (traceSession == nil || !MGTraceIsActive()) return;
    if ([traceSession tickCountdown]) {
        NSDictionary *step = [currentTraceProtocol() objectAtIndex:[traceSession stepIndex]];
        MGTraceBeginStep([step objectForKey:@"id"], [step objectForKey:@"requested"],
                         traceObservedGestureForStep(step),
                         [[step objectForKey:@"expected"] unsignedIntegerValue],
                         [step objectForKey:@"instruction"],
                         ![[step objectForKey:@"manual_capture"] boolValue],
                         [[step objectForKey:@"catalog_audit"] boolValue]);
        traceHeldLiftCueScheduled = NO;
        traceHeldLiftCuePlayed = NO;
        NSBeep();
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [self traceCountdownTick]; });
    }
    [self updateTraceWindow];
}

- (void)tracePrimary:(id)sender {
    if ([traceSession phase] == MGTraceSessionOverview) [traceSession beginProtocol];
    else if ([traceSession phase] == MGTraceSessionPreparing) {
        [traceSession beginCountdown];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [self traceCountdownTick]; });
    }
    [self updateTraceWindow];
}

- (void)traceSurfaceClicked:(id)sender {
    if ([traceSession phase] == MGTraceSessionPreparing)
        [self tracePrimary:sender];
}

- (void)buildTraceWindow {
    if (tracePanel != nil) return;
    tracePanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 720, 610)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow
        backing:NSBackingStoreBuffered defer:NO];
    [tracePanel setTitle:@"Trickpad Diagnostics"];
    [tracePanel setFloatingPanel:YES]; [tracePanel setHidesOnDeactivate:NO];
    NSView *content = [tracePanel contentView];
    traceProgress = [traceText(NSMakeRect(28, 565, 664, 22), 13, NO) retain];
    traceProgressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(28, 545, 664, 8)];
    [traceProgressBar setIndeterminate:NO];
    [traceProgressBar setMaxValue:[[traceSession steps] count]];
    traceHeading = [traceText(NSMakeRect(28, 490, 664, 38), 24, YES) retain];
    traceDetail = [traceText(NSMakeRect(28, 375, 664, 105), 15, NO) retain];
    NSButton *surfaceButton = [[NSButton alloc] initWithFrame:NSMakeRect(28, 145, 664, 210)];
    [surfaceButton setBordered:NO]; [surfaceButton setTitle:@""];
    [surfaceButton setTarget:self]; [surfaceButton setAction:@selector(traceSurfaceClicked:)];
    traceSurface = surfaceButton;
    [traceSurface setWantsLayer:YES];
    [[traceSurface layer] setBackgroundColor:[[NSColor colorWithWhite:0.18 alpha:1] CGColor]];
    [[traceSurface layer] setCornerRadius:12];
    NSTextField *surfaceText = traceText(NSMakeRect(20, 85, 624, 50), 18, YES);
    [surfaceText setAlignment:NSTextAlignmentCenter];
    [surfaceText setTextColor:[NSColor colorWithWhite:1 alpha:0.72]];
    [surfaceText setStringValue:@"INERT TEST SURFACE\nPark the pointer and perform mouse motions here"];
    [traceSurface addSubview:surfaceText];
    tracePrimaryButton = [[NSButton alloc] initWithFrame:NSMakeRect(28, 92, 190, 32)];
    [tracePrimaryButton setBezelStyle:NSBezelStyleRounded]; [tracePrimaryButton setTarget:self];
    [tracePrimaryButton setAction:@selector(tracePrimary:)];
    NSArray *labels = @[@[@"Clean attempt ↩", @"clean", @"\r"], @[@"Botched attempt M", @"botched", @"m"],
        @[@"Unsure U", @"unsure", @"u"], @[@"Skip K", @"skip", @"k"]];
    NSMutableArray *buttons = [NSMutableArray array];
    CGFloat x = 28;
    NSInteger labelIndex = 0;
    for (NSArray *item in labels) {
        NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(x, 92, 154, 32)] autorelease];
        [button setTitle:item[0]]; [button setTag:labelIndex++];
        [button setKeyEquivalent:item[2]]; [button setTarget:self];
        [button setAction:@selector(markTraceStep:)]; [content addSubview:button];
        [buttons addObject:button]; x += 166;
    }
    traceLabelButtons = [buttons copy];
    traceStopButton = [[NSButton alloc] initWithFrame:NSMakeRect(28, 34, 130, 32)];
    [traceStopButton setTitle:@"Stop Esc"]; [traceStopButton setKeyEquivalent:@"\033"];
    [traceStopButton setTarget:self]; [traceStopButton setAction:@selector(stopTraceSession:)];
    traceExportButton = [[NSButton alloc] initWithFrame:NSMakeRect(530, 34, 162, 32)];
    [traceExportButton setTitle:@"Export bundle E"]; [traceExportButton setKeyEquivalent:@"e"];
    [traceExportButton setTarget:self]; [traceExportButton setAction:@selector(exportCompletedTrace:)];
    for (NSView *view in @[traceProgress, traceProgressBar, traceHeading, traceDetail,
                           traceSurface, tracePrimaryButton, traceStopButton, traceExportButton])
        [content addSubview:view];
    [tracePanel center];
}

// Asks for the candidate name and repetition count. Returns NO when the person
// cancels or leaves the name empty.
- (BOOL)askForCandidateGesture:(NSString **)candidate repetitions:(NSInteger *)repetitions {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Record a candidate gesture"];
    [alert setInformativeText:@"Name the motion you are prototyping and choose how many repetitions to record. No recognizer runs against it; the session records raw contact frames and your label for each repetition."];
    [alert addButtonWithTitle:@"Start"];
    [alert addButtonWithTitle:@"Cancel"];
    NSView *fields = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 54)] autorelease];
    NSTextField *nameField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 28, 300, 24)] autorelease];
    [[nameField cell] setPlaceholderString:@"Candidate name, such as corner-pull"];
    NSTextField *countField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)] autorelease];
    [countField setStringValue:@"10"];
    [fields addSubview:nameField]; [fields addSubview:countField];
    [alert setAccessoryView:fields];
    [[alert window] setInitialFirstResponder:nameField];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] != NSAlertFirstButtonReturn) return NO;
    NSString *name = [[nameField stringValue] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([name length] == 0) return NO;
    if ([name length] > 40) name = [name substringToIndex:40];
    NSInteger count = [countField integerValue];
    *candidate = name;
    *repetitions = MIN(MAX(count, 1), 60);
    return YES;
}

- (void)startTraceSession:(id)sender {
    if (MGTraceIsActive()) return;
    BOOL tapCalibration = [sender tag] == 1;
    BOOL ambientCapture = [sender tag] == 2;
    BOOL catalogAudit = [sender tag] == 3;
    BOOL candidateGesture = [sender tag] == 4;
    if (!enMMAll && !candidateGesture) {
        [self reportFailure:@"Magic Mouse gestures are turned off."
                     detail:@"Turn them on in config.toml before starting a trace session. Nothing changed."];
        return;
    }
    NSString *candidateName = nil;
    NSInteger candidateRepetitions = 0;
    if (candidateGesture &&
        ![self askForCandidateGesture:&candidateName repetitions:&candidateRepetitions])
        return;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"Trickpad-Trace-%@", [[NSUUID UUID] UUIDString]]];
    NSString *problem = nil;
    if (!MGTraceStartCapture(path, candidateGesture ? @"candidate-gesture-guided"
                                                    : @"magic-mouse-guided",
                             candidateName, &problem)) {
        [self reportFailure:@"Could not start the trace session." detail:problem];
        return;
    }
    [activeTraceProtocol release];
    activeTraceProtocol = [(candidateGesture
            ? candidateGestureTraceProtocol(candidateName, candidateRepetitions) :
        catalogAudit ? magicMouseGestureCatalogAuditProtocol() :
        ambientCapture ? magicMouseAmbientGestureTraceProtocol() :
        tapCalibration ? magicMouseTapCalibrationTraceProtocol() :
        magicMousePhysicalClickTraceProtocol()) retain];
    [activeTraceProtocolTitle release];
    activeTraceProtocolTitle = [(candidateGesture
            ? [NSString stringWithFormat:@"Candidate gesture: %@", candidateName] :
        catalogAudit ? @"Audit gesture catalog" :
        ambientCapture ? @"Capture normal mouse use" :
        tapCalibration ? @"Magic Mouse tap calibration" :
        @"Magic Mouse physical-click trace") copy];
    [activeTraceProtocolOverview release];
    activeTraceProtocolOverview = [(candidateGesture
        ? [NSString stringWithFormat:@"This records the same motion %ld times on the trackpad or the Magic Mouse so a recognizer can be designed from the data. No recognizer runs against it, so nothing is detected and nothing dispatches. Perform the motion the same way each time, then label how well you executed it.\n\nUse Return, M, U, or K so the pointer can stay in the gray surface. Botched retries the same repetition; the other labels advance. Configured Trickpad actions are suppressed; native behavior remains active.", (long)candidateRepetitions] :
        catalogAudit
        ? @"This shadow-audits every supported Magic Mouse recognizer during up to two minutes of ordinary use, including gestures absent from your configuration. It never fires actions, claims a gesture sequence, or suppresses native scrolling. Potential recognitions are listed in the exported report. Choose Stop, then Export Partial when finished."
        : ambientCapture
        ? @"This captures up to two minutes of ordinary Magic Mouse use so any unexpected configured gesture can be identified without guessing what motion caused it. Work normally after the countdown. Trickpad actions are suppressed, and the panel counts every would-be gesture dispatch. Choose Stop, then Export Partial when finished."
        : tapCalibration
        ? @"This takes about 3 minutes. It compares deliberate two-finger taps, including taps near an edge, against your natural resting edge contact during ordinary clicks, scrolling, and a brief extra touch. Trickpad reports detection automatically. You only label whether your physical attempt matched the instruction.\n\nUse Return, M, U, or K so the pointer can stay in the gray surface. Botched retries the same step; the other labels advance. Configured Trickpad actions are suppressed; native mouse behavior remains active."
        : @"This takes about 4 minutes. It compares natural, deliberately held, and immediate lifts, upper and lower contact positions, then checks drag, contact-shape, scroll, tap, and rapid-repeat conflicts. Trickpad reports detection automatically. You only label whether your physical attempt matched the instruction.\n\nUse Return, M, U, or K so the pointer can stay in the gray surface. Botched retries the same step; the other labels advance. Configured Trickpad actions are suppressed; native mouse behavior remains active.") copy];
    [activeTraceObservedGesture release];
    activeTraceObservedGesture = [(candidateGesture ? @"none" :
        (ambientCapture || catalogAudit) ? @"*" :
        tapCalibration ? @"Two-Finger Tap" : nil) copy];
    [traceSession release];
    traceSession = [[MGTraceSessionModel alloc] initWithSteps:currentTraceProtocol()];
    traceProtocolIndex = 0;
    [self buildTraceWindow]; [self updateTraceWindow];
    [tracePanel makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [tracePollTimer invalidate];
    tracePollTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self
        selector:@selector(tracePoll:) userInfo:nil repeats:YES];
}

- (void)markTraceStep:(id)sender {
    NSDictionary *status = MGTraceStatus();
    if (![[status objectForKey:@"awaiting_label"] boolValue]) return;
    NSArray *labels = @[@"clean", @"botched", @"unsure", @"skip"];
    NSInteger labelIndex = [sender tag];
    if (labelIndex < 0 || labelIndex >= (NSInteger)[labels count]) return;
    NSString *label = [labels objectAtIndex:labelIndex];
    MGTraceMarkStep(label);
    if ([label isEqualToString:@"botched"])
        [traceSession retryCurrentStep];
    else
        [traceSession markCurrentStep];
    traceProtocolIndex = [traceSession stepIndex];
    if ([traceSession phase] == MGTraceSessionComplete) {
        [tracePollTimer invalidate]; tracePollTimer = nil;
        [completedTracePath release]; completedTracePath = [MGTraceBundlePath() copy];
        MGTraceStop();
    } else {
        [traceSession beginCountdown];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [self traceCountdownTick]; });
    }
    [self updateTraceWindow]; [self refreshMenu];
}

- (void)stopTraceSession:(id)sender {
    if (!MGTraceIsActive()) return;
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Stop this incomplete trace?"];
    [alert setInformativeText:@"Export Partial keeps the labeled steps. Discard deletes the temporary bundle. Continue returns to the session."];
    [alert addButtonWithTitle:@"Export Partial"];
    [alert addButtonWithTitle:@"Discard"];
    [alert addButtonWithTitle:@"Continue"];
    NSModalResponse choice = [alert runModal];
    if (choice == NSAlertThirdButtonReturn) return;
    NSDictionary *step = traceProtocolIndex >= 0 &&
        traceProtocolIndex < (NSInteger)[[traceSession steps] count]
        ? [[traceSession steps] objectAtIndex:traceProtocolIndex] : nil;
    if ([[step objectForKey:@"manual_capture"] boolValue])
        MGTraceFinishOpenStep(@"ambient");
    [tracePollTimer invalidate]; tracePollTimer = nil;
    [completedTracePath release]; completedTracePath = [MGTraceBundlePath() copy];
    MGTraceStop();
    [self showTraceCloseControl];
    traceProtocolIndex = -1;
    if (choice == NSAlertSecondButtonReturn) {
        [[NSFileManager defaultManager] removeItemAtPath:completedTracePath error:nil];
        [tracePanel orderOut:nil];
        [traceSession release]; traceSession = nil;
        [completedTracePath release]; completedTracePath = nil;
        [self refreshMenu];
        return;
    }
    [self exportCompletedTrace:nil];
}

- (void)closeTraceWindow:(id)sender {
    [tracePanel orderOut:nil];
    [traceSession release]; traceSession = nil;
    [completedTracePath release]; completedTracePath = nil;
    traceProtocolIndex = -1;
    [self refreshMenu];
}

- (void)showTraceCloseControl {
    [traceStopButton setTitle:@"Close Esc"];
    [traceStopButton setAction:@selector(closeTraceWindow:)];
    [traceStopButton setEnabled:YES];
}

- (void)exportCompletedTrace:(id)sender {
    NSString *source = completedTracePath;
    if (source == nil) return;

    NSString *analyzer = [[NSBundle mainBundle] pathForResource:@"analyze-trace" ofType:nil];
    BOOL analysisOK = NO;
    if (analyzer != nil) {
        NSTask *task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath:analyzer];
        [task setArguments:@[source]];
        [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
        [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
        @try {
            [task launch];
            [task waitUntilExit];
            analysisOK = [task terminationStatus] == 0;
        } @catch (NSException *exception) {}
    }
    if (!analysisOK) {
        [self reportFailure:@"Could not analyze the trace bundle."
                     detail:@"The private temporary capture was kept. Nothing was exported."];
        [self refreshMenu];
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setTitle:@"Export redacted trace bundle"];
    [panel setNameFieldStringValue:[source lastPathComponent]];
    [panel setCanCreateDirectories:YES];
    [NSApp activateIgnoringOtherApps:YES];
    if ([panel runModal] == NSModalResponseOK) {
        NSString *destination = [[panel URL] path];
        NSError *error = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:destination] ||
            ![[NSFileManager defaultManager] moveItemAtPath:source toPath:destination error:&error]) {
            [self reportFailure:@"Could not export the trace bundle."
                         detail:error ? [error localizedDescription] : @"Choose a new bundle name."];
        } else {
            [completedTracePath release]; completedTracePath = [destination copy];
            [traceDetail setStringValue:[NSString stringWithFormat:
                @"Export complete.\n\nBundle: %@", destination]];
            [self showTraceCloseControl];
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:
                @[[NSURL fileURLWithPath:destination]]];
        }
    }
    [self refreshMenu];
}

- (void)populateDiagnosticsMenu:(NSMenu *)menu {
    [menu removeAllItems];
    NSMenuItem *copy = [menu addItemWithTitle:@"Copy Debug Info"
                                       action:@selector(copyDebugInfo:) keyEquivalent:@""];
    [copy setTarget:self];
    NSMenuItem *logs = [menu addItemWithTitle:@"Open Recent Logs"
                                       action:@selector(openRecentLogs:) keyEquivalent:@""];
    [logs setTarget:self];
    NSMenuItem *verbose = [menu addItemWithTitle:@"Verbose Logging This Session"
                                          action:@selector(toggleVerboseLogging:) keyEquivalent:@""];
    [verbose setTarget:self];
    [verbose setState:logLevel >= LOG_LEVEL_DEBUG
        ? NSControlStateValueOn : NSControlStateValueOff];
    BOOL showTrace = internalTraceDiagnosticsEnabled() || MGTraceIsActive() ||
        traceSession != nil;
    if (!showTrace) return;
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *testing = [menu addItemWithTitle:@"Gesture testing"
                                           action:nil keyEquivalent:@""];
    NSMenu *testingMenu = [[[NSMenu alloc] initWithTitle:@"Gesture testing"] autorelease];
    [self populateGestureTestingMenu:testingMenu];
    [testing setSubmenu:testingMenu];
}

- (void)populateGestureTestingMenu:(NSMenu *)menu {
    [menu removeAllItems];
    if (!MGTraceIsActive() && traceSession == nil) {
        NSMenuItem *tap = [menu addItemWithTitle:@"Start Tap Calibration…"
                                            action:@selector(startTraceSession:) keyEquivalent:@""];
        [tap setTarget:self]; [tap setTag:1];
        NSMenuItem *ambient = [menu addItemWithTitle:@"Capture Normal Mouse Use…"
                                                action:@selector(startTraceSession:) keyEquivalent:@""];
        [ambient setTarget:self]; [ambient setTag:2];
        NSMenuItem *catalog = [menu addItemWithTitle:@"Audit Gesture Catalog…"
                                                action:@selector(startTraceSession:) keyEquivalent:@""];
        [catalog setTarget:self]; [catalog setTag:3];
        NSMenuItem *candidate = [menu addItemWithTitle:@"Record Candidate Gesture…"
                                                action:@selector(startTraceSession:) keyEquivalent:@""];
        [candidate setTarget:self]; [candidate setTag:4];
        NSMenuItem *start = [menu addItemWithTitle:@"Start Physical Click Trace…"
                                            action:@selector(startTraceSession:) keyEquivalent:@""];
        [start setTarget:self];
    } else {
        NSMenuItem *show = [menu addItemWithTitle:MGTraceIsActive()
            ? @"Show Trace Session" : @"Show Completed Trace"
            action:@selector(showTraceWindow:) keyEquivalent:@""];
        [show setTarget:self];
        if (!MGTraceIsActive()) return;
        NSDictionary *status = MGTraceStatus();
        BOOL capturing = [[status objectForKey:@"capturing"] boolValue];
        BOOL awaitingLabel = [[status objectForKey:@"awaiting_label"] boolValue];
        NSString *phase = capturing ? @"capturing" : awaitingLabel ? @"ready to label" : @"resetting";
        NSMenuItem *state = [menu addItemWithTitle:[NSString stringWithFormat:
            @"Step %ld of %lu · %@ · %@ · %@ bytes · %@ dropped",
            (long)traceProtocolIndex + 1, (unsigned long)[[traceSession steps] count],
            [status objectForKey:@"step"], phase, [status objectForKey:@"bytes"],
            [status objectForKey:@"dropped"]] action:NULL keyEquivalent:@""];
        [state setEnabled:NO];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *tone = [menu addItemWithTitle:@"Gesture Dispatch Tone"
                                       action:@selector(toggleGestureDispatchTone:)
                                keyEquivalent:@""];
    [tone setTarget:self];
    [tone setState:internalGestureDispatchToneEnabled()
        ? NSControlStateValueOn : NSControlStateValueOff];
}

- (void)showTraceWindow:(id)sender {
    [tracePanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)refreshDiagnosticsSubmenu {
    NSMenuItem *parent = [theMenu itemWithTag:kMenuTagDiagnostics];
    if (parent == nil)
        return;
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Diagnostics"] autorelease];
    [menu setDelegate:self];
    [self populateDiagnosticsMenu:menu];
    [parent setSubmenu:menu];
}

// Starts the selected coding agent in the settings folder with the running app
// path, which distinguishes a source build from a copied release app.
- (void)manageWithAgent:(id)sender {
    NSString *agentPath = [sender representedObject];
    if (agentPath == nil)
        return;

    NSString *dir = [Config configDirectory];
    NSError *error = [self seedConfigDirectory];
    if (error != nil) {
        [self reportFailure:@"Can't set up the Trickpad settings folder."
                     detail:[error localizedDescription]];
        return;
    }

    NSString *appPath = [[NSBundle mainBundle] bundlePath] ?: @"unknown";
    NSString *prompt = [NSString stringWithFormat:
        @"Read AGENTS.md in this folder first. Help me manage Trickpad. "
        @"Ask what I want to do before changing settings or the application. "
        @"The running app is at %@.", appPath];
    NSString *scriptPath = [dir stringByAppendingPathComponent:@"manage-with-agent.command"];
    NSString *script = [NSString stringWithFormat:
        @"#!/bin/zsh\ncd %@\nexec %@ %@\n",
        shellQuote(dir), shellQuote(agentPath), shellQuote(prompt)];

    if (![script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:&error] ||
        ![[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0755)}
                                          ofItemAtPath:scriptPath
                                                 error:&error]) {
        [self reportFailure:@"Can't start the coding agent." detail:[error localizedDescription]];
        return;
    }

    if (![[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:scriptPath]])
        [self reportFailure:@"Can't start the coding agent."
                     detail:[NSString stringWithFormat:@"Nothing opened %@.", scriptPath]];
}

// Copies a privacy-conscious prompt for a general chat assistant that cannot
// edit the local configuration directly.
static NSString *agentPromptWithSettings(BOOL includeSettings) {
    NSString *intro =
        @"I use Trickpad, a macOS app configured through one plain-text file. "
        @"Help me create a ready-to-paste configuration block. Read the syntax and "
        @"available gestures, actions, and settings in the latest web documentation: "
        @"https://thirdwind.fyi/trickpad/docs.md\n\n"
        @"Ask what I want the gesture to do, which device it should use, and whether "
        @"it should be global or limited to an application. Do not invent gesture or "
        @"action names. Ask my Trickpad version if support for a setting matters, because "
        @"the documentation may describe a newer release. Return the smallest valid block, tell me where to paste it, "
        @"and remind me to choose Reload Settings. Preserve unrelated bindings.";
    // The plain prompt keeps the configuration private and tells the agent to
    // ask for lines instead. Attaching it is the user's explicit choice.
    NSString *middle =
        @" Ask for only the relevant lines if you need to inspect my existing "
        @"configuration because it may contain private URLs or script paths.";
    if (includeSettings) {
        NSString *path = [Config resolvedPath];
        NSString *config = path != nil
            ? [NSString stringWithContentsOfFile:path
                                        encoding:NSUTF8StringEncoding error:NULL]
            : nil;
        if (config != nil)
            middle = [NSString stringWithFormat:
                @"\n\nMy current config.toml:\n\n```toml\n%@\n```", config];
    }
    return [NSString stringWithFormat:@"%@%@\n\nWhat I want to configure: ",
            intro, middle];
}

- (void)copyAgentPrompt:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:agentPromptWithSettings(NO)
                  forType:NSPasteboardTypeString];
}

- (void)copyAgentPromptWithSettings:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:agentPromptWithSettings(YES)
                  forType:NSPasteboardTypeString];
}

// Creates the user-owned configuration once and atomically refreshes the
// app-managed agent instructions from the running version.
- (NSError *)seedConfigDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [Config configDirectory];
    NSError *error = nil;
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error])
        return error;

    NSString *root = [self projectRoot];
    NSString *(^source)(NSString *) = ^(NSString *name) {
        // A source checkout owns the freshest copy even before the app is
        // rebuilt. A copied release app has no matching project-root file and
        // uses the resource carried in its bundle.
        NSString *checkoutSource = root != nil ? [root stringByAppendingPathComponent:name] : nil;
        if (checkoutSource != nil && [fm fileExistsAtPath:checkoutSource])
            return checkoutSource;
        return [[NSBundle mainBundle] pathForResource:[name stringByDeletingPathExtension]
                                               ofType:[name pathExtension]];
    };

    NSString *configPath = [dir stringByAppendingPathComponent:@"config.toml"];
    if (![fm fileExistsAtPath:configPath]) {
        NSString *configSource = source(@"config.default.toml");
        if (configSource != nil && [fm fileExistsAtPath:configSource] &&
            ![fm copyItemAtPath:configSource toPath:configPath error:&error])
            return error;
    }

    NSString *agentSource = source(@"config-notes.default.md");
    if (agentSource != nil && [fm fileExistsAtPath:agentSource]) {
        NSData *instructions = [NSData dataWithContentsOfFile:agentSource];
        NSString *agentPath = [dir stringByAppendingPathComponent:@"AGENTS.md"];
        if (instructions == nil ||
            ![instructions writeToFile:agentPath options:NSDataWritingAtomic error:&error])
            return error ?: [NSError errorWithDomain:@"Trickpad"
                                                 code:1
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 @"The installed AGENTS.md could not be refreshed."}];
    }
    return nil;
}

- (NSMenu *)buildAgentSubmenu {
    NSMenu *sub = [[[NSMenu alloc] initWithTitle:@"Manage with Agent"] autorelease];
    // The delegate fills this submenu from the probe cache when it opens, so
    // opening costs no login-shell spawns.
    [sub setDelegate:self];
    return sub;
}

// Installed agents, probed once per top-level menu open in the background
// rather than while the submenu opens: each candidate needs the user's login
// shell, and six synchronous shell launches made the submenu visibly late.
// Entries are name-path pairs; nil means no probe has finished yet.
static NSArray *cachedAgentEntries = nil;

static NSArray *agentCandidates(void) {
    return @[@[@"Claude Code", @"claude"],
             @[@"Codex", @"codex"],
             @[@"Cursor", @"cursor-agent"],
             @[@"Gemini", @"gemini"],
             @[@"opencode", @"opencode"],
             @[@"Aider", @"aider"]];
}

- (void)refreshAgentToolCache {
    // One login shell resolves every candidate, replacing a spawn per tool.
    NSMutableArray *names = [NSMutableArray array];
    for (NSArray *pair in agentCandidates())
        [names addObject:pair[1]];
    NSString *script = [NSString stringWithFormat:
        @"for t in %@; do p=$(command -v \"$t\" 2>/dev/null) && "
        @"[ -n \"$p\" ] && printf '%%s=%%s\\n' \"$t\" \"$p\"; done; true",
        [names componentsJoinedByString:@" "]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:loginShellPath()];
        [task setArguments:@[@"-lc", script]];
        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];
        [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
        NSMutableDictionary *paths = [NSMutableDictionary dictionary];
        @try {
            [task launch];
            NSData *out = [[pipe fileHandleForReading] readDataToEndOfFile];
            [task waitUntilExit];
            NSString *text = [[[NSString alloc] initWithData:out
                encoding:NSUTF8StringEncoding] autorelease];
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                NSRange eq = [line rangeOfString:@"="];
                if (eq.location == NSNotFound || eq.location == 0)
                    continue;
                [paths setObject:[line substringFromIndex:eq.location + 1]
                          forKey:[line substringToIndex:eq.location]];
            }
        } @catch (NSException *e) {
            [paths removeAllObjects];
        }
        [task release];
        NSMutableArray *entries = [NSMutableArray array];
        for (NSArray *pair in agentCandidates()) {
            NSString *path = [paths objectForKey:pair[1]];
            if ([path length] > 0)
                [entries addObject:@[pair[0], path]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [cachedAgentEntries release];
            cachedAgentEntries = [entries copy];
        });
    });
}

- (void)menuWillOpen:(NSMenu *)menu {
    // Refreshing when the top-level menu opens keeps newly installed tools
    // appearing without ever probing on the submenu-open path: the probe
    // finishes in the background long before a hand reaches the submenu.
    if (menu == theMenu)
        [self refreshAgentToolCache];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSMenuItem *agents = [theMenu itemWithTag:kMenuTagAgents];
    NSMenuItem *diagnostics = [theMenu itemWithTag:kMenuTagDiagnostics];
    if (menu == [diagnostics submenu]) {
        [self populateDiagnosticsMenu:menu];
        return;
    }
    if (menu != [agents submenu])
        return;

    [menu removeAllItems];

    BOOL any = NO;
    for (NSArray *pair in cachedAgentEntries) {
        any = YES;
        NSMenuItem *item = [menu addItemWithTitle:pair[0]
                                           action:@selector(manageWithAgent:)
                                    keyEquivalent:@""];
        [item setRepresentedObject:pair[1]];
        [item setTarget:self];
        [item setToolTip:pair[1]];
    }

    if (any) [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *copyPrompt = [menu addItemWithTitle:@"Copy Prompt"
                                             action:@selector(copyAgentPrompt:)
                                      keyEquivalent:@"c"];
    [copyPrompt setTarget:self];
    NSMenuItem *copyPromptSettings = [menu addItemWithTitle:@"Copy Prompt + Settings"
                                                     action:@selector(copyAgentPromptWithSettings:)
                                              keyEquivalent:@"c"];
    [copyPromptSettings setKeyEquivalentModifierMask:
        NSEventModifierFlagCommand | NSEventModifierFlagOption];
    [copyPromptSettings setTarget:self];

    if (!any && cachedAgentEntries == nil) {
        NSMenuItem *pending = [menu addItemWithTitle:@"Looking for installed agents…"
                                              action:NULL keyEquivalent:@""];
        [pending setEnabled:NO];
    } else if (!any) {
        NSMenuItem *empty = [menu addItemWithTitle:@"No coding agent installed" action:NULL keyEquivalent:@""];
        [empty setEnabled:NO];

        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *hint = [menu addItemWithTitle:@"Edit Settings..." action:@selector(preferences:) keyEquivalent:@""];
        [hint setTarget:self];

        NSMenuItem *docs = [menu addItemWithTitle:@"Read the Setup Guide" action:@selector(about:) keyEquivalent:@""];
        [docs setTarget:self];
    }
}

// The one heading style for inert label rows in these menus: the system menu
// section header, with a small bold faded row standing in before macOS 14.
static NSMenuItem *MGMenuSectionHeader(NSString *title) {
    if (@available(macOS 14.0, *))
        return [NSMenuItem sectionHeaderWithTitle:title];
    NSMenuItem *header = [[[NSMenuItem alloc] initWithTitle:title
                                                     action:NULL
                                              keyEquivalent:@""] autorelease];
    [header setEnabled:NO];
    [header setAttributedTitle:[[[NSAttributedString alloc]
        initWithString:title
            attributes:@{
                NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            }] autorelease]];
    return header;
}

- (void)showIcon {
    // The menu outlives this method and is read back by tag on every refresh,
    // so it is owned here rather than left to the status item.
    theMenu = [[NSMenu alloc] initWithTitle:@"Trickpad"];
    [theMenu setDelegate:self];

    NSMenuItem *item = [theMenu addItemWithTitle:@"Turn Trickpad Off" action:@selector(switchChange:) keyEquivalent:@""];
    [item setTag:kMenuTagToggle];

    item = [theMenu addItemWithTitle:@"Accessibility" action:NULL keyEquivalent:@""];
    [item setTag:kMenuTagAccessibility];
    [item setTarget:self];

    item = [theMenu addItemWithTitle:@"Gesture conflicts" action:@selector(showConfigConflicts:) keyEquivalent:@""];
    [item setTag:kMenuTagConflicts];
    [item setTarget:self];

    [theMenu addItem:[NSMenuItem separatorItem]];

    item = [theMenu addItemWithTitle:@"Current Gestures" action:NULL keyEquivalent:@""];
    [item setTag:kMenuTagBindings];

    [theMenu addItem:[NSMenuItem separatorItem]];

    item = [theMenu addItemWithTitle:@"Manage with Agent" action:NULL keyEquivalent:@""];
    [item setTag:kMenuTagAgents];
    [item setSubmenu:[self buildAgentSubmenu]];

    // No row icons: they sit unevenly beside the Open at Login checkmark.
    // Key equivalents fire while the menu is open.
    [theMenu addItemWithTitle:@"Edit Settings..."
                       action:@selector(preferences:)
                keyEquivalent:@","];
    [theMenu addItemWithTitle:@"Reload Settings"
                       action:@selector(reloadConfiguration:)
                keyEquivalent:@"r"];

    [theMenu addItem:[NSMenuItem separatorItem]];

    // Open at Login sits with the app-lifecycle rows rather than the
    // configuration actions above, keeping its checkmark out of that group.
    item = [theMenu addItemWithTitle:@"Open at Login" action:@selector(toggleLoginItem:) keyEquivalent:@""];
    [item setTag:kMenuTagLoginItem];

    item = [theMenu addItemWithTitle:@"Diagnostics" action:NULL keyEquivalent:@""];
    [item setTag:kMenuTagDiagnostics];

    NSMenu *aboutMenu = [[[NSMenu alloc] initWithTitle:@"About Trickpad"] autorelease];
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    // An unreleased build reports the last shipped version number, so the
    // build stamp names the commit it actually came from.
    NSString *stamp = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"TrickpadBuildStamp"];
    NSString *versionTitle = stamp != nil
        ? [NSString stringWithFormat:@"Version %@ (%@)", version ?: @"unknown", stamp]
        : [NSString stringWithFormat:@"Version %@", version ?: @"unknown"];
    NSMenuItem *versionItem = MGMenuSectionHeader(versionTitle);
    [aboutMenu addItem:versionItem];
    [versionItem setEnabled:NO];
    // No ellipsis on rows that only open a page: the mark means the command
    // needs further input before it completes, not that it leaves the app.
    NSMenuItem *docsItem = [aboutMenu addItemWithTitle:@"Open Docs"
                                                action:@selector(openDocs:)
                                         keyEquivalent:@""];
    [docsItem setTarget:self];
    // The in-app check replaces the download page rather than sitting beside
    // it. Two routes to the same outcome invite the question of which to use,
    // and this one needs no manual download or drag to Applications. The page
    // stays reachable from the docs, and from the updater's own failure alert.
    if (MGUpdaterIsAvailable()) {
        // The ellipsis is earned here: choosing whether to install is the
        // further input the mark stands for.
        NSMenuItem *updateItem = [aboutMenu addItemWithTitle:@"Check for Updates…"
                                                      action:@selector(checkForUpdates:)
                                               keyEquivalent:@""];
        [updateItem setTarget:self];
        NSMenuItem *automaticItem = [aboutMenu addItemWithTitle:@"Install Updates Automatically"
                                                         action:@selector(toggleAutomaticUpdates:)
                                                  keyEquivalent:@""];
        [automaticItem setTarget:self];
        [automaticItem setState:MGUpdaterUpdatesAutomatically() ? NSOnState : NSOffState];
    } else {
        NSMenuItem *downloadItem = [aboutMenu addItemWithTitle:@"Get Latest Version"
                                                        action:@selector(getLatestVersion:)
                                                 keyEquivalent:@""];
        [downloadItem setTarget:self];
    }
    NSMenuItem *websiteItem = [aboutMenu addItemWithTitle:@"Website" action:@selector(about:) keyEquivalent:@""];
    [websiteItem setTarget:self];

    NSMenuItem *aboutItem = [theMenu addItemWithTitle:@"About Trickpad" action:NULL keyEquivalent:@""];
    [aboutItem setSubmenu:aboutMenu];
    [theMenu addItemWithTitle:@"Quit Trickpad" action:@selector(quit:) keyEquivalent:@"q"];

    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    theItem = [bar statusItemWithLength:NSVariableStatusItemLength];
    [theItem retain];
    // Persists where the user command-drags the icon. Without this, macOS
    // reassigns a position each launch and a deliberate placement is lost.
    [theItem setAutosaveName:@"TrickpadStatusItem"];
    [theItem setMenu:theMenu];
    [self updateIconImage];
    [self refreshAccessibilityItem];
    [self refreshBindingsSubmenu];
    [self refreshDiagnosticsSubmenu];
}

- (void)hideIcon {
    [[NSStatusBar systemStatusBar] removeStatusItem:theItem];
    [theItem release];
    theItem = nil;
    [theMenu release];
    theMenu = nil;
}

// The bundled mark is the default. Suspension dims the selected image without
// changing its shape, so every icon choice uses the same state treatment.
- (void)updateIconImage {
    NSString *choice = [[settings objectForKey:@"MenuBarIcon"] lowercaseString] ?: @"trickpad";
    NSImage *img = nil;
    if ([choice isEqualToString:@"trickpad"]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Trickpad-menu-bar-icon" ofType:@"svg"];
        img = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
        [img setSize:NSMakeSize(18, 18)];
    } else {
        NSString *symbol = [choice substringFromIndex:3];
        img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"Trickpad"];
    }
    if (img == nil)
        img = [NSImage imageWithSystemSymbolName:@"hand.tap.fill" accessibilityDescription:@"Trickpad"];
    [img setTemplate:YES];
    [[theItem button] setAlphaValue:enAll ? 1.0 : 0.45];
    // NSStatusItem image methods have been deprecated since macOS 10.14, so the
    // image is set on its button.
    [[theItem button] setImage:img];
}

- (void)preferences:(id)sender  {
    NSError *error = [self seedConfigDirectory];
    if (error != nil) {
        [self reportFailure:@"Can't set up the Trickpad settings folder."
                     detail:[error localizedDescription]];
        return;
    }

    NSString *path = [Config resolvedPath];
    if (path == nil) {
        [self reportFailure:@"Can't find the Trickpad configuration."
                     detail:[NSString stringWithFormat:@"Expected it at %@/config.toml.", [Config configDirectory]]];
        return;
    }

    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    if ([workspace openURL:[NSURL fileURLWithPath:path]])
        return;

    // Launch Services may not have an association for .toml on a fresh or
    // customized system. TextEdit is part of macOS and can edit plain text.
    NSURL *textEditURL = [workspace URLForApplicationWithBundleIdentifier:@"com.apple.TextEdit"];
    if (textEditURL != nil) {
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        [workspace openURLs:@[fileURL]
 withApplicationAtURL:textEditURL
           configuration:[NSWorkspaceOpenConfiguration configuration]
       completionHandler:nil];
        return;
    }

    [self reportFailure:@"Can't open the Trickpad configuration." detail:path];
}

- (void)quit:(id)sender {
    if (![self isLoginItemInstalled]) {
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Quit Trickpad?"];
        [alert setInformativeText:@"Gestures stop until you start it again. Open at Login is off, so it will not come back by itself.\n\nStart it again by reopening Trickpad."];
        [alert setAlertStyle:NSAlertStyleInformational];
        [alert addButtonWithTitle:@"Quit"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([bundlePath length] > 0)
            [alert addButtonWithTitle:@"Show Me the App"];

        [NSApp activateIgnoringOtherApps:YES];
        NSModalResponse response = [alert runModal];

        if (response == NSAlertSecondButtonReturn)
            return;
        if (response == NSAlertThirdButtonReturn && [bundlePath length] > 0) {
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:
                @[[NSURL fileURLWithPath:bundlePath]]];
            return;
        }
    }

    [self unloadJitouchLaunchAgent];
    [NSApp terminate:sender];
}

- (void)refreshMenu {
    if (theItem == nil && [[settings objectForKey:@"ShowIcon"] intValue] == 1){
        [self showIcon];
    } else if (theItem != nil && [[settings objectForKey:@"ShowIcon"] intValue] == 0){
        [self hideIcon];
    }
    if (theItem) {
        NSMenuItem *toggle = [theMenu itemWithTag:kMenuTagToggle];
        [toggle setTitle:enAll ? @"Turn Trickpad Off" : @"Turn Trickpad On"];

        NSMenuItem *login = [theMenu itemWithTag:kMenuTagLoginItem];
        [login setState:[self isLoginItemInstalled] ? NSControlStateValueOn : NSControlStateValueOff];

        [self refreshAccessibilityItem];
        [self refreshProblemsItem];
        [self refreshConflictsItem];
        [self refreshBindingsSubmenu];
        [self refreshDiagnosticsSubmenu];
        [self updateIconImage];
    }
}

// The configuration file has no field for this switch and every load turns
// gestures back on, so the switch lasts until the settings are reloaded or the
// app restarts.
- (void)switchChange:(id)sender {
    enAll = !enAll;
    [self refreshMenu];

    if (!enAll)
        turnOffGestures();
}

#pragma mark - Settings

- (void)settingsUpdated:(NSNotification *)aNotification {
    //[Settings loadSettings];

    [Settings loadSettings2:aNotification.userInfo]; // fixes bug in mountain lion
    [self refreshMenu];

    if (!enAll)
        turnOffGestures();
}

#pragma mark - Initialization


// A menu bar app with no window gives a first-time user nothing that says
// where the app lives, so the first launch opens the app's own menu once:
// it points at its location instead of describing it. The wait exists
// because launch also raises the Accessibility permission dialog, and a
// menu popping over that dialog reaches the user at the moment they are
// least oriented. An icon pushed into notch overflow may keep the menu
// invisible; this handles the common case, not that one.
static NSString * const kFirstLaunchMenuShownKey = @"FirstLaunchMenuShown";

- (void)openFirstLaunchMenuWhenSettled {
    static int pollCount = 0;
    // Accessibility is usually granted within the first minute of a real
    // install. Waiting much longer risks the menu opening over unrelated
    // work, and the menu is worth showing even ungranted, since its own
    // Accessibility row is the way to finish that step.
    if (!AXIsProcessTrusted() && ++pollCount < 45) {
        [self performSelector:@selector(openFirstLaunchMenuWhenSettled)
                   withObject:nil afterDelay:2.0];
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:YES
                                            forKey:kFirstLaunchMenuShownKey];
    if (theItem != nil)
        [[theItem button] performClick:nil];
}

- (void)checkAXAPI {
    AXIsProcessTrustedWithOptions((CFDictionaryRef)@{(id)kAXTrustedCheckOptionPrompt: @(YES)});
}

/*
void languageChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    for (int i = 0; i < 128; i++)
        keyMap[i] = (CGKeyCode)i;
    NSString *inputSource = (NSString*)TISGetInputSourceProperty(TISCopyCurrentKeyboardInputSource(), kTISPropertyLocalizedName);
    if ([inputSource isEqualToString:@"Dvorak"] || [inputSource isEqualToString:@"Svorak"]) {
        keyMap[13] = 43; //w -> ,
        keyMap[12] = 7;  //q -> x
        keyMap[17] = 40; //t -> k
        keyMap[4] = 38;  //h -> j
        keyMap[15] = 31; //r -> o
        keyMap[45] = 37; //n -> l
        keyMap[8] = 34; //c -> i
        keyMap[9] = 47; //v -> >
        keyMap[31] = 1; //o ->
        keyMap[37] = 45; //l -> n
        keyMap[3] = 32; // f -> u
        keyMap[40] = 17;
    } else if ([inputSource isEqualToString:@"French"]) {
        keyMap[13] = 6;  //w -> z
        keyMap[12] = 0;  //q -> a
    }
}
*/

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Captured before seeding creates the file: an existing configuration
    // means an existing user, so an upgrade never replays the first-launch
    // welcome even though older versions never wrote its preference.
    BOOL configExistedBeforeSeeding = [Config resolvedPath] != nil;

    // A packaged install has no start.sh or install script to seed the settings
    // folder, so the app seeds it here before resolving the configuration.
    NSError *seedError = [self seedConfigDirectory];
    if (seedError != nil)
        [self reportFailure:@"Can't create the settings folder."
                     detail:[NSString stringWithFormat:@"%@\n\nGestures run with built-in defaults until %@/config.toml exists.",
                             [seedError localizedDescription], [Config configDirectory]]];

    [self enableLoginItemOnFirstLaunch];

    NSString *configPath = [Config resolvedPath];
    if (configPath != nil) {
        NSArray *problems = nil;
        NSDictionary *parsed = [Config settingsFromFile:configPath problems:&problems];
        [self setConfigProblems:problems];
        if (parsed != nil) {
            lastConfigRejected = NO;
            [self adoptConfiguration:parsed];
            [Settings loadSettings2:parsed];
        } else if ([problems count] > 0) {
            lastConfigRejected = YES;
            [self adoptConfiguration:nil];
            [self reportFailure:@"Could not apply the configuration."
                         detail:[[problems componentsJoinedByString:@"\n\n"]
                                 stringByAppendingString:@"\n\nNo gestures were loaded."]];
        }
    } else {
        lastConfigRejected = NO;
        [Settings loadSettings];
    }

    [self refreshMenu];

    // Move this task to prefpane instead. Starting at Sierra
    //[self addJitouchToLoginItems];

    // The legacy cursor overlay touches AppKit from gesture callback threads on
    // recent macOS releases and can crash the process. Disable it in the agent.
    cursorWindow = nil;

    //languageChanged(NULL, NULL, NULL, NULL, NULL);

    gesture = [[Gesture alloc] init];

    //[self showIcon];

    [self startWatchingConfig];

    [self refreshAgentToolCache];

    [self checkAXAPI];

    if (!configExistedBeforeSeeding &&
        ![[NSUserDefaults standardUserDefaults] boolForKey:kFirstLaunchMenuShownKey])
        [self performSelector:@selector(openFirstLaunchMenuWhenSettled)
                   withObject:nil afterDelay:2.0];

    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(settingsUpdated:)
                                                            name: @"My Notification"
                                                          object: @"fyi.thirdwind.trickpad.PrefpaneTarget"];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(wokeUp:) name:NSWorkspaceDidWakeNotification object: NULL];

    // An application-scoped binding must take effect the moment its
    // application comes forward, so activation drops the cached candidates.
    MGApplicationScopeCacheObserveApplicationActivation();

    //CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(), self, languageChanged, kTISNotifySelectedKeyboardInputSourceChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)wokeUp:(NSNotification *)aNotification {
    NSLog(@"Woke up.");
    [self reload];
}

- (void)reload {
    [gesture reload];
}

#pragma mark -

- (void) dealloc {
    [cursorWindow release];
    [gesture release];
    [theItem release];
    [theMenu release];
    [super dealloc];
}

@end
