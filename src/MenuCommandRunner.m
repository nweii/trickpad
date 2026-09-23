// Runs one menu step against an injected environment: confirms the target is
// frontmost, finds the item without opening any menu, and presses it only
// after rechecking the target, enabled state, deadline, and cancellation.

#import "MenuCommandRunner.h"
#import "MenuPath.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <errno.h>
#import <signal.h>
#import <stdatomic.h>
#import <time.h>

NSString *const MGMenuDetailChildren = @"children";
NSString *const MGMenuDetailTitle = @"title";
NSString *const MGMenuDetailRole = @"role";
NSString *const MGMenuDetailEnabled = @"enabled";

// The only time limit in a menu step. It bounds a step when an application
// stops answering; a responsive application finishes far sooner. One that has
// just come forward was measured leaving requests unanswered for most of a
// second, after which a full title search can take several hundred
// milliseconds.
const NSTimeInterval MGMenuStepDeadlineSeconds = 2.0;
// A browser's full menu bar, with its history and bookmarks menus, measured
// 1,400 to 3,000 elements. The deadline is the bound a real application
// reaches; this limit sits above it and only stops a pathological tree.
const NSUInteger MGMenuExaminedChildrenLimit = 10000;

static _Atomic unsigned long cancellationGeneration = 0;

void MGCancelRunningMenuSteps(void) {
    atomic_fetch_add(&cancellationGeneration, 1);
}

typedef struct {
    id<MGMenuEnvironment> environment;
    NSTimeInterval deadline;
    NSUInteger examined;
    MGMenuResult failure;
    NSUInteger failureComponent;
    NSTimeInterval activationWaitSeconds;
    // The application's titles from the menu bar to the current position.
    NSMutableArray *location;
    // A title search's path to the first matching item that was disabled.
    NSArray *disabledPath;
    // The path to the closest title to a missing one, and its spelling distance.
    NSArray *suggestion;
    NSUInteger suggestionDistance;
} MGMenuTraversal;

static BOOL fail(MGMenuTraversal *traversal, MGMenuResult result, NSUInteger component) {
    traversal->failure = result;
    traversal->failureComponent = component;
    return NO;
}

static BOOL pastDeadline(MGMenuTraversal *traversal) {
    if ([traversal->environment now] <= traversal->deadline)
        return NO;
    return !fail(traversal, MGMenuResultDeadlineExceeded, 0);
}

// Reads an element's details, waiting for the application until the deadline.
static NSDictionary *readDetails(MGMenuTraversal *traversal, id element) {
    if (pastDeadline(traversal))
        return nil;
    NSDictionary *details = [traversal->environment detailsOfElement:element
                                                               until:traversal->deadline];
    if (details == nil && !pastDeadline(traversal))
        fail(traversal, MGMenuResultTraversalError, 0);
    return details;
}

// Returns the children in an element's details and charges them to the work
// limit, or nil once the limit is exceeded.
static NSArray *examineChildren(MGMenuTraversal *traversal, NSDictionary *details) {
    NSArray *children = [details objectForKey:MGMenuDetailChildren];
    traversal->examined += [children count];
    if (traversal->examined > MGMenuExaminedChildrenLimit) {
        fail(traversal, MGMenuResultWorkLimitExceeded, 0);
        return nil;
    }
    return children;
}

// Returns the items of the submenu an item opens, or an empty array when the
// item opens none. Returns nil after a failure.
static NSArray *submenuItems(MGMenuTraversal *traversal, NSDictionary *itemDetails) {
    NSArray *children = examineChildren(traversal, itemDetails);
    if (children == nil)
        return nil;
    NSDictionary *menu = nil;
    for (id child in children) {
        NSDictionary *details = readDetails(traversal, child);
        if (details == nil)
            return nil;
        if (![[details objectForKey:MGMenuDetailRole] isEqualToString:(NSString *)kAXMenuRole])
            continue;
        if (menu != nil) {
            fail(traversal, MGMenuResultTraversalError, 0);
            return nil;
        }
        menu = details;
    }
    return menu == nil ? @[] : examineChildren(traversal, menu);
}

