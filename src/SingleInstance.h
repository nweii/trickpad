// Decides which copy of the app survives when two start at once.

#import <Foundation/Foundation.h>
#import <unistd.h>

// Whether this process should stand down because another copy already owns the
// bundle. Both copies evaluate the same rule against the same set, so exactly
// one of them yields.
BOOL MGShouldYieldToExistingInstance(pid_t mine, const pid_t *others, int count);

// The same decision against the copies macOS reports as running now.
BOOL MGAnotherInstanceOwnsThisBundle(void);
