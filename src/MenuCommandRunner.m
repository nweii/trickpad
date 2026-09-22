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

const NSTimeInterval MGMenuStepDeadlineSeconds = 1.0;
// A browser's full menu bar, with its history and bookmarks menus, measured
// 1,400 to 3,000 elements and took up to about half a second to search. The
// one-second deadline is the bound a real application reaches; this limit sits
// above it and only stops a pathological tree.
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
    // The first matching item that read as disabled during a title search.
    BOOL sawDisabledMatch;
} MGMenuTraversal;

static BOOL fail(MGMenuTraversal *traversal, MGMenuResult result, NSUInteger component) {
    traversal->failure = result;
    traversal->failureComponent = component;
    return NO;
}

// Reads an element's children and charges them to the work limit.
static NSArray *examineChildren(MGMenuTraversal *traversal, id element) {
    if ([traversal->environment now] > traversal->deadline) {
        fail(traversal, MGMenuResultDeadlineExceeded, 0);
        return nil;
    }
    NSArray *children = [traversal->environment childrenOfElement:element];
    if (children == nil) {
        fail(traversal, MGMenuResultTraversalError, 0);
        return nil;
    }
    traversal->examined += [children count];
    if (traversal->examined > MGMenuExaminedChildrenLimit) {
        fail(traversal, MGMenuResultWorkLimitExceeded, 0);
        return nil;
    }
    return children;
}

// Returns the single menu beneath an item, or nil when it has none. A leaf's
// children may be unreadable, which counts as having no menu.
static id childMenu(MGMenuTraversal *traversal, id item, BOOL *outFailed) {
    *outFailed = NO;
    if ([traversal->environment now] > traversal->deadline) {
        *outFailed = YES;
        fail(traversal, MGMenuResultDeadlineExceeded, 0);
        return nil;
    }
    NSArray *children = [traversal->environment childrenOfElement:item];
    if (children == nil)
        return nil;
    traversal->examined += [children count];
    if (traversal->examined > MGMenuExaminedChildrenLimit) {
        *outFailed = YES;
        fail(traversal, MGMenuResultWorkLimitExceeded, 0);
        return nil;
    }
    id menu = nil;
    for (id child in children) {
        if ([[traversal->environment roleOfElement:child] isEqualToString:(NSString *)kAXMenuRole]) {
            if (menu != nil) {
                *outFailed = YES;
                fail(traversal, MGMenuResultTraversalError, 0);
                return nil;
            }
            menu = child;
        }
    }
    return menu;
}

static BOOL titleMatches(MGMenuTraversal *traversal, id element, NSString *wanted) {
    NSString *title = [traversal->environment titleOfElement:element];
    return title != nil &&
        [MGMenuTitleForMatching(title) isEqualToString:MGMenuTitleForMatching(wanted)];
}

