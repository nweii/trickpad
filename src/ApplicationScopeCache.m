// Caches the application candidates a binding lookup resolves against, since touch frames ask for them at the device's report rate.

#import "ApplicationScopeCache.h"

#import <AppKit/AppKit.h>
#import <os/lock.h>
#import <time.h>

// A quarter of a second. The cached list names the application under the
// pointer as well as the frontmost one. The frontmost part changes only on
// activation, which invalidates the cache, but the element under a stationary
// pointer can change with no notification at all, so the whole list is cached
// together behind a short lifetime rather than kept live: resolving the
// pointer's application is the most expensive part of the answer, and a live
// read would leave every touch frame paying for it. The lifetime bounds the
// staleness to below what a hand can act on, so an application-scoped binding
// still takes effect as its window comes under the pointer, and it takes
// effect at once when that window also comes forward.
static const uint64_t kDefaultLifetimeNanoseconds = 250ull * NSEC_PER_MSEC;

static os_unfair_lock cacheLock = OS_UNFAIR_LOCK_INIT;
static MGApplicationScopeResolver cacheResolver = NULL;
static NSArray *cachedCandidates = nil;
static uint64_t cachedAt = 0;
static uint64_t cacheLifetime = kDefaultLifetimeNanoseconds;

static uint64_t nowNanoseconds(void) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

void MGApplicationScopeCacheSetResolver(MGApplicationScopeResolver resolver) {
    os_unfair_lock_lock(&cacheLock);
    cacheResolver = resolver;
    [cachedCandidates release];
    cachedCandidates = nil;
    os_unfair_lock_unlock(&cacheLock);
}

void MGApplicationScopeCacheSetLifetime(uint64_t nanoseconds) {
    os_unfair_lock_lock(&cacheLock);
    cacheLifetime = nanoseconds;
    os_unfair_lock_unlock(&cacheLock);
}

void MGApplicationScopeCacheInvalidate(void) {
    os_unfair_lock_lock(&cacheLock);
    [cachedCandidates release];
    cachedCandidates = nil;
    os_unfair_lock_unlock(&cacheLock);
}

NSArray *MGApplicationScopeCacheCandidates(void) {
    // The multi-touch callbacks run on their own threads, so the whole read is
    // taken under one lock. A hit costs an uncontended lock and a clock read;
    // a miss holds the lock across the resolve so two callback threads cannot
    // both pay for the same answer.
    os_unfair_lock_lock(&cacheLock);
    if (cachedCandidates != nil && nowNanoseconds() - cachedAt < cacheLifetime) {
        NSArray *candidates = [[cachedCandidates retain] autorelease];
        os_unfair_lock_unlock(&cacheLock);
        return candidates;
    }

    NSArray *resolved = cacheResolver != NULL ? cacheResolver() : [NSArray array];
    [cachedCandidates release];
    cachedCandidates = [resolved copy];
    cachedAt = nowNanoseconds();
    NSArray *candidates = [[cachedCandidates retain] autorelease];
    os_unfair_lock_unlock(&cacheLock);
    return candidates;
}

// The notification arrives on the main thread while gesture lookups read from
// the callback threads, which the cache's own lock already covers.
@interface MGApplicationScopeCacheObserver : NSObject
@end

@implementation MGApplicationScopeCacheObserver
- (void)applicationActivated:(NSNotification *)notification {
    MGApplicationScopeCacheInvalidate();
}
@end

void MGApplicationScopeCacheObserveApplicationActivation(void) {
    static MGApplicationScopeCacheObserver *observer = nil;
    if (observer != nil)
        return;
    observer = [[MGApplicationScopeCacheObserver alloc] init];
    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserver:observer
           selector:@selector(applicationActivated:)
               name:NSWorkspaceDidActivateApplicationNotification
             object:nil];
}
