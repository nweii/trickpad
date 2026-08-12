// Defines immutable contact snapshots and the device-specific builders that derive their named views.

#import <Foundation/Foundation.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint pos, vel; } MTReadout;

enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7
};

typedef uint32_t MTTouchState;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    MTTouchState state;
    int fingerId, handId;
    MTReadout normalized;
    float size;
    int zero1;
    float angle, majorAxis, minorAxis;
    MTReadout mm;
    int zero2[2];
    float zDensity;
} Finger;

typedef struct {
    const Finger *contacts;
    int count;
} MGContactList;

typedef struct {
    MGContactList raw;
    MGContactList thumbFiltered;
    MGContactList fingertipScale;
} MGContactFrame;

typedef struct {
    int thumbIdentifier;
} MGTrackpadContactFrameBuilder;

void MGTrackpadContactFrameBuilderInitialize(MGTrackpadContactFrameBuilder *builder);
MGContactFrame MGTrackpadContactFrameCreate(MGTrackpadContactFrameBuilder *builder,
                                            const Finger *contacts,
                                            int contactCount,
                                            BOOL leftHanded);
MGContactFrame MGMagicMouseContactFrameCreate(const Finger *contacts,
                                              int contactCount,
                                              BOOL leftHanded);
void MGContactFrameDestroy(MGContactFrame *frame);