// The number of single-character insertions, deletions, substitutions, and
// swaps of two neighboring characters between two strings. A swap counts as
// one edit because it is one of the most common typing mistakes.
static NSUInteger editDistance(NSString *a, NSString *b) {
    NSUInteger n = [a length], m = [b length], width = m + 1;
    NSUInteger *d = calloc((n + 1) * width, sizeof(NSUInteger));
    for (NSUInteger i = 0; i <= n; i++)
        d[i * width] = i;
    for (NSUInteger j = 0; j <= m; j++)
        d[j] = j;
    for (NSUInteger i = 1; i <= n; i++) {
        for (NSUInteger j = 1; j <= m; j++) {
            unichar ai = [a characterAtIndex:i - 1], bj = [b characterAtIndex:j - 1];
            NSUInteger cost = ai == bj ? 0 : 1;
            NSUInteger best = MIN(MIN(d[(i - 1) * width + j] + 1, d[i * width + j - 1] + 1),
                                  d[(i - 1) * width + j - 1] + cost);
            if (i > 1 && j > 1 && ai == [b characterAtIndex:j - 2] &&
                [a characterAtIndex:i - 2] == bj)
                best = MIN(best, d[(i - 2) * width + j - 2] + 1);
            d[i * width + j] = best;
        }
    }
    NSUInteger distance = d[n * width + m];
    free(d);
    return distance;
}

// Remembers title as the suggestion for wanted when it is the closest so far
// and near enough to be a likely misspelling: one edit for a short title,
// two for a longer one. A wrong guess is worse than no suggestion.
static void considerSuggestion(MGMenuTraversal *traversal, NSString *title, NSString *wanted) {
    if (title == nil)
        return;
    NSString *have = MGMenuTitleForMatching(title);
    NSString *want = MGMenuTitleForMatching(wanted);
    NSUInteger allowed = [want length] <= 4 ? 1 : 2;
    NSUInteger lengthGap = [have length] > [want length] ? [have length] - [want length]
                                                         : [want length] - [have length];
    if (lengthGap > allowed)
        return;
    NSUInteger distance = editDistance(have, want);
    if (distance == 0 || distance > allowed)
        return;
    if (traversal->suggestion == nil || distance < traversal->suggestionDistance) {
        traversal->suggestion = [traversal->location arrayByAddingObject:title];
        traversal->suggestionDistance = distance;
    }
}

static BOOL titleMatches(NSDictionary *details, NSString *wanted) {
    NSString *title = [details objectForKey:MGMenuDetailTitle];
    return title != nil &&
        [MGMenuTitleForMatching(title) isEqualToString:MGMenuTitleForMatching(wanted)];
}

static BOOL isEnabled(NSDictionary *details) {
    return [[details objectForKey:MGMenuDetailEnabled] boolValue];
}

// Follows an exact root-to-leaf path. Returns the leaf and its details.
static id findPathLeaf(MGMenuTraversal *traversal, NSArray *items, NSArray *components,
                       NSDictionary **outDetails) {
    for (NSUInteger index = 0; index < [components count]; index++) {
        id match = nil;
        NSDictionary *matchDetails = nil;
        NSUInteger matches = 0;
        NSMutableArray *titles = [NSMutableArray arrayWithCapacity:[items count]];
        for (id item in items) {
            NSDictionary *details = readDetails(traversal, item);
            if (details == nil)
                return nil;
            if ([details objectForKey:MGMenuDetailTitle] != nil)
                [titles addObject:[details objectForKey:MGMenuDetailTitle]];
            if (titleMatches(details, [components objectAtIndex:index])) {
                match = item;
                matchDetails = details;
                matches++;
            }
        }
        if (matches == 0) {
            for (NSString *title in titles)
                considerSuggestion(traversal, title, [components objectAtIndex:index]);
            fail(traversal, MGMenuResultComponentMissing, index + 1);
            return nil;
        }
        if (matches > 1) {
            fail(traversal, MGMenuResultComponentAmbiguous, index + 1);
            return nil;
        }
        [traversal->location addObject:[matchDetails objectForKey:MGMenuDetailTitle]];
        if (index + 1 == [components count]) {
            *outDetails = matchDetails;
            return match;
        }
        items = submenuItems(traversal, matchDetails);
        if (items == nil)
            return nil;
        if ([items count] == 0) {
            fail(traversal, MGMenuResultComponentMissing, index + 2);
            return nil;
        }
    }
    return nil;
}

