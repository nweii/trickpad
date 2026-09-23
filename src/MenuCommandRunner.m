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

// An application that has just come forward can leave Accessibility requests
// unanswered for most of a second while it rebuilds its menus, and a full
// title search of a large menu bar then takes several hundred milliseconds.
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
    // Whether a title search passed over a matching item that was disabled.
    BOOL sawDisabledMatch;
    NSTimeInterval activationWaitSeconds;
    NSUInteger unansweredReads;
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

// Reads an element's details. Nothing has been pressed yet, so an unanswered
// read is repeated until the deadline.
static NSDictionary *readDetails(MGMenuTraversal *traversal, id element) {
    while (!pastDeadline(traversal)) {
        NSDictionary *details = [traversal->environment detailsOfElement:element];
        if (details != nil)
            return details;
        traversal->unansweredReads++;
        [traversal->environment pauseBeforeRetry];
    }
    return nil;
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
        for (id item in items) {
            NSDictionary *details = readDetails(traversal, item);
            if (details == nil)
                return nil;
            if (titleMatches(details, [components objectAtIndex:index])) {
                match = item;
                matchDetails = details;
                matches++;
            }
        }
        if (matches == 0) {
            fail(traversal, MGMenuResultComponentMissing, index + 1);
            return nil;
        }
        if (matches > 1) {
            fail(traversal, MGMenuResultComponentAmbiguous, index + 1);
            return nil;
        }
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
        if ([submenu count] > 0) {
            id found = searchItems(traversal, submenu, title, outFailed);
            if (found != nil || *outFailed)
                return found;
            continue;
        }
        if (!titleMatches(details, title) || ![traversal->environment elementSupportsPress:item])
            continue;
        if (isEnabled(details))
            return item;
        traversal->sawDisabledMatch = YES;
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
        BOOL failed = NO;
        id found = searchItems(traversal, menu, title, &failed);
        if (found != nil || failed)
            return found;
    }
    fail(traversal, traversal->sawDisabledMatch ? MGMenuResultLeafDisabled
                                                : MGMenuResultComponentMissing, 1);
    return nil;
}

static MGMenuOutcome outcome(MGMenuResult result, NSUInteger component, NSUInteger examined) {
    MGMenuOutcome value = { result, component, examined, 0, 0 };
    return value;
}

static MGMenuOutcome traversalOutcome(MGMenuTraversal *traversal, MGMenuResult result,
                                      NSUInteger component) {
    MGMenuOutcome value = { result, component, traversal->examined,
                            traversal->activationWaitSeconds, traversal->unansweredReads };
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
                                  0, MGMenuResultPressed, 0, NO, 0, 0 };
    if (![environment processIsRunning:target])
        return outcome(MGMenuResultTargetTerminated, 0, 0);
    if ([environment frontmostProcess] != target) {
        BOOL arrived = [environment waitForFrontmostProcess:target until:traversal.deadline];
        traversal.activationWaitSeconds = [environment now] - started;
        if (!arrived)
            return traversalOutcome(&traversal, [environment processIsRunning:target]
                                    ? MGMenuResultTargetChanged : MGMenuResultTargetTerminated, 0);
    }

    id menuBar = nil;
    while ((menuBar = [environment menuBarForProcess:target]) == nil) {
        if ([environment now] > traversal.deadline)
            return traversalOutcome(&traversal, MGMenuResultDeadlineExceeded, 0);
        traversal.unansweredReads++;
        [environment pauseBeforeRetry];
    }
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
        if ([submenu count] > 0 || ![environment elementSupportsPress:item])
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
    return traversalOutcome(&traversal, [environment pressElement:item]
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

BOOL MGMenuResultIsUnavailableItem(MGMenuResult result) {
    return result == MGMenuResultComponentMissing || result == MGMenuResultComponentAmbiguous ||
        result == MGMenuResultLeafDisabled || result == MGMenuResultLeafNotActionable;
}

#pragma mark - System environment

// A hung application would otherwise hold each Accessibility call for the
// system default of several seconds.
static const float kMessagingTimeoutSeconds = 0.25f;

// Whether an Accessibility error means the application did not answer, as
// opposed to the attribute having no value.
static BOOL isUnanswered(AXError error) {
    return error == kAXErrorCannotComplete || error == kAXErrorFailure;
}

static const useconds_t kRetryPauseMicroseconds = 20000;

static id copiedAttribute(id element, CFStringRef attribute) {
    AXUIElementRef axElement = (AXUIElementRef)element;
    AXUIElementSetMessagingTimeout(axElement, kMessagingTimeoutSeconds);
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
    return (NSTimeInterval)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9;
}

- (void)pauseBeforeRetry {
    usleep(kRetryPauseMicroseconds);
}

- (id)menuBarForProcess:(pid_t)pid {
    AXUIElementRef application = AXUIElementCreateApplication(pid);
    if (application == NULL)
        return nil;
    // An application with no menu bar never answers usefully, so its missing
    // value is treated like silence and ends at the deadline.
    id menuBar = copiedAttribute((id)application, kAXMenuBarAttribute);
    CFRelease(application);
    return menuBar;
}

- (NSDictionary *)detailsOfElement:(id)element {
    AXUIElementRef axElement = (AXUIElementRef)element;
    AXUIElementSetMessagingTimeout(axElement, kMessagingTimeoutSeconds);
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

- (BOOL)elementSupportsPress:(id)element {
    AXUIElementRef axElement = (AXUIElementRef)element;
    AXUIElementSetMessagingTimeout(axElement, kMessagingTimeoutSeconds);
    CFArrayRef actions = NULL;
    if (AXUIElementCopyActionNames(axElement, &actions) != kAXErrorSuccess || actions == NULL)
        return NO;
    BOOL supported = CFArrayContainsValue(actions, CFRangeMake(0, CFArrayGetCount(actions)),
                                          kAXPressAction);
    CFRelease(actions);
    return supported;
}

- (BOOL)pressElement:(id)element {
    AXUIElementRef axElement = (AXUIElementRef)element;
    AXUIElementSetMessagingTimeout(axElement, kMessagingTimeoutSeconds);
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
