// Checks held numbered-button decisions with the engine's actual device mapping.

#import <Foundation/Foundation.h>
#import <math.h>
#import "jitouch/Jitouch/GestureDevice.h"
#import "MouseButtonLifecycle.h"

static int failures = 0;

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL  %s\n", [message UTF8String]);
        failures++;
    }
}

static void requireRelease(MGMouseButtonLifecycle *lifecycle, NSString *path) {
    require(MGMouseButtonLifecycleEnd(lifecycle),
            [NSString stringWithFormat:@"%@ did not release the held button", path]);
    require(!MGMouseButtonLifecycleIsHeld(lifecycle),
            [NSString stringWithFormat:@"%@ left the button held", path]);
    require(!MGMouseButtonLifecycleEnd(lifecycle),
            [NSString stringWithFormat:@"%@ released the button twice", path]);
}

int main(void) {
    @autoreleasepool {
        MGMouseButtonLifecycle lifecycle;
        MGMouseButtonLifecycleInitialize(&lifecycle);
        MGMouseButtonDevice trackpad =
            MGMouseButtonDeviceFromEngineDevice(TRACKPAD);
        MGMouseButtonDevice magicMouse =
            MGMouseButtonDeviceFromEngineDevice(MAGICMOUSE);

        require(trackpad == MGMouseButtonDeviceTrackpad &&
                    trackpad != MGMouseButtonDeviceInvalid,
                @"the engine's zero-valued trackpad did not map to a valid device");
        require(magicMouse == MGMouseButtonDeviceMagicMouse,
                @"the engine's Magic Mouse did not map to its lifecycle device");
        require(MGMouseButtonDeviceFromEngineDevice(-1) ==
                    MGMouseButtonDeviceInvalid &&
                    MGMouseButtonDeviceFromEngineDevice(2) ==
                    MGMouseButtonDeviceInvalid,
                @"an unknown engine device mapped to a valid lifecycle device");

        require(MGMouseButtonNumberForCommand(@"Middle Click") == 2 &&
                    MGMouseButtonNumberForCommand(@"Mouse Button 3") == 2 &&
                    MGMouseButtonNumberForCommand(@"Mouse Button 32") == 31,
                @"documented actions did not map to Quartz button numbers");
        require(MGMouseButtonNumberForCommand(@"Mouse Button 2") == -1 &&
                    MGMouseButtonNumberForCommand(@"Mouse Button 33") == -1 &&
                    MGMouseButtonNumberForCommand(@"Mission Control") == -1,
                @"an unsupported action mapped to a mouse button");

        // The escaped regression: with no held press, a trackpad physical click
        // bound to another action must dispatch on mouse-up.
        require(!MGMouseButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, trackpad, @"Mission Control"),
                @"a non-middle trackpad click rewrote its mouse-down");
        require(MGMouseButtonLifecycleShouldDispatchOnMouseUp(
                    &lifecycle, trackpad),
                @"a non-middle trackpad click did not dispatch on mouse-up");

        require(MGMouseButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, trackpad, @"Middle Click"),
                @"a trackpad middle click did not produce its one down");
        require(!MGMouseButtonLifecycleShouldDispatchOnMouseUp(
                    &lifecycle, trackpad),
                @"a held trackpad middle click also dispatched on mouse-up");
        require(MGMouseButtonLifecycleShouldRewriteDrag(&lifecycle),
                @"a held trackpad middle click did not rewrite its drag");
        int firstIDs[] = {11, 12, 13};
        double firstXs[] = {0.20, 0.40, 0.60};
        double firstYs[] = {0.30, 0.50, 0.70};
        MGMouseButtonDragDelta delta = {0};
        require(!MGMouseButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, firstXs, firstYs, 3, 0.0, &delta),
                @"the first trackpad frame produced movement without a baseline");
        require(!MGMouseButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, firstXs, firstYs, 3, 0.01, &delta),
                @"stationary contacts produced a drag");
        double tinyXs[] = {0.2005, 0.4005, 0.6005};
        require(!MGMouseButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, tinyXs, firstYs, 3, 0.02, &delta),
                @"sub-threshold contact jitter produced a drag");
        double accumulatedXs[] = {0.2025, 0.4025, 0.6025};
        require(MGMouseButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, accumulatedXs, firstYs, 3,
                    0.03, &delta) && delta.x >= 2.0 && delta.x < 2.6 &&
                    fabs(delta.y) < 0.001,
                @"accumulated contact movement did not cross the drag threshold");

        requireRelease(&lifecycle, @"the slow drag calibration");
        require(MGMouseButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, trackpad, @"Middle Click"),
                @"a slow-speed calibration press did not begin");
        require(!MGMouseButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, firstXs, firstYs, 3, 1.0, &delta),
                @"the slow-speed calibration baseline produced movement");
        double speedXs[] = {0.202, 0.402, 0.602};
        require(MGMouseButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, speedXs, firstYs, 3,
                    2.0, &delta) && delta.x >= 1.8 && delta.x < 1.9,
                @"a slow contact movement did not stay near the low-speed gain");
        requireRelease(&lifecycle, @"the slow-speed calibration");
        require(MGMouseButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, trackpad, @"Middle Click"),
                @"a fast calibration press did not begin");
        require(!MGMouseButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, firstXs, firstYs, 3, 3.0, &delta),
                @"the fast calibration baseline produced movement");
        require(MGMouseButtonLifecycleTrackpadDragDelta(
                    &lifecycle, firstIDs, speedXs, firstYs, 3,
                    3.0001, &delta) && delta.x >= 4.0 && delta.x < 4.2,
                @"a fast contact sweep did not approach the high-speed gain");
        require(!MGMouseButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, magicMouse, @"Middle Click"),
                @"a second device claimed an already-held button");
        require(MGMouseButtonLifecycleHoldingDevice(&lifecycle) == trackpad,
                @"a second claim replaced the holding device");
        requireRelease(&lifecycle, @"the click release");

        require(MGMouseButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, magicMouse, @"Mouse Button 32"),
                @"a numbered mouse-button action did not begin a held press");
        require(MGMouseButtonLifecycleHoldingButtonNumber(&lifecycle) == 31,
                @"a held press did not retain its Quartz button number");
        requireRelease(&lifecycle, @"the numbered click release");

        for (NSString *path in @[@"reload", @"wake", @"trackpad off",
                                  @"Magic Mouse off", @"interrupted release",
                                  @"a new mouse-down"]) {
            require(MGMouseButtonLifecycleShouldRewriteMouseDown(
                        &lifecycle, magicMouse, @"Middle Click"),
                    [NSString stringWithFormat:@"%@ could not begin a press", path]);
            requireRelease(&lifecycle, path);
        }

        require(!MGMouseButtonLifecycleShouldRewriteMouseDown(
                    &lifecycle, MGMouseButtonDeviceInvalid, @"Middle Click"),
                @"an invalid device claimed a press");

        if (failures == 0) {
            printf("mouse button lifecycle: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "mouse button lifecycle: %d failure(s)\n", failures);
        return 1;
    }
}