// Searches items depth-first for the first enabled, pressable item titled
// title. Submenus are searched where they appear, before later siblings, and
// never match themselves.
static id searchItems(MGMenuTraversal *traversal, NSArray *items, NSString *title,
                      BOOL *outFailed) {
    for (id item in items) {
        NSDictionary *details = readDetails(traversal, item);
        NSArray *submenu = details == nil ? nil : submenuItems(traversal, details);
        if (submenu == nil) {
            *outFailed = YES;
            return nil;
        }
        NSString *itemTitle = [details objectForKey:MGMenuDetailTitle] ?: @"";
        if ([submenu count] > 0) {
            [traversal->location addObject:itemTitle];
            id found = searchItems(traversal, submenu, title, outFailed);
            if (found != nil || *outFailed)
                return found;
            [traversal->location removeLastObject];
            continue;
        }
        if (!titleMatches(details, title)) {
            considerSuggestion(traversal, [details objectForKey:MGMenuDetailTitle], title);
            continue;
        }
        if (![traversal->environment elementSupportsPress:item until:traversal->deadline])
            continue;
        if (isEnabled(details)) {
            [traversal->location addObject:itemTitle];
            return item;
        }
        if (traversal->disabledPath == nil)
            traversal->disabledPath = [traversal->location arrayByAddingObject:itemTitle];
    }
    return nil;
}

// Searches every menu in the menu bar. Menu-bar titles are never candidates.
static id findTitledItem(MGMenuTraversal *traversal, NSArray *roots, NSString *title) {
    for (id root in roots) {
        NSDictionary *details = readDetails(traversal, root);
        NSArray *menu = details == nil ? nil : submenuItems(traversal, details);
        if (menu == nil)
            return nil;
        [traversal->location addObject:[details objectForKey:MGMenuDetailTitle] ?: @""];
        BOOL failed = NO;
        id found = searchItems(traversal, menu, title, &failed);
        if (found != nil || failed)
            return found;
        [traversal->location removeLastObject];
    }
    if (traversal->disabledPath != nil) {
        [traversal->location setArray:traversal->disabledPath];
        fail(traversal, MGMenuResultLeafDisabled, 0);
    } else {
        fail(traversal, MGMenuResultComponentMissing, 1);
    }
    return nil;
}

static MGMenuOutcome outcome(MGMenuResult result, NSUInteger component, NSUInteger examined) {
    MGMenuOutcome value = { result, component, examined, 0, nil, nil };
    return value;
}

static MGMenuOutcome traversalOutcome(MGMenuTraversal *traversal, MGMenuResult result,
                                      NSUInteger component) {
    // A suggestion only explains a missing item.
    MGMenuOutcome value = { result, component, traversal->examined,
                            traversal->activationWaitSeconds,
                            [[traversal->location copy] autorelease],
                            result == MGMenuResultComponentMissing ? traversal->suggestion : nil };
    return value;
}

