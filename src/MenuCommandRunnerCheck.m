// Checks menu-step results against synthetic menu bars: path and title
// matching, enabled and pressable leaves, bounds, cancellation, and the
// target checks that must pass immediately before a press.

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import "MenuCommandRunner.h"

static int failures = 0;

static void require(BOOL condition, const char *message) {
    if (condition)
        return;
    fprintf(stderr, "FAIL  %s\n", message);
    failures++;
}

// A menu item; enabled and pressable unless stated.
static NSDictionary *item(NSString *title) {
    return @{ @"title": title, @"role": (NSString *)kAXMenuItemRole };
}

static NSDictionary *disabled(NSString *title) {
    return @{ @"title": title, @"role": (NSString *)kAXMenuItemRole, @"enabled": @NO };
}

// An item that opens a submenu of the given items. Such items advertise
// AXPress in real applications, so only the child menu distinguishes them.
static NSDictionary *submenu(NSString *title, NSArray *items) {
    return @{ @"title": title, @"role": (NSString *)kAXMenuItemRole,
              @"children": @[@{ @"role": (NSString *)kAXMenuRole, @"children": items }] };
}

static NSDictionary *menuBar(NSArray *roots) {
    return @{ @"role": (NSString *)kAXMenuBarRole, @"children": roots };
}

@interface FakeMenuEnvironment : NSObject <MGMenuEnvironment>
@property (nonatomic, retain) NSDictionary *bar;
@property (nonatomic) pid_t frontmost;
@property (nonatomic) BOOL trusted;
@property (nonatomic) BOOL running;
@property (nonatomic) BOOL pressAccepted;
@property (nonatomic) NSTimeInterval clock;
@property (nonatomic) NSTimeInterval secondsPerChildrenRead;
// When set, the target becomes frontmost once the wait begins.
@property (nonatomic) BOOL activatesOnWait;
// Changes the frontmost process once this many frontmost reads have happened.
@property (nonatomic) NSInteger frontmostReadsBeforeSwitch;
@property (nonatomic) NSInteger frontmostReads;
@property (nonatomic) BOOL cancelDuringTraversal;
@property (nonatomic, retain) NSDictionary *pressed;
@end

@implementation FakeMenuEnvironment
- (instancetype)init {
    self = [super init];
    _trusted = YES;
    _running = YES;
    _pressAccepted = YES;
    _frontmost = 42;
    _frontmostReadsBeforeSwitch = -1;
    return self;
}
- (void)dealloc {
    [_bar release];
    [_pressed release];
    [super dealloc];
}
- (BOOL)accessibilityTrusted { return _trusted; }
- (BOOL)processIsRunning:(pid_t)pid { return _running; }
- (pid_t)frontmostProcess {
    _frontmostReads++;
    if (_frontmostReadsBeforeSwitch >= 0 && _frontmostReads > _frontmostReadsBeforeSwitch)
        _frontmost = 7;
    return _frontmost;
}
- (BOOL)waitForFrontmostProcess:(pid_t)pid until:(NSTimeInterval)deadline {
    if (_activatesOnWait)
        _frontmost = pid;
    else
        _clock = deadline + 0.001;
    return _frontmost == pid;
}
- (NSTimeInterval)now { return _clock; }
- (id)menuBarForProcess:(pid_t)pid { return _bar; }
- (NSArray *)childrenOfElement:(id)element {
    _clock += _secondsPerChildrenRead;
    if (_cancelDuringTraversal)
        MGCancelRunningMenuSteps();
    return [element objectForKey:@"children"] ?: @[];
}
- (NSString *)titleOfElement:(id)element { return [element objectForKey:@"title"]; }
- (NSString *)roleOfElement:(id)element { return [element objectForKey:@"role"]; }
- (NSNumber *)enabledStateOfElement:(id)element {
    if ([element objectForKey:@"unreadable"] != nil)
        return nil;
    return [element objectForKey:@"enabled"] ?: @YES;
}
- (BOOL)elementSupportsPress:(id)element {
    return [element objectForKey:@"press"] == nil || [[element objectForKey:@"press"] boolValue];
}
- (BOOL)pressElement:(id)element {
    self.pressed = element;
    return _pressAccepted;
}
@end

static FakeMenuEnvironment *environmentWithBar(NSDictionary *bar) {
    FakeMenuEnvironment *environment = [[[FakeMenuEnvironment alloc] init] autorelease];
    environment.bar = bar;
    return environment;
}

