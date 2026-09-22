// Defines asynchronous ordered dispatch for one parsed sequence binding.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

typedef void (^MGSequenceScheduler)(NSTimeInterval delay, dispatch_block_t block);
// Returns NO to stop the rest of the sequence, as a failed menu step does.
typedef BOOL (^MGSequenceStepHandler)(NSDictionary *step);

@interface MGSequenceDispatcher : NSObject {
    NSUInteger _generation;
    MGSequenceScheduler _scheduler;
    NSMutableArray *_pendingSequences;
    BOOL _sequenceRunning;
    BOOL _runningSequenceIsLimited;
}

- (instancetype)initWithScheduler:(MGSequenceScheduler)scheduler;

// Queues every action in order and returns before the first action runs. A
// sequence added while another runs starts after the active sequence finishes.
- (void)dispatchSequence:(NSArray *)sequence stepHandler:(MGSequenceStepHandler)handler;

// Like dispatchSequence:stepHandler:, but admits the sequence only while fewer
// than limit limited sequences are running or waiting, counting the running
// one. Returns NO without queueing when the limit is reached; queued work is
// never displaced.
- (BOOL)dispatchSequence:(NSArray *)sequence
              limitedTo:(NSUInteger)limit
             stepHandler:(MGSequenceStepHandler)handler;

// Drops every action that has not started.
- (void)cancelAll;

@end