MGMenuOutcome MGRunMenuStep(NSArray<NSString *> *components, pid_t target,
                            id<MGMenuEnvironment> environment) {
    unsigned long generation = atomic_load(&cancellationGeneration);
    if (target <= 0)
        return outcome(MGMenuResultNoTargetApplication, 0, 0);
    if (![environment accessibilityTrusted])
        return outcome(MGMenuResultAccessibilityDenied, 0, 0);

    NSTimeInterval started = [environment now];
    MGMenuTraversal traversal = { environment, started + MGMenuStepDeadlineSeconds,
                                  0, MGMenuResultPressed, 0, 0, [NSMutableArray array],
                                  nil, nil, 0 };
    if (![environment processIsRunning:target])
        return outcome(MGMenuResultTargetTerminated, 0, 0);
    if ([environment frontmostProcess] != target) {
        BOOL arrived = [environment waitForFrontmostProcess:target until:traversal.deadline];
        traversal.activationWaitSeconds = [environment now] - started;
        if (!arrived)
            return traversalOutcome(&traversal, [environment processIsRunning:target]
                                    ? MGMenuResultTargetChanged : MGMenuResultTargetTerminated, 0);
    }

    id menuBar = [environment menuBarForProcess:target until:traversal.deadline];
    if (menuBar == nil)
        return traversalOutcome(&traversal, [environment now] > traversal.deadline
                                ? MGMenuResultDeadlineExceeded : MGMenuResultTraversalError, 0);
    NSDictionary *barDetails = readDetails(&traversal, menuBar);
    NSArray *roots = barDetails == nil ? nil : examineChildren(&traversal, barDetails);
    if (roots == nil)
        return traversalOutcome(&traversal, traversal.failure, 0);

    NSDictionary *leafDetails = nil;
    id item = [components count] == 1
        ? findTitledItem(&traversal, roots, [components firstObject])
        : findPathLeaf(&traversal, roots, components, &leafDetails);
    if (item == nil)
        return traversalOutcome(&traversal, traversal.failure, traversal.failureComponent);

    if ([components count] > 1) {
        NSArray *submenu = submenuItems(&traversal, leafDetails);
        if (submenu == nil)
            return traversalOutcome(&traversal, traversal.failure, 0);
        if ([submenu count] > 0 || ![environment elementSupportsPress:item until:traversal.deadline])
            return traversalOutcome(&traversal, MGMenuResultLeafNotActionable, 0);
        if (!isEnabled(leafDetails))
            return traversalOutcome(&traversal, MGMenuResultLeafDisabled, 0);
    }

    // The last checks before the press, in the order that names the cause.
    if (atomic_load(&cancellationGeneration) != generation)
        return traversalOutcome(&traversal, MGMenuResultCancelled, 0);
    if ([environment now] > traversal.deadline)
        return traversalOutcome(&traversal, MGMenuResultDeadlineExceeded, 0);
    if (![environment processIsRunning:target])
        return traversalOutcome(&traversal, MGMenuResultTargetTerminated, 0);
    if ([environment frontmostProcess] != target)
        return traversalOutcome(&traversal, MGMenuResultTargetChanged, 0);

    // Once the press call begins, a failure cannot prove the application did
    // not act, so it is never classified as a pre-press failure.
    return traversalOutcome(&traversal, [environment pressElement:item until:traversal.deadline]
                            ? MGMenuResultPressed : MGMenuResultPressOutcomeUncertain, 0);
}

NSString *MGMenuResultName(MGMenuResult result) {
    switch (result) {
        case MGMenuResultPressed: return @"pressed";
        case MGMenuResultNoTargetApplication: return @"no-target-application";
        case MGMenuResultAccessibilityDenied: return @"accessibility-denied";
        case MGMenuResultTargetTerminated: return @"target-terminated";
        case MGMenuResultTargetChanged: return @"target-changed";
        case MGMenuResultComponentMissing: return @"component-missing";
        case MGMenuResultComponentAmbiguous: return @"component-ambiguous";
        case MGMenuResultLeafNotActionable: return @"leaf-not-actionable";
        case MGMenuResultLeafDisabled: return @"leaf-disabled";
        case MGMenuResultTraversalError: return @"traversal-error";
        case MGMenuResultDeadlineExceeded: return @"deadline-exceeded";
        case MGMenuResultWorkLimitExceeded: return @"work-limit-exceeded";
        case MGMenuResultCancelled: return @"cancelled";
        case MGMenuResultQueueFull: return @"queue-full";
        case MGMenuResultPressOutcomeUncertain: return @"press-outcome-uncertain";
    }
    return @"unknown";
}