static MGMenuOutcome run(FakeMenuEnvironment *environment, NSArray *components) {
    return MGRunMenuStep(components, 42, environment);
}

int main(void) {
    @autoreleasepool {
        NSDictionary *save = item(@"Save");
        NSDictionary *clear = item(@"Clear Menu");
        NSDictionary *settings = item(@"Settings…");
        NSDictionary *bar = menuBar(@[
            submenu(@"App", @[settings, item(@"Quit")]),
            submenu(@"File", @[item(@"New"), submenu(@"Open Recent", @[item(@"a.txt"), clear]),
                               save, disabled(@"Revert"), item(@"Duplicate"), item(@"Duplicate")]),
            submenu(@"Edit", @[submenu(@"Find", @[item(@"Find…"), item(@"Find Next")]),
                               item(@"Save"), @{ @"title": @"Odd", @"role": (NSString *)kAXMenuItemRole,
                                                 @"unreadable": @YES }]),
        ]);

        FakeMenuEnvironment *environment = environmentWithBar(bar);
        MGMenuOutcome outcome = run(environment, @[@"File", @"Save"]);
        require(outcome.result == MGMenuResultPressed && environment.pressed == save,
                "an exact path presses its leaf");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"File", @"Open Recent", @"Clear Menu"]);
        require(outcome.result == MGMenuResultPressed && environment.pressed == clear,
                "a path descends into a submenu without opening it");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"App", @"Settings..."]);
        require(outcome.result == MGMenuResultPressed && environment.pressed == settings,
                "three periods match a menu ellipsis");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"File", @"Close"]);
        require(outcome.result == MGMenuResultComponentMissing && outcome.component == 2 &&
                environment.pressed == nil, "a missing leaf names its component");

        outcome = run(environmentWithBar(bar), @[@"Window", @"Minimize"]);
        require(outcome.result == MGMenuResultComponentMissing && outcome.component == 1,
                "a missing root names the first component");

        outcome = run(environmentWithBar(bar), @[@"File", @"save"]);
        require(outcome.result == MGMenuResultComponentMissing, "path matching is case-sensitive");

        outcome = run(environmentWithBar(bar), @[@"File", @"Duplicate"]);
        require(outcome.result == MGMenuResultComponentAmbiguous && outcome.component == 2,
                "duplicate siblings are ambiguous in a path");

        outcome = run(environmentWithBar(bar), @[@"File", @"Save", @"More"]);
        require(outcome.result == MGMenuResultComponentMissing && outcome.component == 3,
                "a path through an item without a submenu misses the next component");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"File", @"Open Recent"]);
        require(outcome.result == MGMenuResultLeafNotActionable && environment.pressed == nil,
                "a submenu named as the leaf is not pressed");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"File", @"Revert"]);
        require(outcome.result == MGMenuResultLeafDisabled && environment.pressed == nil,
                "a disabled leaf is not pressed");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"Edit", @"Odd"]);
        require(outcome.result == MGMenuResultLeafDisabled && environment.pressed == nil,
                "an unreadable enabled state is not pressed");

        // Single titles.
        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"Save"]);
        require(outcome.result == MGMenuResultPressed && environment.pressed == save,
                "a title presses the first match in menu order");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"Clear Menu"]);
        require(outcome.result == MGMenuResultPressed && environment.pressed == clear,
                "a title search descends into submenus");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"Find…"]);
        require(outcome.result == MGMenuResultPressed &&
                [[environment.pressed objectForKey:@"title"] isEqualToString:@"Find…"],
                "a title search reaches an item inside a same-named submenu");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"Open Recent"]);
        require(outcome.result == MGMenuResultComponentMissing && environment.pressed == nil,
                "a title search never presses a submenu");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"Duplicate"]);
        require(outcome.result == MGMenuResultPressed, "a title search takes the first duplicate");

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"Revert"]);
        require(outcome.result == MGMenuResultLeafDisabled && environment.pressed == nil,
                "a title that only matches disabled items reports disabled");

        NSDictionary *laterEnabled = item(@"Export");
        environment = environmentWithBar(menuBar(@[submenu(@"File", @[disabled(@"Export")]),
                                                   submenu(@"Tools", @[laterEnabled])]));
        outcome = run(environment, @[@"Export"]);
        require(outcome.result == MGMenuResultPressed && environment.pressed == laterEnabled,
                "a title search skips a disabled match for a later enabled one");

        outcome = run(environmentWithBar(bar), @[@"Nothing"]);
        require(outcome.result == MGMenuResultComponentMissing && outcome.component == 1,
                "a title with no match is missing");

        // Target checks.
        outcome = MGRunMenuStep(@[@"File", @"Save"], 0, environmentWithBar(bar));
        require(outcome.result == MGMenuResultNoTargetApplication, "no process is no target");

        environment = environmentWithBar(bar);
        environment.trusted = NO;
        require(run(environment, @[@"File", @"Save"]).result == MGMenuResultAccessibilityDenied,
                "missing Accessibility access is reported before traversal");

        environment = environmentWithBar(bar);
        environment.running = NO;
        require(run(environment, @[@"File", @"Save"]).result == MGMenuResultTargetTerminated,
                "a terminated target is reported");

        environment = environmentWithBar(bar);
        environment.frontmost = 7;
        environment.activatesOnWait = YES;
        outcome = run(environment, @[@"File", @"Save"]);
        require(outcome.result == MGMenuResultPressed && environment.pressed == save,
                "a target that comes forward during the wait is pressed");

        environment = environmentWithBar(bar);
        environment.frontmost = 7;
        outcome = run(environment, @[@"File", @"Save"]);
        require(outcome.result == MGMenuResultTargetChanged && environment.pressed == nil,
                "a target that never comes forward is not pressed");

        environment = environmentWithBar(bar);
        environment.frontmostReadsBeforeSwitch = 1;
        outcome = run(environment, @[@"File", @"Save"]);
        require(outcome.result == MGMenuResultTargetChanged && environment.pressed == nil,
                "focus that moves during traversal stops the press");

        environment = environmentWithBar(bar);
        environment.cancelDuringTraversal = YES;
        outcome = run(environment, @[@"File", @"Save"]);
        require(outcome.result == MGMenuResultCancelled && environment.pressed == nil,
                "cancellation during traversal stops the press");
        environment = environmentWithBar(bar);
        MGCancelRunningMenuSteps();
        outcome = run(environment, @[@"File", @"Save"]);
        require(outcome.result == MGMenuResultPressed,
                "cancellation before a step starts does not affect that step");

        // Bounds.
        environment = environmentWithBar(bar);
        environment.secondsPerChildrenRead = 0.4;
        outcome = run(environment, @[@"File", @"Open Recent", @"Clear Menu"]);
        require(outcome.result == MGMenuResultDeadlineExceeded && environment.pressed == nil,
                "a traversal past the deadline is not pressed");

        environment = environmentWithBar(bar);
        environment.secondsPerChildrenRead = 0.4;
        outcome = run(environment, @[@"Clear Menu"]);
        require(outcome.result == MGMenuResultDeadlineExceeded && environment.pressed == nil,
                "a title search past the deadline is not pressed");

        NSMutableArray *many = [NSMutableArray array];
        for (int index = 0; index < 10100; index++)
            [many addObject:item([NSString stringWithFormat:@"Item %d", index])];
        environment = environmentWithBar(menuBar(@[submenu(@"Big", many)]));
        outcome = run(environment, @[@"Big", @"Item 5"]);
        require(outcome.result == MGMenuResultWorkLimitExceeded && environment.pressed == nil,
                "a menu larger than the work limit is not traversed");

        environment = environmentWithBar(bar);
        environment.pressAccepted = NO;
        outcome = run(environment, @[@"File", @"Save"]);
        require(outcome.result == MGMenuResultPressOutcomeUncertain,
                "a rejected press call is uncertain, not a pre-press failure");

        require([MGMenuResultName(MGMenuResultPressOutcomeUncertain)
                 isEqualToString:@"press-outcome-uncertain"], "result names are stable");
        require(MGMenuResultIsUnavailableItem(MGMenuResultComponentMissing) &&
                MGMenuResultIsUnavailableItem(MGMenuResultLeafDisabled) &&
                !MGMenuResultIsUnavailableItem(MGMenuResultTargetChanged) &&
                !MGMenuResultIsUnavailableItem(MGMenuResultPressed),
                "only a missing or unusable item is an unavailable item");
    }
    if (failures > 0)
        return 1;
    printf("menu command runner: ok\n");
    return 0;
}
