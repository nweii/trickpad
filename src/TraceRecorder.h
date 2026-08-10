// Declares the bounded, privacy-safe recorder used by guided hardware trace sessions.

#import <Foundation/Foundation.h>

typedef struct {
    int identifier;
    int state;
    double x;
    double y;
    double size;
    double majorAxis;
    double minorAxis;
    double density;
} MGTraceContact;

BOOL MGTraceStart(NSString *bundlePath, NSString **problem);
// Starts a session whose manifest names the capture kind, and for a candidate
// gesture protocol, the short name the person typed for the motion they record.
BOOL MGTraceStartCapture(NSString *bundlePath, NSString *capture,
                         NSString *candidate, NSString **problem);
BOOL MGTraceIsActive(void);
BOOL MGTraceIsCapturing(void);
BOOL MGTraceSuppressesActions(void);
BOOL MGTraceAuditsGestureCatalog(void);
BOOL MGTraceObservesUnconfiguredGesture(NSString *gesture);
NSString *MGTraceBundlePath(void);
NSDictionary *MGTraceStatus(void);
void MGTraceBeginStep(NSString *step, NSString *requested,
                      NSString *observedGesture, NSUInteger expectedDispatchCount,
                      NSString *instruction, BOOL closesOnFullLift,
                      BOOL auditsGestureCatalog);
void MGTraceMarkStep(NSString *label);
void MGTraceFinishOpenStep(NSString *label);
void MGTraceStop(void);

void MGTraceRecordMouseFrame(const void *device, double hardwareTimestamp,
                             int frame, const MGTraceContact *contacts,
                             int contactCount);
void MGTraceRecordTrackpadFrame(const void *device, double hardwareTimestamp,
                                int frame, const MGTraceContact *contacts,
                                int contactCount);
void MGTraceRecordFilterDecision(int identifier, NSString *reason, BOOL kept,
                                 double x, double y, double size,
                                 double majorAxis, double minorAxis);
void MGTraceRecordCGEvent(NSString *event, double pressure,
                          int64_t axis1, int64_t axis2, NSString *disposition);
void MGTraceRecordClickEligibility(NSString *stage, int rawContactCount,
                                   int eligibleContactCount);
void MGTraceRecordCandidate(NSString *gesture, NSString *phase,
                            NSString *reason);
void MGTraceRecordOwnership(NSString *requested, NSString *previous,
                            NSString *result, BOOL accepted);
void MGTraceRecordDispatch(NSString *gesture, NSString *scope,
                           NSString *actionKind, NSString *outcome);

// Test seam: serializes one already-safe envelope with stable key ordering.
NSData *MGTraceDeterministicJSONLine(NSDictionary *event, NSString **problem);
