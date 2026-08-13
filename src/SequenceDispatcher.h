// Defines asynchronous ordered dispatch for one parsed sequence binding.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

typedef void (^MGSequenceScheduler)(NSTimeInterval delay, dispatch_block_t block);
typedef void (^MGSequenceStepHandler)(NSDictionary *step);

@interface MGSequenceDispatcher : NSObject {
    NSUInteger _generation;
    MGSequenceScheduler _scheduler;
    NSMutableArray *_pendingSequences;
    BOOL _sequenceRunning;
}

- (instancetype)initWithScheduler:(MGSequenceScheduler)scheduler;

// Queues every action in order and returns before the first action runs. A
// sequence added while another runs starts after the active sequence finishes.
- (void)dispatchSequence:(NSArray *)sequence stepHandler:(MGSequenceStepHandler)handler;

// Drops every action that has not started.
- (void)cancelAll;

@end
