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
    // Where the time went, for logs: waiting for the target to come forward,
    // and reads the application left unanswered.
    NSTimeInterval activationWaitSeconds;
    NSUInteger unansweredReads;
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
// Waits before a read is retried.
- (void)pauseBeforeRetry;
// Returns nil when the application did not answer, as while it rebuilds its
// menus on becoming active.
- (id)menuBarForProcess:(pid_t)pid;
// Reads an element's details in one request: MGMenuDetailChildren (always
// present, empty for none), and MGMenuDetailTitle, MGMenuDetailRole, and
// MGMenuDetailEnabled when readable. Returns nil when the application did not
// answer.
- (NSDictionary *)detailsOfElement:(id)element;
- (BOOL)elementSupportsPress:(id)element;
// Returns YES when Accessibility accepted the press. Acceptance does not show
// that the application acted.
- (BOOL)pressElement:(id)element;
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

// Whether the result means the target application lacks a usable item, which
// the user hears as the system alert sound.
BOOL MGMenuResultIsUnavailableItem(MGMenuResult result);

// The Accessibility and NSWorkspace environment used by the app.
id<MGMenuEnvironment> MGSystemMenuEnvironment(void);
