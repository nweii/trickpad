// Owns the held middle-button state shared by Magic Mouse and trackpad click paths.

#import "MiddleButtonLifecycle.h"

#import <math.h>

// Synthesized drags bypass macOS pointer acceleration. Slow movement uses 2.0
// for precision, fast movement saturates at 4.5, and 120 mm/s is the midpoint.
// The squared speed curve is continuous and approaches both limits smoothly.
static const double kTrackpadMiddleDragLowSpeedGain = 2.0;
static const double kTrackpadMiddleDragHighSpeedGain = 4.5;
static const double kTrackpadMiddleDragMidpointMillimetersPerSecond = 120.0;
static const double kTrackpadWidthMillimeters = 160.0;
static const double kTrackpadHeightMillimeters = 115.0;
static const double kPointsPerMillimeter = 72.0 / 25.4;
static const double kTrackpadMiddleDragThresholdPoints = 1.0;

void MGMiddleButtonLifecycleInitialize(MGMiddleButtonLifecycle *lifecycle) {
    lifecycle->held = NO;
    lifecycle->device = MGMiddleButtonDeviceInvalid;
    lifecycle->contactCount = 0;
    lifecycle->accumulatedDragX = 0;
    lifecycle->accumulatedDragY = 0;
    lifecycle->lastFrameTimestamp = 0;
}

MGMiddleButtonDevice MGMiddleButtonDeviceFromEngineDevice(int engineDevice) {
    if (engineDevice == 0)
        return MGMiddleButtonDeviceTrackpad;
    if (engineDevice == 1)
        return MGMiddleButtonDeviceMagicMouse;
    return MGMiddleButtonDeviceInvalid;
}

BOOL MGMiddleButtonLifecycleShouldRewriteMouseDown(
    MGMiddleButtonLifecycle *lifecycle,
    MGMiddleButtonDevice device,
    NSString *command) {
    if (![command isEqualToString:@"Middle Click"] || lifecycle->held ||
        device == MGMiddleButtonDeviceInvalid)
        return NO;
    lifecycle->held = YES;
    lifecycle->device = device;
    return YES;
}

BOOL MGMiddleButtonLifecycleShouldDispatchOnMouseUp(
    const MGMiddleButtonLifecycle *lifecycle,
    MGMiddleButtonDevice device) {
    return device == MGMiddleButtonDeviceInvalid || !lifecycle->held ||
        lifecycle->device != device;
}

BOOL MGMiddleButtonLifecycleShouldRewriteDrag(
    const MGMiddleButtonLifecycle *lifecycle) {
    return lifecycle->held;
}

BOOL MGMiddleButtonLifecycleTrackpadDragDelta(
    MGMiddleButtonLifecycle *lifecycle,
    const int *contactIDs,
    const double *contactXs,
    const double *contactYs,
    int contactCount,
    double timestamp,
    MGMiddleButtonDragDelta *delta) {
    if (!lifecycle->held ||
        lifecycle->device != MGMiddleButtonDeviceTrackpad || delta == NULL)
        return NO;

    int count = MIN(MAX(contactCount, 0), 16);
    double previousTimestamp = lifecycle->lastFrameTimestamp;
    double totalX = 0, totalY = 0;
    int matchedCount = 0;
    for (int i = 0; i < count; i++) {
        for (int previous = 0; previous < lifecycle->contactCount; previous++) {
            if (contactIDs[i] != lifecycle->contactIDs[previous])
                continue;
            totalX += contactXs[i] - lifecycle->contactXs[previous];
            totalY += contactYs[i] - lifecycle->contactYs[previous];
            matchedCount++;
            break;
        }
    }

    lifecycle->contactCount = count;
    lifecycle->lastFrameTimestamp = timestamp;
    for (int i = 0; i < count; i++) {
        lifecycle->contactIDs[i] = contactIDs[i];
        lifecycle->contactXs[i] = contactXs[i];
        lifecycle->contactYs[i] = contactYs[i];
    }

    if (matchedCount == 0) {
        lifecycle->accumulatedDragX = 0;
        lifecycle->accumulatedDragY = 0;
        return NO;
    }
    double physicalX = totalX / matchedCount * kTrackpadWidthMillimeters;
    double physicalY = -totalY / matchedCount * kTrackpadHeightMillimeters;
    double interval = timestamp - previousTimestamp;
    double speed = interval > 0 ? hypot(physicalX, physicalY) / interval : 0;
    double speedSquared = speed * speed;
    double midpointSquared =
        kTrackpadMiddleDragMidpointMillimetersPerSecond *
        kTrackpadMiddleDragMidpointMillimetersPerSecond;
    double gain = kTrackpadMiddleDragLowSpeedGain +
        (kTrackpadMiddleDragHighSpeedGain -
         kTrackpadMiddleDragLowSpeedGain) *
        speedSquared / (speedSquared + midpointSquared);
    lifecycle->accumulatedDragX += physicalX * kPointsPerMillimeter * gain;
    lifecycle->accumulatedDragY += physicalY * kPointsPerMillimeter * gain;
    if (hypot(lifecycle->accumulatedDragX,
              lifecycle->accumulatedDragY) <
        kTrackpadMiddleDragThresholdPoints)
        return NO;

    delta->x = lifecycle->accumulatedDragX;
    delta->y = lifecycle->accumulatedDragY;
    lifecycle->accumulatedDragX = 0;
    lifecycle->accumulatedDragY = 0;
    return YES;
}

BOOL MGMiddleButtonLifecycleIsHeld(const MGMiddleButtonLifecycle *lifecycle) {
    return lifecycle->held;
}

MGMiddleButtonDevice MGMiddleButtonLifecycleHoldingDevice(
    const MGMiddleButtonLifecycle *lifecycle) {
    return lifecycle->held ? lifecycle->device : MGMiddleButtonDeviceInvalid;
}

BOOL MGMiddleButtonLifecycleEnd(MGMiddleButtonLifecycle *lifecycle) {
    BOOL held = lifecycle->held;
    MGMiddleButtonLifecycleInitialize(lifecycle);
    return held;
}