BOOL MGMenuResultPlaysAlert(MGMenuResult result) {
    return result == MGMenuResultComponentMissing || result == MGMenuResultComponentAmbiguous ||
        result == MGMenuResultLeafDisabled || result == MGMenuResultLeafNotActionable ||
        result == MGMenuResultDeadlineExceeded;
}

BOOL MGMenuFailureIsInSettings(MGMenuResult result) {
    return result == MGMenuResultComponentMissing || result == MGMenuResultComponentAmbiguous ||
        result == MGMenuResultLeafNotActionable || result == MGMenuResultWorkLimitExceeded;
}

static BOOL showsMessage(MGMenuResult result) {
    return result != MGMenuResultPressed && result != MGMenuResultCancelled;
}

// Quotes follow their source: text from the user's settings keeps the user's
// spelling, and names from the menu bar keep the application's.
NSString *MGMenuFailureMessage(MGMenuOutcome outcome, NSArray<NSString *> *components,
                               NSString *applicationName) {
    if (!showsMessage(outcome.result))
        return nil;
    NSString *app = [applicationName length] > 0 ? applicationName : @"application";
    NSString *theApp = [applicationName length] > 0 ? applicationName : @"The application";
    NSString *menuBar = [NSString stringWithFormat:@"the %@ menu bar", app];
    NSString *MenuBar = [NSString stringWithFormat:@"The %@ menu bar", app];
    NSArray *located = outcome.applicationPath;
    BOOL singleTitle = [components count] == 1;
    BOOL itemLocated = [located count] > 0 && (singleTitle || [located count] == [components count]);
    // The command as the menu bar shows it once located, else as configured.
    NSString *command = [NSString stringWithFormat:@"“%@”",
                         MGMenuPathDisplay(itemLocated ? located : components)];
    NSUInteger component = outcome.component;
    NSString *missing = component > 0 && component <= [components count]
        ? [components objectAtIndex:component - 1] : nil;
    // The menus leading to a missing or ambiguous component, as the menu bar
    // shows them.
    NSString *parent = component > 1 && [located count] >= component - 1
        ? MGMenuPathDisplay([located subarrayWithRange:NSMakeRange(0, component - 1)]) : nil;

    switch (outcome.result) {
        case MGMenuResultPressed:
        case MGMenuResultCancelled:
            return nil;
        case MGMenuResultComponentMissing:
            if ([outcome.suggestedPath count] > 0) {
                NSUInteger written = singleTitle ? 1 : MIN(component, [components count]);
                return [NSString stringWithFormat:@"Your settings say “%@”, but %@ has “%@”.",
                        MGMenuPathDisplay([components subarrayWithRange:NSMakeRange(0, written)]),
                        menuBar, MGMenuPathDisplay(outcome.suggestedPath)];
            }
            if (singleTitle)
                return [NSString stringWithFormat:@"%@ has no command named %@.", MenuBar, command];
            if (parent == nil)
                return [NSString stringWithFormat:@"%@ has no “%@” menu.", MenuBar, missing];
            return [NSString stringWithFormat:@"%@ has no “%@” under %@.", MenuBar, missing, parent];
        case MGMenuResultComponentAmbiguous:
            if (parent == nil)
                return [NSString stringWithFormat:
                        @"%@ has more than one “%@” menu, so Trickpad can’t tell which to use.",
                        MenuBar, missing];
            return [NSString stringWithFormat:
                    @"%@ has more than one “%@” under %@, so Trickpad can’t tell which to choose.",
                    MenuBar, missing, parent];
        case MGMenuResultLeafDisabled:
            return [NSString stringWithFormat:@"%@ is dimmed in %@ right now.", command, menuBar];
        case MGMenuResultLeafNotActionable:
            return [NSString stringWithFormat:
                    @"%@ opens a submenu in %@. Add the command inside it to the binding.",
                    command, menuBar];
        case MGMenuResultDeadlineExceeded:
            return [NSString stringWithFormat:@"%@ didn’t respond in time to choose %@.", theApp, command];
        case MGMenuResultTargetChanged:
            return [NSString stringWithFormat:
                    @"Another app came forward before Trickpad could choose %@ from the menu bar.",
                    command];
        case MGMenuResultTargetTerminated:
            return [NSString stringWithFormat:@"%@ quit before Trickpad could choose %@.", theApp, command];
        case MGMenuResultNoTargetApplication:
            return [NSString stringWithFormat:
                    @"Trickpad found no window under the pointer to send %@ to.", command];
        case MGMenuResultAccessibilityDenied:
            return @"Trickpad needs Accessibility access to choose menu bar commands. Turn it on in "
                   @"System Settings > Privacy & Security > Accessibility.";
        case MGMenuResultTraversalError:
            return [NSString stringWithFormat:@"Trickpad couldn’t read %@.", menuBar];
        case MGMenuResultWorkLimitExceeded:
            return [NSString stringWithFormat:
                    @"%@ is too large to search. Write the full menu path in the binding.", MenuBar];
        case MGMenuResultQueueFull:
            return @"Too many menu gestures arrived at once, so Trickpad skipped this one.";
        case MGMenuResultPressOutcomeUncertain:
            return [NSString stringWithFormat:@"macOS didn’t confirm that %@ ran in %@.",
                    command, menuBar];
    }
    return nil;
}