// Follows an exact root-to-leaf path and returns the leaf.
static id findPathLeaf(MGMenuTraversal *traversal, id menuBar, NSArray *components) {
    id container = menuBar;
    for (NSUInteger index = 0; index < [components count]; index++) {
        NSArray *children = examineChildren(traversal, container);
        if (children == nil)
            return nil;
        id match = nil;
        NSUInteger matches = 0;
        for (id child in children) {
            if (titleMatches(traversal, child, [components objectAtIndex:index])) {
                match = child;
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
        if (index + 1 == [components count])
            return match;
        BOOL failed = NO;
        container = childMenu(traversal, match, &failed);
        if (failed)
            return nil;
        if (container == nil) {
            fail(traversal, MGMenuResultComponentMissing, index + 2);
            return nil;
        }
    }
    return nil;
}

static BOOL itemIsPressable(MGMenuTraversal *traversal, id item, id submenu) {
    return submenu == nil && [traversal->environment elementSupportsPress:item];
}

// Searches one menu depth-first for the first enabled, pressable item titled
// title. Submenus are searched where they appear, before later siblings.
static id searchMenu(MGMenuTraversal *traversal, id menu, NSString *title, BOOL *outFailed) {
    NSArray *items = examineChildren(traversal, menu);
    if (items == nil) {
        *outFailed = YES;
        return nil;
    }
    for (id item in items) {
        BOOL failed = NO;
        id submenu = childMenu(traversal, item, &failed);
        if (failed) {
            *outFailed = YES;
            return nil;
        }
        if (submenu != nil) {
            id found = searchMenu(traversal, submenu, title, outFailed);
            if (found != nil || *outFailed)
                return found;
            continue;
        }
        if (!titleMatches(traversal, item, title) || !itemIsPressable(traversal, item, nil))
            continue;
        if ([[traversal->environment enabledStateOfElement:item] boolValue])
            return item;
        traversal->sawDisabledMatch = YES;
    }
    return nil;
}

static id findTitledItem(MGMenuTraversal *traversal, id menuBar, NSString *title) {
    NSArray *roots = examineChildren(traversal, menuBar);
    if (roots == nil)
        return nil;
    for (id root in roots) {
        BOOL failed = NO;
        id menu = childMenu(traversal, root, &failed);
        if (failed)
            return nil;
        if (menu == nil)
            continue;
        id found = searchMenu(traversal, menu, title, &failed);
        if (found != nil || failed)
            return found;
    }
    fail(traversal, traversal->sawDisabledMatch ? MGMenuResultLeafDisabled
                                                : MGMenuResultComponentMissing, 1);
    return nil;
}

static MGMenuOutcome outcome(MGMenuResult result, NSUInteger component, NSUInteger examined) {
    MGMenuOutcome value = { result, component, examined };
    return value;
}

MGMenuOutcome MGRunMenuStep(NSArray<NSString *> *components, pid_t target,
                            id<MGMenuEnvironment> environment) {
    unsigned long generation = atomic_load(&cancellationGeneration);
    if (target <= 0)
        return outcome(MGMenuResultNoTargetApplication, 0, 0);
    if (![environment accessibilityTrusted])
        return outcome(MGMenuResultAccessibilityDenied, 0, 0);

    MGMenuTraversal traversal = { environment, [environment now] + MGMenuStepDeadlineSeconds,
                                  0, MGMenuResultPressed, 0, NO };
    if (![environment processIsRunning:target])
        return outcome(MGMenuResultTargetTerminated, 0, 0);
    if ([environment frontmostProcess] != target &&
        ![environment waitForFrontmostProcess:target until:traversal.deadline])
        return outcome([environment processIsRunning:target] ? MGMenuResultTargetChanged
                                                             : MGMenuResultTargetTerminated, 0, 0);

    id menuBar = [environment menuBarForProcess:target];
    if (menuBar == nil)
        return outcome(MGMenuResultTraversalError, 0, 0);
    id item = [components count] == 1
        ? findTitledItem(&traversal, menuBar, [components firstObject])
        : findPathLeaf(&traversal, menuBar, components);
    if (item == nil)
        return outcome(traversal.failure, traversal.failureComponent, traversal.examined);

    if ([components count] > 1) {
        BOOL failed = NO;
        id submenu = childMenu(&traversal, item, &failed);
        if (failed)
            return outcome(traversal.failure, 0, traversal.examined);
        if (!itemIsPressable(&traversal, item, submenu))
            return outcome(MGMenuResultLeafNotActionable, 0, traversal.examined);
        if (![[environment enabledStateOfElement:item] boolValue])
            return outcome(MGMenuResultLeafDisabled, 0, traversal.examined);
    }

    // The last checks before the press, in the order that names the cause.
    if (atomic_load(&cancellationGeneration) != generation)
        return outcome(MGMenuResultCancelled, 0, traversal.examined);
    if ([environment now] > traversal.deadline)
        return outcome(MGMenuResultDeadlineExceeded, 0, traversal.examined);
    if (![environment processIsRunning:target])
        return outcome(MGMenuResultTargetTerminated, 0, traversal.examined);
    if ([environment frontmostProcess] != target)
        return outcome(MGMenuResultTargetChanged, 0, traversal.examined);

    // Once the press call begins, a failure cannot prove the application did
    // not act, so it is never classified as a pre-press failure.
    return outcome([environment pressElement:item] ? MGMenuResultPressed
                                                   : MGMenuResultPressOutcomeUncertain,
                   0, traversal.examined);
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

- (id)menuBarForProcess:(pid_t)pid {
    AXUIElementRef application = AXUIElementCreateApplication(pid);
    if (application == NULL)
        return nil;
    id menuBar = copiedAttribute((id)application, kAXMenuBarAttribute);
    CFRelease(application);
    return menuBar;
}

- (NSArray *)childrenOfElement:(id)element {
    id children = copiedAttribute(element, kAXChildrenAttribute);
    return [children isKindOfClass:[NSArray class]] ? children : nil;
}

- (NSString *)titleOfElement:(id)element {
    id title = copiedAttribute(element, kAXTitleAttribute);
    return [title isKindOfClass:[NSString class]] ? title : nil;
}

- (NSString *)roleOfElement:(id)element {
    id role = copiedAttribute(element, kAXRoleAttribute);
    return [role isKindOfClass:[NSString class]] ? role : nil;
}

- (NSNumber *)enabledStateOfElement:(id)element {
    id enabled = copiedAttribute(element, kAXEnabledAttribute);
    return [enabled isKindOfClass:[NSNumber class]] ? enabled : nil;
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
