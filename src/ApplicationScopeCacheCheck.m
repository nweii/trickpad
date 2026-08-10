// Asserts that the application scope cache answers repeated lookups without resolving again, and that a configuration reload and an application activation both drop it. Run with scripts/check.sh.

#import <AppKit/AppKit.h>

#import "ApplicationScopeCache.h"

static int failures = 0;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL  %s\n", what);
        failures++;
    }
}

// Stands in for the Accessibility resolution the engine installs. Counting its
// calls is how the check sees whether a lookup reached Accessibility at all.
static int resolveCount = 0;
static NSArray *countingResolver(void) {
    resolveCount++;
    return @[@"Finder", @"com.apple.finder"];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        MGApplicationScopeCacheSetResolver(countingResolver);
        MGApplicationScopeCacheSetLifetime(60ull * NSEC_PER_SEC);

        NSArray *first = MGApplicationScopeCacheCandidates();
        expect(resolveCount == 1, "the first lookup resolves the candidates");
        expect([first isEqualToArray:(@[@"Finder", @"com.apple.finder"])],
               "the cache returns the resolved candidates in order");

        // The cached read path must reach no Accessibility call: the resolver
        // is the only thing that performs one, and it is not called again.
        for (int frame = 0; frame < 500; frame++) {
            NSArray *cached = MGApplicationScopeCacheCandidates();
            expect([cached isEqualToArray:first], "a cached lookup returns the same candidates");
        }
        expect(resolveCount == 1, "repeated lookups perform no further resolution");

        // A configuration reload, simulated by the call Settings makes.
        MGApplicationScopeCacheInvalidate();
        MGApplicationScopeCacheCandidates();
        expect(resolveCount == 2, "a configuration reload drops the cached candidates");
        MGApplicationScopeCacheCandidates();
        expect(resolveCount == 2, "the answer is cached again after a reload");

        // An application activation, injected as the notification itself so
        // the check needs no real application switch.
        MGApplicationScopeCacheObserveApplicationActivation();
        [[[NSWorkspace sharedWorkspace] notificationCenter]
            postNotificationName:NSWorkspaceDidActivateApplicationNotification
                          object:[NSWorkspace sharedWorkspace]
                        userInfo:nil];
        MGApplicationScopeCacheCandidates();
        expect(resolveCount == 3, "an application activation drops the cached candidates");
        MGApplicationScopeCacheCandidates();
        expect(resolveCount == 3, "the answer is cached again after an activation");

        // The element under the pointer changes with neither event, so the
        // cached answer expires on its own as well.
        MGApplicationScopeCacheSetLifetime(0);
        MGApplicationScopeCacheCandidates();
        MGApplicationScopeCacheCandidates();
        expect(resolveCount == 5, "an expired answer is resolved again");

        // Installing a resolver must not serve the previous one's answer.
        MGApplicationScopeCacheSetLifetime(60ull * NSEC_PER_SEC);
        MGApplicationScopeCacheCandidates();
        int beforeReinstall = resolveCount;
        MGApplicationScopeCacheSetResolver(countingResolver);
        MGApplicationScopeCacheCandidates();
        expect(resolveCount == beforeReinstall + 1, "a new resolver replaces the cached answer");

        if (failures == 0) {
            printf("application scope cache: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "application scope cache: %d failure(s)\n", failures);
        return 1;
    }
}