#pragma mark - System environment

// Whether an Accessibility error means the application did not answer, as
// opposed to the attribute having no value.
static BOOL isUnanswered(AXError error) {
    return error == kAXErrorCannotComplete || error == kAXErrorFailure;
}

static NSTimeInterval monotonicNow(void) {
    return (NSTimeInterval)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9;
}

// Lets one request wait only for the time left before the deadline, instead of
// the system default of several seconds. Returns NO when no time is left.
static BOOL limitRequestToDeadline(AXUIElementRef element, NSTimeInterval deadline) {
    NSTimeInterval remaining = deadline - monotonicNow();
    if (remaining <= 0)
        return NO;
    AXUIElementSetMessagingTimeout(element, (float)remaining);
    return YES;
}

static id copiedAttribute(id element, CFStringRef attribute, NSTimeInterval deadline) {
    AXUIElementRef axElement = (AXUIElementRef)element;
    if (!limitRequestToDeadline(axElement, deadline))
        return nil;
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(axElement, attribute, &value) != kAXErrorSuccess)
        return nil;
    return [(id)value autorelease];
}

static pid_t frontmostProcessOnMain(void) {
    return [[[NSWorkspace sharedWorkspace] frontmostApplication] processIdentifier];
}

@interface MGSystemMenuEnvironmentImpl : NSObject <MGMenuEnvironment>
@end

@implementation MGSystemMenuEnvironmentImpl

- (BOOL)accessibilityTrusted {
    return AXIsProcessTrusted();
}

- (BOOL)processIsRunning:(pid_t)pid {
    return kill(pid, 0) == 0 || errno == EPERM;
}

// NSWorkspace updates its frontmost application from notifications the main
// run loop delivers, so a read on another thread can name an application that
// is no longer frontmost. Reading on the main queue sees every delivered change.
- (pid_t)frontmostProcess {
    if ([NSThread isMainThread])
        return frontmostProcessOnMain();
    __block pid_t pid = 0;
    dispatch_sync(dispatch_get_main_queue(), ^{
        pid = frontmostProcessOnMain();
    });
    return pid;
}

- (BOOL)waitForFrontmostProcess:(pid_t)pid until:(NSTimeInterval)deadline {
    dispatch_semaphore_t activated = dispatch_semaphore_create(0);
    NSNotificationCenter *center = [[NSWorkspace sharedWorkspace] notificationCenter];
    id observer = [center addObserverForName:NSWorkspaceDidActivateApplicationNotification
                                      object:nil
                                       queue:nil
                                  usingBlock:^(NSNotification *note) {
        dispatch_semaphore_signal(activated);
    }];
    BOOL frontmost = NO;
    while (!(frontmost = [self frontmostProcess] == pid)) {
        NSTimeInterval remaining = deadline - [self now];
        if (remaining <= 0)
            break;
        dispatch_semaphore_wait(activated,
                                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)));
    }
    [center removeObserver:observer];
    dispatch_release(activated);
    return frontmost;
}

