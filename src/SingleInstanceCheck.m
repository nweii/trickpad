// Asserts that two copies starting at once agree on which one survives.

#import <Foundation/Foundation.h>
#import "SingleInstance.h"

static int failures = 0;

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"%@", message);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        // Alone in the world, nothing to yield to.
        require(!MGShouldYieldToExistingInstance(100, NULL, 0),
                @"a lone instance stood down");

        // Its own entry appears in the list macOS returns, and is not a rival.
        pid_t justMe[1] = {100};
        require(!MGShouldYieldToExistingInstance(100, justMe, 1),
                @"an instance yielded to itself");

        // The pair an update produces. Exactly one must stand down, and both
        // reach that answer from the same set without coordinating.
        pid_t pair[2] = {100, 101};
        BOOL lowerYields = MGShouldYieldToExistingInstance(100, pair, 2);
        BOOL higherYields = MGShouldYieldToExistingInstance(101, pair, 2);
        require(!lowerYields, @"the lower process identifier stood down");
        require(higherYields, @"the higher process identifier survived");
        require(lowerYields != higherYields,
                @"two copies did not agree on which one survives");

        // Order of discovery must not change the answer.
        pid_t reversed[2] = {101, 100};
        require(MGShouldYieldToExistingInstance(101, reversed, 2),
                @"the decision depended on the order the copies were listed");

        // Three at once still leaves exactly one.
        pid_t three[3] = {50, 60, 70};
        int survivors = 0;
        for (int i = 0; i < 3; i++) {
            if (!MGShouldYieldToExistingInstance(three[i], three, 3))
                survivors++;
        }
        require(survivors == 1, @"three copies did not settle on one survivor");

        if (failures == 0)
            NSLog(@"single instance: all checks passed");
    }
    return failures == 0 ? 0 : 1;
}
