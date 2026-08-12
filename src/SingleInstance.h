// Decides which copy of the app survives when two start at once.

#import <Foundation/Foundation.h>
#import <unistd.h>

// What asking for the lock at one path produced.
typedef enum {
    MGInstanceLockAcquired,
    MGInstanceLockHeldByAnother,
    MGInstanceLockCouldNotOpen,
    MGInstanceLockFailed,
} MGInstanceLockOutcome;

// Opens path and asks for an exclusive lock on it without waiting. The
// descriptor is stored in *descriptor whenever the file opened, and is -1
// otherwise; closing it releases the lock, so an acquired one stays open for as
// long as the caller wants to hold it. errno describes either failure.
MGInstanceLockOutcome MGTakeInstanceLockAtPath(const char *path, int *descriptor);

// Whether this process should stand down because another copy already holds the
// lock. Takes the lock for the life of the process when it is free.
BOOL MGAnotherInstanceOwnsThisBundle(void);
