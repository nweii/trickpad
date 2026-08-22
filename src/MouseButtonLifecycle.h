// Declares the shared held mouse-button lifecycle and the click decisions it owns.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MGMouseButtonDevice) {
    MGMouseButtonDeviceInvalid = 0,
    MGMouseButtonDeviceTrackpad = 1,
    MGMouseButtonDeviceMagicMouse = 2,
};

typedef struct {
    double x;
    double y;
} MGMouseButtonDragDelta;

typedef struct {
    BOOL held;
    MGMouseButtonDevice device;
    NSInteger buttonNumber;
    int contactCount;
    int contactIDs[16];
    double contactXs[16];
    double contactYs[16];
    double accumulatedDragX;
    double accumulatedDragY;
    double lastFrameTimestamp;
} MGMouseButtonLifecycle;

void MGMouseButtonLifecycleInitialize(MGMouseButtonLifecycle *lifecycle);

// Maps the engine's device constants into the lifecycle's nonzero identity.
// Unknown engine values map to Invalid and cannot claim a press.
MGMouseButtonDevice MGMouseButtonDeviceFromEngineDevice(int engineDevice);

// Returns the zero-based Quartz number for a configured mouse-button action,
// or -1 when the command is not one of mouse-3 through mouse-32.
NSInteger MGMouseButtonNumberForCommand(NSString *command);

// Claims a physical click and reports whether its mouse-down becomes a held
// numbered-button down. Other actions leave the lifecycle unchanged.
BOOL MGMouseButtonLifecycleShouldRewriteMouseDown(
    MGMouseButtonLifecycle *lifecycle,
    MGMouseButtonDevice device,
    NSString *command);

// Reports whether a physical click still owes its configured action on
// mouse-up. A click that held a numbered button has already acted.
BOOL MGMouseButtonLifecycleShouldDispatchOnMouseUp(
    const MGMouseButtonLifecycle *lifecycle,
    MGMouseButtonDevice device);

// Reports whether pointer movement belongs to the held numbered-button press.
BOOL MGMouseButtonLifecycleShouldRewriteDrag(
    const MGMouseButtonLifecycle *lifecycle);

// Tracks consecutive trackpad contact frames and returns their accumulated
// physical-scale movement. Contact additions and removals do not create jumps.
BOOL MGMouseButtonLifecycleTrackpadDragDelta(
    MGMouseButtonLifecycle *lifecycle,
    const int *contactIDs,
    const double *contactXs,
    const double *contactYs,
    int contactCount,
    double timestamp,
    MGMouseButtonDragDelta *delta);

BOOL MGMouseButtonLifecycleIsHeld(const MGMouseButtonLifecycle *lifecycle);
MGMouseButtonDevice MGMouseButtonLifecycleHoldingDevice(
    const MGMouseButtonLifecycle *lifecycle);
NSInteger MGMouseButtonLifecycleHoldingButtonNumber(
    const MGMouseButtonLifecycle *lifecycle);

// Ends the press and returns YES exactly once, telling the caller it owes the
// matching numbered-button up.
BOOL MGMouseButtonLifecycleEnd(MGMouseButtonLifecycle *lifecycle);
