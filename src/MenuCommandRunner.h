// Finds and presses one menu item in a target application's menu bar through
// Accessibility, within fixed time and work bounds, and reports one result.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MGMenuResult) {
    MGMenuResultPressed,
    MGMenuResultNoTargetApplication,
    MGMenuResultAccessibilityDenied,
    MGMenuResultTargetTerminated,
    MGMenuResultTargetChanged,
    MGMenuResultComponentMissing,
    MGMenuResultComponentAmbiguous,
    MGMenuResultLeafNotActionable,
    MGMenuResultLeafDisabled,
    MGMenuResultTraversalError,
    MGMenuResultDeadlineExceeded,
    MGMenuResultWorkLimitExceeded,
    MGMenuResultCancelled,
    MGMenuResultQueueFull,
    MGMenuResultPressOutcomeUncertain,
};

typedef struct {
    MGMenuResult result;
    // The 1-based component a missing or ambiguous result refers to, else 0.
    NSUInteger component;
    NSUInteger examinedChildren;
    // Time spent waiting for the target to come forward, for logs.
    NSTimeInterval activationWaitSeconds;
    // The application's own titles, so messages can quote the menu bar as it
    // appears: the whole path when the item was located, or the menus leading
    // to a missing or ambiguous path component. Shown to the user, never logged.
    NSArray<NSString *> *applicationPath;
    // For a missing item, the application's path to its closest title within a
    // small spelling distance, or nil. Shown to the user, never logged.
    NSArray<NSString *> *suggestedPath;
} MGMenuOutcome;

extern NSString *const MGMenuDetailChildren;
extern NSString *const MGMenuDetailTitle;
extern NSString *const MGMenuDetailRole;
extern NSString *const MGMenuDetailEnabled;

extern const NSTimeInterval MGMenuStepDeadlineSeconds;
extern const NSUInteger MGMenuExaminedChildrenLimit;

// Everything the runner asks of the system. Elements are opaque objects the
// environment hands back to itself.
@protocol MGMenuEnvironment <NSObject>
- (BOOL)accessibilityTrusted;
- (BOOL)processIsRunning:(pid_t)pid;
- (pid_t)frontmostProcess;
// Returns YES once pid is frontmost, or NO when the deadline passes first.
- (BOOL)waitForFrontmostProcess:(pid_t)pid until:(NSTimeInterval)deadline;
// A monotonic clock in seconds.
- (NSTimeInterval)now;
// Each request below waits for the application to answer until deadline, the
// step's single time limit. An application that has just come forward can
// take most of a second to answer while it rebuilds its menus.
// Returns nil when the application did not answer.
- (id)menuBarForProcess:(pid_t)pid until:(NSTimeInterval)deadline;
// Reads an element's details in one request: MGMenuDetailChildren (always
// present, empty for none), and MGMenuDetailTitle, MGMenuDetailRole, and
// MGMenuDetailEnabled when readable. Returns nil when the application did not
// answer.
- (NSDictionary *)detailsOfElement:(id)element until:(NSTimeInterval)deadline;
- (BOOL)elementSupportsPress:(id)element until:(NSTimeInterval)deadline;
// Returns YES when Accessibility accepted the press. Acceptance does not show
// that the application acted.
- (BOOL)pressElement:(id)element until:(NSTimeInterval)deadline;
@end

// Runs one menu step. Two or more components name a root-to-leaf path. One
// component names a title found anywhere in the menu bar: the first enabled,
// pressable item with that title, reading menus left to right and each menu
// top to bottom, descending into submenus where they appear. Blocks until the
// step finishes; call it off the main thread.
MGMenuOutcome MGRunMenuStep(NSArray<NSString *> *components, pid_t target,
                            id<MGMenuEnvironment> environment);

// Makes every step already running stop before its press.
void MGCancelRunningMenuSteps(void);

// The stable result code used in logs.
NSString *MGMenuResultName(MGMenuResult result);

// Whether the user hears the system alert sound for the result: the target
// application lacks a usable item, or did not answer in time. Failures that
// describe Trickpad's own state stay silent and appear only in the log.
BOOL MGMenuResultPlaysAlert(MGMenuResult result);

// Whether the fix for a failed step belongs in the user's settings, so the
// feedback can offer to open them.
BOOL MGMenuFailureIsInSettings(MGMenuResult result);

// One sentence saying why a step failed, framed around the application's menu
// bar and naming the configured command. Returns nil for a press and for a
// cancellation, which follows the user's own reload.
NSString *MGMenuFailureMessage(MGMenuOutcome outcome, NSArray<NSString *> *components,
                               NSString *applicationName);

// The Accessibility and NSWorkspace environment used by the app.
id<MGMenuEnvironment> MGSystemMenuEnvironment(void);
