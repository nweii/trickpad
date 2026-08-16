// Declares the shared held middle-button lifecycle and the click decisions it owns.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MGMiddleButtonDevice) {
    MGMiddleButtonDeviceInvalid = 0,
    MGMiddleButtonDeviceTrackpad = 1,
    MGMiddleButtonDeviceMagicMouse = 2,
};

typedef struct {
    double x;
    double y;
} MGMiddleButtonDragDelta;

typedef struct {
    BOOL held;
    MGMiddleButtonDevice device;
    int contactCount;
    int contactIDs[16];
    double contactXs[16];
    double contactYs[16];
    double accumulatedDragX;
    double accumulatedDragY;
    double lastFrameTimestamp;
} MGMiddleButtonLifecycle;

void MGMiddleButtonLifecycleInitialize(MGMiddleButtonLifecycle *lifecycle);

// Maps the engine's device constants into the lifecycle's nonzero identity.
// Unknown engine values map to Invalid and cannot claim a press.
MGMiddleButtonDevice MGMiddleButtonDeviceFromEngineDevice(int engineDevice);

// Claims a physical click and reports whether its mouse-down becomes a held
// middle-button down. Other actions leave the lifecycle unchanged.
BOOL MGMiddleButtonLifecycleShouldRewriteMouseDown(
    MGMiddleButtonLifecycle *lifecycle,
    MGMiddleButtonDevice device,
    NSString *command);

// Reports whether a physical click still owes its configured action on
// mouse-up. A click that held the middle button has already acted.
BOOL MGMiddleButtonLifecycleShouldDispatchOnMouseUp(
    const MGMiddleButtonLifecycle *lifecycle,
    MGMiddleButtonDevice device);

// Reports whether pointer movement belongs to the held middle-button press.
BOOL MGMiddleButtonLifecycleShouldRewriteDrag(
    const MGMiddleButtonLifecycle *lifecycle);

// Tracks consecutive trackpad contact frames and returns their accumulated
// physical-scale movement. Contact additions and removals do not create jumps.
BOOL MGMiddleButtonLifecycleTrackpadDragDelta(
    MGMiddleButtonLifecycle *lifecycle,
    const int *contactIDs,
    const double *contactXs,
    const double *contactYs,
    int contactCount,
    double timestamp,
    MGMiddleButtonDragDelta *delta);

BOOL MGMiddleButtonLifecycleIsHeld(const MGMiddleButtonLifecycle *lifecycle);
MGMiddleButtonDevice MGMiddleButtonLifecycleHoldingDevice(
    const MGMiddleButtonLifecycle *lifecycle);

// Ends the press and returns YES exactly once, telling the caller it owes the
// matching middle-button up.
BOOL MGMiddleButtonLifecycleEnd(MGMiddleButtonLifecycle *lifecycle);
