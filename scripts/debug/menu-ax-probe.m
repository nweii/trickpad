// Prototypes bounded, literal Accessibility traversal of the frontmost app's menu bar without asking macOS to open menus.
// Build: clang -fobjc-arc -framework AppKit -framework ApplicationServices scripts/debug/menu-ax-probe.m -o /tmp/menu-ax-probe

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <mach/mach_time.h>

static const NSUInteger kMinimumDepth = 2;
static const NSUInteger kMaximumDepth = 16;
static const NSUInteger kMaximumVisitedChildren = 1024;
static const CFTimeInterval kMessagingTimeoutSeconds = 0.25;
static const CFTimeInterval kTraversalBudgetSeconds = 1.0;

static const char *errorName(AXError error) {
    switch (error) {
        case kAXErrorSuccess: return "success";
        case kAXErrorFailure: return "failure";
        case kAXErrorIllegalArgument: return "illegal-argument";
        case kAXErrorInvalidUIElement: return "invalid-element";
        case kAXErrorInvalidUIElementObserver: return "invalid-observer";
        case kAXErrorCannotComplete: return "cannot-complete";
        case kAXErrorAttributeUnsupported: return "attribute-unsupported";
        case kAXErrorActionUnsupported: return "action-unsupported";
        case kAXErrorNotificationUnsupported: return "notification-unsupported";
        case kAXErrorNotImplemented: return "not-implemented";
        case kAXErrorNotificationAlreadyRegistered: return "notification-already-registered";
        case kAXErrorNotificationNotRegistered: return "notification-not-registered";
        case kAXErrorAPIDisabled: return "api-disabled";
        case kAXErrorNoValue: return "no-value";
        case kAXErrorParameterizedAttributeUnsupported: return "parameterized-attribute-unsupported";
        case kAXErrorNotEnoughPrecision: return "not-enough-precision";
    }
    return "unknown";
}

static CFTimeInterval elapsedSeconds(uint64_t startedAt) {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    uint64_t elapsed = mach_absolute_time() - startedAt;
    return ((double)elapsed * (double)timebase.numer / (double)timebase.denom) / 1e9;
}

static BOOL budgetExpired(uint64_t startedAt) {
    return elapsedSeconds(startedAt) > kTraversalBudgetSeconds;
}

static AXError copyAttribute(AXUIElementRef element, CFStringRef attribute,
                             CFTypeRef *value) {
    if (element == NULL || attribute == NULL || value == NULL)
        return kAXErrorIllegalArgument;
    *value = NULL;
    return AXUIElementCopyAttributeValue(element, attribute, value);
}

static AXError copyChildren(AXUIElementRef element, CFArrayRef *children) {
    CFTypeRef value = NULL;
    AXError error = copyAttribute(element, kAXChildrenAttribute, &value);
    if (error != kAXErrorSuccess)
        return error;
    if (value == NULL || CFGetTypeID(value) != CFArrayGetTypeID()) {
        if (value != NULL)
            CFRelease(value);
        return kAXErrorFailure;
    }
    *children = (CFArrayRef)value;
    return kAXErrorSuccess;
}

static NSString *copyTitle(AXUIElementRef element, AXError *error) {
    CFTypeRef value = NULL;
    *error = copyAttribute(element, kAXTitleAttribute, &value);
    if (*error != kAXErrorSuccess)
        return nil;
    if (value == NULL || CFGetTypeID(value) != CFStringGetTypeID()) {
        if (value != NULL)
            CFRelease(value);
        *error = kAXErrorFailure;
        return nil;
    }
    return CFBridgingRelease(value);
}

static NSString *copyRole(AXUIElementRef element, AXError *error) {
    CFTypeRef value = NULL;
    *error = copyAttribute(element, kAXRoleAttribute, &value);
    if (*error != kAXErrorSuccess)
        return nil;
    if (value == NULL || CFGetTypeID(value) != CFStringGetTypeID()) {
        if (value != NULL)
            CFRelease(value);
        *error = kAXErrorFailure;
        return nil;
    }
    return CFBridgingRelease(value);
}

