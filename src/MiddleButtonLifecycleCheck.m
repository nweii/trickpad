// Checks held middle-button decisions with the engine's actual device mapping.

#import <Foundation/Foundation.h>
#import <math.h>
#import "jitouch/Jitouch/GestureDevice.h"
#import "MiddleButtonLifecycle.h"

static int failures = 0;

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL  %s\n", [message UTF8String]);
        failures++;
    }
}

static void requireRelease(MGMiddleButtonLifecycle *lifecycle, NSString *path) {
    require(MGMiddleButtonLifecycleEnd(lifecycle),
            [NSString stringWithFormat:@"%@ did not release the held button", path]);
    require(!MGMiddleButtonLifecycleIsHeld(lifecycle),
            [NSString stringWithFormat:@"%@ left the button held", path]);
    require(!MGMiddleButtonLifecycleEnd(lifecycle),
            [NSString stringWithFormat:@"%@ released the button twice", path]);
}

int main(void) {
    @autoreleasepool {
        MGMiddleButtonLifecycle lifecycle;
        MGMiddleButtonLifecycleInitialize(&lifecycle);
        MGMiddleButtonDevice trackpad =
            MGMiddleButtonDeviceFromEngineDevice(TRACKPAD);
        MGMiddleButtonDevice magicMouse =
            MGMiddleButtonDeviceFromEngineDevice(MAGICMOUSE);

        require(trackpad == MGMiddleButtonDeviceTrackpad &&
                    trackpad != MGMiddleButtonDeviceInvalid,
                @"the engine's zero-valued trackpad did not map to a valid device");
        require(magicMouse == MGMiddleButtonDeviceMagicMouse,
                @"the engine's Magic Mouse did not map to its lifecycle device");
        require(MGMiddleButtonDeviceFromEngineDevice(-1) ==
                    MGMiddleButtonDeviceInvalid &&
                    MGMiddleButtonDeviceFromEngineDevice(2) ==
                    MGMiddleButtonDeviceInvalid,
                @"an unknown engine device mapped to a valid lifecycle device");

        // The escaped regression: with no held press, a trackpad physical click
        // bound to another action must dispatch on mouse-up.
        require(!MGMiddleButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, trackpad, @"Mission Control"),
                @"a non-middle trackpad click rewrote its mouse-down");
        require(MGMiddleButtonLifecycleShouldDispatchOnMouseUp(
                    &lifecycle, trackpad),
                @"a non-middle trackpad click did not dispatch on mouse-up");

        require(MGMiddleButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, trackpad, @"Middle Click"),
                @"a trackpad middle click did not produce its one down");
        require(!MGMiddleButtonLifecycleShouldDispatchOnMouseUp(
                    &lifecycle, trackpad),
                @"a held trackpad middle click also dispatched on mouse-up");
        require(MGMiddleButtonLifecycleShouldRewriteDrag(&lifecycle),
                @"a held trackpad middle click did not rewrite its drag");
        int firstIDs[] = {11, 12, 13};
        double firstXs[] = {0.20, 0.40, 0.60};
        double firstYs[] = {0.30, 0.50, 0.70};
        MGMiddleButtonDragDelta delta = {0};
        require(!MGMiddleButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, firstXs, firstYs, 3, 0.0, &delta),
                @"the first trackpad frame produced movement without a baseline");
        require(!MGMiddleButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, firstXs, firstYs, 3, 0.01, &delta),
                @"stationary contacts produced a drag");
        double tinyXs[] = {0.2005, 0.4005, 0.6005};
        require(!MGMiddleButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, tinyXs, firstYs, 3, 0.02, &delta),
                @"sub-threshold contact jitter produced a drag");
        double accumulatedXs[] = {0.2025, 0.4025, 0.6025};
        require(MGMiddleButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, accumulatedXs, firstYs, 3,
                    0.03, &delta) && delta.x >= 2.0 && delta.x < 2.6 &&
                    fabs(delta.y) < 0.001,
                @"accumulated contact movement did not cross the drag threshold");

        requireRelease(&lifecycle, @"the slow drag calibration");
        require(MGMiddleButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, trackpad, @"Middle Click"),
                @"a slow-speed calibration press did not begin");
        require(!MGMiddleButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, firstXs, firstYs, 3, 1.0, &delta),
                @"the slow-speed calibration baseline produced movement");
        double speedXs[] = {0.202, 0.402, 0.602};
        require(MGMiddleButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, speedXs, firstYs, 3,
                    2.0, &delta) && delta.x >= 1.8 && delta.x < 1.9,
                @"a slow contact movement did not stay near the low-speed gain");
        requireRelease(&lifecycle, @"the slow-speed calibration");
        require(MGMiddleButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, trackpad, @"Middle Click"),
                @"a fast calibration press did not begin");
        require(!MGMiddleButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, firstXs, firstYs, 3, 3.0, &delta),
                @"the fast calibration baseline produced movement");
        require(MGMiddleButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, speedXs, firstYs, 3,
                    3.0001, &delta) && delta.x >= 4.0 && delta.x < 4.2,
                @"a fast contact sweep did not approach the high-speed gain");
        require(!MGMiddleButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, magicMouse, @"Middle Click"),
                @"a second device claimed an already-held button");
        require(MGMiddleButtonLifecycleHoldingDevice(&lifecycle) == trackpad,
                @"a second claim replaced the holding device");
        requireRelease(&lifecycle, @"the click release");

        for (NSString *path in @[@"reload", @"wake", @"trackpad off",
                                  @"Magic Mouse off", @"interrupted release",
                                  @"a new mouse-down"]) {
            require(MGMiddleButtonLifecycleShouldRewriteMouseDown(
                        &lifecycle, magicMouse, @"Middle Click"),
                    [NSString stringWithFormat:@"%@ could not begin a press", path]);
            requireRelease(&lifecycle, path);
        }

        require(!MGMiddleButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, MGMiddleButtonDeviceInvalid, @"Middle Click"),
                @"an invalid device claimed a press");

        if (failures == 0) {
            printf("middle button lifecycle: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "middle button lifecycle: %d failure(s)\n", failures);
        return 1;
    }
}
