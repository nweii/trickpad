// Exposes the private-framework seam used by the lifecycle check.
// Production callers use MultitouchDeviceLifecycle.h instead.

#import "MultitouchDeviceLifecycle.h"

typedef struct {
    CFMutableArrayRef (*createDeviceList)(void *context);
    int (*familyID)(void *context, MGMultitouchDeviceRef device);
    uint64_t (*deviceID)(void *context, MGMultitouchDeviceRef device);
    bool (*isRunning)(void *context, MGMultitouchDeviceRef device);
    void (*registerCallback)(void *context, MGMultitouchDeviceRef device,
                             MGMultitouchContactCallback callback);
    void (*unregisterCallback)(void *context, MGMultitouchDeviceRef device,
                               MGMultitouchContactCallback callback);
    void (*startDevice)(void *context, MGMultitouchDeviceRef device);
    void (*stopDevice)(void *context, MGMultitouchDeviceRef device);
    void (*releaseDeviceList)(void *context, CFMutableArrayRef deviceList);
    void (*waitAfterStop)(void *context);
} MGMultitouchFrameworkFunctions;

@interface MGMultitouchDeviceLifecycle (Testing)

- (instancetype)initWithTrackpadCallback:(MGMultitouchContactCallback)trackpadCallback
                            mouseCallback:(MGMultitouchContactCallback)mouseCallback
                    deviceRemovedCallback:(MGMultitouchDeviceRemovedCallback)deviceRemovedCallback
                       frameworkFunctions:(MGMultitouchFrameworkFunctions)functions
                                  context:(void *)context;
- (BOOL)replaceDeviceWithIDForTesting:(uint64_t)deviceID;

@end