static AXError copyOnlyChildMenu(AXUIElementRef item, AXUIElementRef *menu,
                                 CFIndex *childCount, CFIndex *menuCount,
                                 NSUInteger *visitedChildren,
                                 uint64_t startedAt,
                                 BOOL *workBoundExceeded,
                                 BOOL *timeBoundExceeded) {
    CFArrayRef children = NULL;
    AXError error = copyChildren(item, &children);
    if (error != kAXErrorSuccess)
        return error;

    *childCount = CFArrayGetCount(children);
    *menuCount = 0;
    if (*visitedChildren + (NSUInteger)*childCount > kMaximumVisitedChildren) {
        *workBoundExceeded = YES;
        CFRelease(children);
        return kAXErrorSuccess;
    }
    *visitedChildren += (NSUInteger)*childCount;
    AXUIElementRef found = NULL;
    for (CFIndex index = 0; index < *childCount; index++) {
        if (budgetExpired(startedAt)) {
            *timeBoundExceeded = YES;
            break;
        }
        AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, index);
        AXError roleError = kAXErrorSuccess;
        NSString *role = copyRole(child, &roleError);
        if (roleError == kAXErrorSuccess && [role isEqualToString:(__bridge NSString *)kAXMenuRole]) {
            (*menuCount)++;
            found = child;
        }
    }
    if (*menuCount == 1 && !*workBoundExceeded && !*timeBoundExceeded)
        *menu = (AXUIElementRef)CFRetain(found);
    CFRelease(children);
    return kAXErrorSuccess;
}

