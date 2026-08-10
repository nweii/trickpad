// Declares the cache that holds the application names a binding lookup resolves against, so touch frames do not pay an Accessibility round trip each.

#import <Foundation/Foundation.h>

// Returns the application candidates in resolution order. The engine installs
// the resolver that reads Accessibility; a check installs a counting stub.
typedef NSArray *(*MGApplicationScopeResolver)(void);

void MGApplicationScopeCacheSetResolver(MGApplicationScopeResolver resolver);

// The read path every binding lookup goes through.
NSArray *MGApplicationScopeCacheCandidates(void);

// Drops the cached answer. Called when the configuration reloads and when
// another application becomes active.
void MGApplicationScopeCacheInvalidate(void);

// Observes NSWorkspaceDidActivateApplicationNotification for the lifetime of
// the process.
void MGApplicationScopeCacheObserveApplicationActivation(void);

// How long a resolved answer stays usable without an invalidating event.
// Production keeps the default; a check sets it to bound or expire the window.
void MGApplicationScopeCacheSetLifetime(uint64_t nanoseconds);
