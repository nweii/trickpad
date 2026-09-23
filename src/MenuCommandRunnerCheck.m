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
// How long the application takes to answer its first request, as one that has
// just come forward does, and whether it ever answers.
@property (nonatomic) NSTimeInterval firstAnswerDelay;
@property (nonatomic) BOOL neverAnswers;
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
// Advances the clock by one request and reports whether it was answered.
- (BOOL)answerUntil:(NSTimeInterval)deadline {
    _clock += _firstAnswerDelay;
    _firstAnswerDelay = 0;
    if (_neverAnswers || _clock > deadline) {
        _clock = MAX(_clock, deadline + 0.001);
        return NO;
    }
    return YES;
}
- (id)menuBarForProcess:(pid_t)pid until:(NSTimeInterval)deadline {
    return [self answerUntil:deadline] ? _bar : nil;
}
- (NSDictionary *)detailsOfElement:(id)element until:(NSTimeInterval)deadline {
    _clock += _secondsPerChildrenRead;
    if (![self answerUntil:deadline])
        return nil;
    if (_cancelDuringTraversal)
        MGCancelRunningMenuSteps();
    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    [details setObject:[element objectForKey:@"children"] ?: @[] forKey:MGMenuDetailChildren];
    if ([element objectForKey:@"title"] != nil)
        [details setObject:[element objectForKey:@"title"] forKey:MGMenuDetailTitle];
    if ([element objectForKey:@"role"] != nil)
        [details setObject:[element objectForKey:@"role"] forKey:MGMenuDetailRole];
    if ([element objectForKey:@"unreadable"] == nil)
        [details setObject:[element objectForKey:@"enabled"] ?: @YES forKey:MGMenuDetailEnabled];
    return details;
}
- (BOOL)elementSupportsPress:(id)element until:(NSTimeInterval)deadline {
    return [element objectForKey:@"press"] == nil || [[element objectForKey:@"press"] boolValue];
}
- (BOOL)pressElement:(id)element until:(NSTimeInterval)deadline {
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

        environment = environmentWithBar(bar);
        outcome = run(environment, @[@"file", @"SAVE"]);
        require(outcome.result == MGMenuResultPressed && environment.pressed == save,
                "path matching ignores capitalization");

        outcome = run(environmentWithBar(menuBar(@[submenu(@"Edit", @[item(@"Copy"), item(@"copy")])])),
                      @[@"Edit", @"Copy"]);
        require(outcome.result == MGMenuResultComponentAmbiguous,
                "siblings that differ only in capitalization are ambiguous in a path");

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

        // An application that is slow to answer after coming forward is waited
        // for; one that never answers ends at the deadline unpressed.
        environment = environmentWithBar(bar);
        environment.firstAnswerDelay = 1.5;
        outcome = run(environment, @[@"Clear Menu"]);
        require(outcome.result == MGMenuResultPressed && environment.pressed == clear,
                "a slow first answer is waited for within the deadline");

        environment = environmentWithBar(bar);
        environment.neverAnswers = YES;
        outcome = run(environment, @[@"File", @"Save"]);
        require(outcome.result == MGMenuResultDeadlineExceeded && environment.pressed == nil,
                "an application that never answers ends at the deadline");

        environment = environmentWithBar(bar);
        environment.firstAnswerDelay = 2.5;
        outcome = run(environment, @[@"Save"]);
        require(outcome.result == MGMenuResultDeadlineExceeded && environment.pressed == nil,
                "an answer after the deadline is not waited for"); 

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

        // A likely misspelling names the application's closest title; a
        // distant title suggests nothing.
        outcome = run(environmentWithBar(bar), @[@"file", @"Sve"]);
        require(outcome.result == MGMenuResultComponentMissing &&
                [outcome.suggestedPath isEqual:@[@"File", @"Save"]],
                "a misspelled path component suggests the closest title with its menu");
        require([MGMenuFailureMessage(outcome, @[@"file", @"Sve"], @"Notes")
                 isEqualToString:@"Your settings say “file › Sve”, but the Notes menu bar has “File › Save”."],
                "a suggestion quotes the settings as written and the menu bar as shown");
        outcome = run(environmentWithBar(bar), @[@"Fiel", @"Save"]);
        require([outcome.suggestedPath isEqual:@[@"File"]],
                "a misspelled menu suggests the closest menu");
        require([MGMenuFailureMessage(outcome, @[@"Fiel", @"Save"], @"Notes")
                 isEqualToString:@"Your settings say “Fiel”, but the Notes menu bar has “File”."],
                "a misspelled menu quotes only the part that failed");
        outcome = run(environmentWithBar(bar), @[@"Clear Menus"]);
        require(outcome.result == MGMenuResultComponentMissing &&
                [outcome.suggestedPath isEqual:@[@"File", @"Open Recent", @"Clear Menu"]],
                "a misspelled title search suggests the closest command and where it is");
        outcome = run(environmentWithBar(bar), @[@"Xylophone"]);
        require(outcome.suggestedPath == nil, "a distant title suggests nothing");
        outcome = run(environmentWithBar(bar), @[@"file", @"revert"]);
        require(outcome.suggestedPath == nil &&
                [MGMenuFailureMessage(outcome, @[@"file", @"revert"], @"Notes")
                 isEqualToString:@"“File › Revert” is dimmed in the Notes menu bar right now."],
                "a located command is quoted as the menu bar shows it");
        outcome = run(environmentWithBar(bar), @[@"revert"]);
        require(outcome.result == MGMenuResultLeafDisabled &&
                [outcome.applicationPath isEqual:@[@"File", @"Revert"]],
                "a title search that finds only a disabled item reports where it is");
        outcome = run(environmentWithBar(bar), @[@"file", @"Close"]);
        require([MGMenuFailureMessage(outcome, @[@"file", @"Close"], @"Notes")
                 isEqualToString:@"The Notes menu bar has no “Close” under File."],
                "a missing component quotes its menus as the menu bar shows them");
        require(MGMenuFailureIsInSettings(MGMenuResultComponentMissing) &&
                !MGMenuFailureIsInSettings(MGMenuResultDeadlineExceeded) &&
                !MGMenuFailureIsInSettings(MGMenuResultLeafDisabled),
                "only failures fixed in settings offer to open them");

        // Failure messages name the configured command, the application, and
        // the part of the path that failed, and stay quiet for a press.
        MGMenuOutcome described = { MGMenuResultComponentMissing, 2, 0, 0, @[@"File"], nil };
        require([MGMenuFailureMessage(described, @[@"File", @"Save"], @"Notes")
                 isEqualToString:@"The Notes menu bar has no “Save” under File."],
                "a missing path component is named with its parent");
        described.component = 3;
        described.applicationPath = @[@"File", @"Open Recent"];
        require([MGMenuFailureMessage(described, @[@"File", @"Open Recent", @"Clear"], @"Notes")
                 isEqualToString:@"The Notes menu bar has no “Clear” under File › Open Recent."],
                "a deeper missing component names the whole parent path");
        described.component = 1;
        described.applicationPath = @[];
        require([MGMenuFailureMessage(described, @[@"Save"], @"Notes")
                 isEqualToString:@"The Notes menu bar has no command named “Save”."],
                "a missing single title is described as a command");
        require([MGMenuFailureMessage(described, @[@"Fiel", @"Save"], @"Notes")
                 isEqualToString:@"The Notes menu bar has no “Fiel” menu."],
                "a missing root is described as a menu");
        described.result = MGMenuResultLeafDisabled;
        described.component = 0;
        require([MGMenuFailureMessage(described, @[@"File", @"Save"], @"Notes")
                 isEqualToString:@"“File › Save” is dimmed in the Notes menu bar right now."],
                "a disabled command is described as dimmed");
        described.result = MGMenuResultDeadlineExceeded;
        require([MGMenuFailureMessage(described, @[@"Save"], nil)
                 hasPrefix:@"The application didn’t respond"],
                "a message without an application name still reads naturally");
        described.result = MGMenuResultPressed;
        require(MGMenuFailureMessage(described, @[@"Save"], @"Notes") == nil,
                "a press shows no message");
        described.result = MGMenuResultCancelled;
        require(MGMenuFailureMessage(described, @[@"Save"], @"Notes") == nil,
                "a cancellation shows no message");
        for (MGMenuResult result = MGMenuResultNoTargetApplication;
             result <= MGMenuResultPressOutcomeUncertain; result++) {
            described.result = result;
            described.component = 1;
            if (result != MGMenuResultCancelled &&
                [MGMenuFailureMessage(described, @[@"File", @"Save"], @"Notes") length] == 0)
                require(NO, "every failure other than cancellation has a message");
        }

        require([MGMenuResultName(MGMenuResultPressOutcomeUncertain)
                 isEqualToString:@"press-outcome-uncertain"], "result names are stable");
        require(MGMenuResultPlaysAlert(MGMenuResultComponentMissing) &&
                MGMenuResultPlaysAlert(MGMenuResultLeafDisabled) &&
                MGMenuResultPlaysAlert(MGMenuResultDeadlineExceeded) &&
                !MGMenuResultPlaysAlert(MGMenuResultTargetChanged) &&
                !MGMenuResultPlaysAlert(MGMenuResultCancelled) &&
                !MGMenuResultPlaysAlert(MGMenuResultPressed),
                "a missing, unusable, or unanswered item plays the alert and nothing else does");
    }
    if (failures > 0)
        return 1;
    printf("menu command runner: ok\n");
    return 0;
}