static void printUsage(void) {
    fprintf(stderr,
            "Usage: menu-ax-probe [--press [--hold-before-press MS] | --pid PID] COMPONENT [COMPONENT ...]\n"
            "Pass 2 to 16 literal menu titles, each as its own argument.\n"
            "Passive traversal is the default; --press explicitly requests AXPress.\n"
            "--pid passively reads one background application without changing focus.\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL shouldPress = NO;
        pid_t requestedPID = 0;
        int holdMilliseconds = 0;
        NSMutableArray<NSString *> *path = [NSMutableArray array];
        for (int index = 1; index < argc; index++) {
            NSString *argument = [NSString stringWithUTF8String:argv[index]];
            if (argument == nil) {
                fprintf(stderr, "invalid_argument=index-%d reason=invalid-utf8\n", index);
                return 64;
            }
            if ([argument isEqualToString:@"--press"]) {
                if (shouldPress || path.count > 0) {
                    fprintf(stderr, "invalid_argument=index-%d reason=press-flag-position\n", index);
                    return 64;
                }
                shouldPress = YES;
            } else if ([argument isEqualToString:@"--hold-before-press"]) {
                // Opens a window for a live focus change between traversal and the identity check.
                if (holdMilliseconds > 0 || path.count > 0 || index + 1 >= argc) {
                    fprintf(stderr, "invalid_argument=index-%d reason=hold-flag-position\n", index);
                    return 64;
                }
                holdMilliseconds = atoi(argv[++index]);
                if (holdMilliseconds <= 0 || holdMilliseconds > 5000) {
                    fprintf(stderr, "invalid_argument=index-%d reason=hold-out-of-range\n", index);
                    return 64;
                }
            } else if ([argument isEqualToString:@"--pid"]) {
                // A background target is read-only: pressing requires the frontmost-identity check.
                if (requestedPID > 0 || path.count > 0 || index + 1 >= argc) {
                    fprintf(stderr, "invalid_argument=index-%d reason=pid-flag-position\n", index);
                    return 64;
                }
                requestedPID = (pid_t)atoi(argv[++index]);
                if (requestedPID <= 0) {
                    fprintf(stderr, "invalid_argument=index-%d reason=invalid-pid\n", index);
                    return 64;
                }
            } else if (argument.length == 0) {
                fprintf(stderr, "invalid_argument=index-%d reason=empty-component\n", index);
                return 64;
            } else {
                [path addObject:argument];
            }
        }

        if (holdMilliseconds > 0 && !shouldPress) {
            fprintf(stderr, "invalid_argument=hold-without-press reason=hold-requires-press\n");
            return 64;
        }
        if (shouldPress && requestedPID > 0) {
            fprintf(stderr, "invalid_argument=press-with-pid reason=background-press-unsupported\n");
            return 64;
        }

        if (path.count < kMinimumDepth || path.count > kMaximumDepth) {
            printUsage();
            fprintf(stderr, "invalid_path=component-count-%lu minimum=%lu maximum=%lu\n",
                    (unsigned long)path.count, (unsigned long)kMinimumDepth,
                    (unsigned long)kMaximumDepth);
            return 64;
        }

        printf("mode=%s\n", shouldPress ? "press" : "passive");
        printf("path_depth=%lu\n", (unsigned long)path.count);
        printf("bounds=min-depth:%lu,max-depth:%lu,max-visited:%lu,traversal-ms:%.0f,deadline-clock:monotonic,message-ms:%.0f\n",
               (unsigned long)kMinimumDepth, (unsigned long)kMaximumDepth,
               (unsigned long)kMaximumVisitedChildren,
               kTraversalBudgetSeconds * 1000.0, kMessagingTimeoutSeconds * 1000.0);

        BOOL trusted = AXIsProcessTrusted();
        printf("accessibility_trusted=%s\n", trusted ? "yes" : "no");
        if (!trusted) {
            printf("path_exposed=no\n");
            printf("failure=accessibility-not-authorized\n");
            return 2;
        }

        NSRunningApplication *frontmost = requestedPID > 0
            ? [NSRunningApplication runningApplicationWithProcessIdentifier:requestedPID]
            : NSWorkspace.sharedWorkspace.frontmostApplication;
        printf("target=%s\n", requestedPID > 0 ? "pid" : "frontmost");
        if (frontmost == nil || frontmost.processIdentifier <= 0) {
            printf("path_exposed=no\n");
            printf("failure=no-frontmost-application\n");
            return 2;
        }
        pid_t capturedPID = frontmost.processIdentifier;
        AXUIElementRef application = AXUIElementCreateApplication(capturedPID);
        AXError timeoutError = AXUIElementSetMessagingTimeout(application, kMessagingTimeoutSeconds);
        if (timeoutError != kAXErrorSuccess) {
            printf("path_exposed=no\n");
            printf("failure=messaging-timeout-setup error=%s\n", errorName(timeoutError));
            CFRelease(application);
            return 2;
        }

        uint64_t startedAt = mach_absolute_time();
        CFTypeRef menuBarValue = NULL;
        AXError menuBarError = copyAttribute(application, kAXMenuBarAttribute, &menuBarValue);
        if (menuBarError != kAXErrorSuccess || menuBarValue == NULL ||
            CFGetTypeID(menuBarValue) != AXUIElementGetTypeID()) {
            if (menuBarValue != NULL)
                CFRelease(menuBarValue);
            printf("path_exposed=no\n");
            printf("failure=menu-bar-unavailable error=%s\n", errorName(menuBarError));
            CFRelease(application);
            return 2;
        }

        AXUIElementRef container = (AXUIElementRef)menuBarValue;
        AXUIElementRef target = NULL;
        NSUInteger visitedChildren = 0;
        for (NSUInteger componentIndex = 0; componentIndex < path.count; componentIndex++) {
            if (budgetExpired(startedAt)) {
                printf("path_exposed=no\n");
                printf("failure=traversal-budget-exceeded at-component=%lu\n",
                       (unsigned long)(componentIndex + 1));
                CFRelease(container);
                CFRelease(application);
                return 2;
            }

            CFArrayRef children = NULL;
            AXError childrenError = copyChildren(container, &children);
            if (childrenError != kAXErrorSuccess) {
                printf("component[%lu].children=unavailable error=%s\n",
                       (unsigned long)(componentIndex + 1), errorName(childrenError));
                printf("path_exposed=no\n");
                printf("failure=children-unavailable at-component=%lu\n",
                       (unsigned long)(componentIndex + 1));
                CFRelease(container);
                CFRelease(application);
                return 2;
            }

            CFIndex childCount = CFArrayGetCount(children);
            printf("component[%lu].siblings=%ld\n",
                   (unsigned long)(componentIndex + 1), (long)childCount);
            if (visitedChildren + (NSUInteger)childCount > kMaximumVisitedChildren) {
                printf("component[%lu].matches=not-evaluated\n",
                       (unsigned long)(componentIndex + 1));
                printf("path_exposed=no\n");
                printf("failure=traversal-work-bound at-component=%lu\n",
                       (unsigned long)(componentIndex + 1));
                CFRelease(children);
                CFRelease(container);
                CFRelease(application);
                return 2;
            }
            visitedChildren += (NSUInteger)childCount;

            CFIndex matchCount = 0;
            AXUIElementRef matched = NULL;
            for (CFIndex childIndex = 0; childIndex < childCount; childIndex++) {
                if (budgetExpired(startedAt))
                    break;
                AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, childIndex);
                AXError titleError = kAXErrorSuccess;
                NSString *title = copyTitle(child, &titleError);
                if (titleError == kAXErrorSuccess && [title isEqualToString:path[componentIndex]]) {
                    matchCount++;
                    matched = child;
                }
            }
            printf("component[%lu].matches=%ld\n",
                   (unsigned long)(componentIndex + 1), (long)matchCount);

            if (budgetExpired(startedAt)) {
                printf("path_exposed=no\n");
                printf("failure=traversal-budget-exceeded at-component=%lu\n",
                       (unsigned long)(componentIndex + 1));
                CFRelease(children);
                CFRelease(container);
                CFRelease(application);
                return 2;
            }
            if (matchCount != 1) {
                printf("path_exposed=no\n");
                printf("failure=%s at-component=%lu\n",
                       matchCount == 0 ? "component-not-found" : "duplicate-siblings",
                       (unsigned long)(componentIndex + 1));
                CFRelease(children);
                CFRelease(container);
                CFRelease(application);
                return 2;
            }

            AXUIElementRef matchedTarget = (AXUIElementRef)CFRetain(matched);
            CFRelease(children);
            if (componentIndex + 1 < path.count) {
                CFIndex directChildCount = 0;
                CFIndex childMenuCount = 0;
                AXUIElementRef childMenu = NULL;
                BOOL childWorkBoundExceeded = NO;
                BOOL childTimeBoundExceeded = NO;
                AXError childMenuError = copyOnlyChildMenu(
                    matchedTarget, &childMenu, &directChildCount, &childMenuCount,
                    &visitedChildren, startedAt, &childWorkBoundExceeded,
                    &childTimeBoundExceeded);
                printf("component[%lu].direct-children=%ld\n",
                       (unsigned long)(componentIndex + 1), (long)directChildCount);
                printf("component[%lu].child-menus=%ld\n",
                       (unsigned long)(componentIndex + 1), (long)childMenuCount);
                if (childMenuError != kAXErrorSuccess || childMenuCount != 1 ||
                    childWorkBoundExceeded || childTimeBoundExceeded) {
                    if (childMenuError != kAXErrorSuccess) {
                        printf("component[%lu].next-children=unavailable error=%s\n",
                               (unsigned long)(componentIndex + 1), errorName(childMenuError));
                    } else {
                        printf("component[%lu].next-children=unavailable menu-count=%ld\n",
                               (unsigned long)(componentIndex + 1), (long)childMenuCount);
                    }
                    printf("path_exposed=no\n");
                    const char *failure = "child-menu-unavailable";
                    if (childWorkBoundExceeded)
                        failure = "traversal-work-bound";
                    else if (childTimeBoundExceeded)
                        failure = "traversal-budget-exceeded";
                    else if (childMenuError == kAXErrorCannotComplete)
                        failure = "lazy-children-unavailable";
                    printf("failure=%s at-component=%lu\n", failure,
                           (unsigned long)(componentIndex + 1));
                    CFRelease(matchedTarget);
                    CFRelease(container);
                    CFRelease(application);
                    return 2;
                }
                CFRelease(container);
                container = childMenu;
                CFRelease(matchedTarget);
            } else {
                target = matchedTarget;
                break;
            }
        }

        if (target == NULL) {
            printf("path_exposed=no\n");
            printf("failure=internal-target-missing\n");
            CFRelease(container);
            CFRelease(application);
            return 2;
        }
        if (budgetExpired(startedAt)) {
            printf("path_exposed=no\n");
            printf("failure=traversal-budget-exceeded after-path-match\n");
            CFRelease(target);
            CFRelease(container);
            CFRelease(application);
            return 2;
        }

        CFTypeRef enabledValue = NULL;
        AXError enabledError = copyAttribute(target, kAXEnabledAttribute, &enabledValue);
        BOOL enabledKnown = enabledError == kAXErrorSuccess && enabledValue != NULL &&
            CFGetTypeID(enabledValue) == CFBooleanGetTypeID();
        BOOL enabled = enabledKnown && CFBooleanGetValue((CFBooleanRef)enabledValue);
        printf("path_exposed=yes\n");
        printf("enabled=%s\n", enabledKnown ? (enabled ? "yes" : "no") : "unknown");
        if (!enabledKnown)
            printf("enabled_error=%s\n", errorName(enabledError));

        if (budgetExpired(startedAt)) {
            printf("press_supported=not-checked\n");
            printf("press_accepted=not-attempted\n");
            printf("failure=traversal-budget-exceeded-after-enabled-check\n");
            if (enabledValue != NULL)
                CFRelease(enabledValue);
            CFRelease(target);
            CFRelease(container);
            CFRelease(application);
            return shouldPress ? 3 : 2;
        }

        CFArrayRef actions = NULL;
        AXError actionsError = AXUIElementCopyActionNames(target, &actions);
        BOOL pressSupported = actionsError == kAXErrorSuccess && actions != NULL &&
            CFArrayContainsValue(actions, CFRangeMake(0, CFArrayGetCount(actions)), kAXPressAction);
        printf("press_supported=%s\n",
               actionsError == kAXErrorSuccess ? (pressSupported ? "yes" : "no") : "unknown");
        if (actionsError != kAXErrorSuccess)
            printf("press_support_error=%s\n", errorName(actionsError));

        int exitCode = 0;
        if (shouldPress) {
            if (budgetExpired(startedAt)) {
                printf("frontmost_pid_unchanged=not-checked\n");
                printf("press_accepted=no\n");
                printf("failure=traversal-budget-exceeded-before-press\n");
                exitCode = 3;
            } else {
                if (holdMilliseconds > 0) {
                    printf("hold_before_press_ms=%d\n", holdMilliseconds);
                    fflush(stdout);
                    usleep((useconds_t)holdMilliseconds * 1000);
                }
                // NSWorkspace updates its frontmost value from run-loop notifications, so a
                // process that never spins its run loop reads a stale answer; compare sources.
                pid_t workspacePID = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                pid_t spunWorkspacePID = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
                pid_t accessibilityPID = 0;
                AXUIElementRef systemWide = AXUIElementCreateSystemWide();
                CFTypeRef focusedApplication = NULL;
                if (copyAttribute(systemWide, kAXFocusedApplicationAttribute, &focusedApplication) == kAXErrorSuccess &&
                    focusedApplication != NULL && CFGetTypeID(focusedApplication) == AXUIElementGetTypeID())
                    AXUIElementGetPid((AXUIElementRef)focusedApplication, &accessibilityPID);
                if (focusedApplication != NULL)
                    CFRelease(focusedApplication);
                CFRelease(systemWide);
                printf("frontmost_sources=captured:%d,workspace:%d,workspace-after-runloop:%d,accessibility:%d\n",
                       capturedPID, workspacePID, spunWorkspacePID, accessibilityPID);
                BOOL focusUnchanged = spunWorkspacePID == capturedPID && accessibilityPID == capturedPID;
                printf("frontmost_pid_unchanged=%s\n", focusUnchanged ? "yes" : "no");
                if (!focusUnchanged) {
                    printf("press_accepted=no\n");
                    printf("failure=frontmost-application-changed\n");
                    exitCode = 3;
                } else if (!enabledKnown || !enabled) {
                    printf("press_accepted=no\n");
                    printf("failure=target-not-confirmed-enabled\n");
                    exitCode = 3;
                } else if (!pressSupported) {
                    printf("press_accepted=no\n");
                    printf("failure=press-action-unavailable\n");
                    exitCode = 3;
                } else {
                    AXError pressError = AXUIElementPerformAction(target, kAXPressAction);
                    printf("press_accepted=%s\n", pressError == kAXErrorSuccess ? "yes" : "no");
                    printf("press_error=%s\n", errorName(pressError));
                    if (pressError != kAXErrorSuccess)
                        exitCode = 3;
                }
            }
        } else {
            printf("press_accepted=not-requested\n");
        }

        printf("visited_children=%lu\n", (unsigned long)visitedChildren);
        printf("traversal_ms=%.1f\n", elapsedSeconds(startedAt) * 1000.0);
        if (actions != NULL)
            CFRelease(actions);
        if (enabledValue != NULL)
            CFRelease(enabledValue);
        CFRelease(target);
        CFRelease(container);
        CFRelease(application);
        return exitCode;
    }
}