- (NSTimeInterval)now {
    return monotonicNow();
}

- (id)menuBarForProcess:(pid_t)pid until:(NSTimeInterval)deadline {
    AXUIElementRef application = AXUIElementCreateApplication(pid);
    if (application == NULL)
        return nil;
    id menuBar = copiedAttribute((id)application, kAXMenuBarAttribute, deadline);
    CFRelease(application);
    return menuBar;
}

- (NSDictionary *)detailsOfElement:(id)element until:(NSTimeInterval)deadline {
    AXUIElementRef axElement = (AXUIElementRef)element;
    if (!limitRequestToDeadline(axElement, deadline))
        return nil;
    NSArray *keys = @[MGMenuDetailChildren, MGMenuDetailTitle, MGMenuDetailRole, MGMenuDetailEnabled];
    NSArray *attributes = @[(id)kAXChildrenAttribute, (id)kAXTitleAttribute,
                            (id)kAXRoleAttribute, (id)kAXEnabledAttribute];
    CFArrayRef values = NULL;
    AXError error = AXUIElementCopyMultipleAttributeValues(axElement, (CFArrayRef)attributes,
                                                           0, &values);
    if (error != kAXErrorSuccess || values == NULL)
        return isUnanswered(error) ? nil : @{ MGMenuDetailChildren: @[] };

    // An attribute the element lacks comes back as an embedded error value.
    // Children the application left unanswered make the whole read unanswered,
    // since reading them as empty would hide a submenu.
    CFTypeRef childrenValue = CFArrayGetValueAtIndex(values, 0);
    AXError childrenError = kAXErrorSuccess;
    if (CFGetTypeID(childrenValue) == AXValueGetTypeID() &&
        AXValueGetType((AXValueRef)childrenValue) == kAXValueTypeAXError &&
        AXValueGetValue((AXValueRef)childrenValue, kAXValueTypeAXError, &childrenError) &&
        isUnanswered(childrenError)) {
        CFRelease(values);
        return nil;
    }
    NSMutableDictionary *details = [NSMutableDictionary dictionaryWithCapacity:4];
    Class expected[] = { [NSArray class], [NSString class], [NSString class], [NSNumber class] };
    for (NSUInteger index = 0; index < [keys count]; index++) {
        id value = [(NSArray *)values objectAtIndex:index];
        if ([value isKindOfClass:expected[index]])
            [details setObject:value forKey:[keys objectAtIndex:index]];
    }
    CFRelease(values);
    if ([details objectForKey:MGMenuDetailChildren] == nil)
        [details setObject:@[] forKey:MGMenuDetailChildren];
    return details;
}

- (BOOL)elementSupportsPress:(id)element until:(NSTimeInterval)deadline {
    AXUIElementRef axElement = (AXUIElementRef)element;
    if (!limitRequestToDeadline(axElement, deadline))
        return NO;
    CFArrayRef actions = NULL;
    if (AXUIElementCopyActionNames(axElement, &actions) != kAXErrorSuccess || actions == NULL)
        return NO;
    BOOL supported = CFArrayContainsValue(actions, CFRangeMake(0, CFArrayGetCount(actions)),
                                          kAXPressAction);
    CFRelease(actions);
    return supported;
}

- (BOOL)pressElement:(id)element until:(NSTimeInterval)deadline {
    AXUIElementRef axElement = (AXUIElementRef)element;
    if (!limitRequestToDeadline(axElement, deadline))
        return NO;
    return AXUIElementPerformAction(axElement, kAXPressAction) == kAXErrorSuccess;
}

@end

id<MGMenuEnvironment> MGSystemMenuEnvironment(void) {
    static MGSystemMenuEnvironmentImpl *environment = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        environment = [[MGSystemMenuEnvironmentImpl alloc] init];
    });
    return environment;
}
