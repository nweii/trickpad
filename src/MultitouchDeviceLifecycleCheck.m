// Verifies device registration, full rebuild ordering, and same-ID replacement through the lifecycle seam.
// Run with scripts/check.sh.

#import <Foundation/Foundation.h>

#import "MultitouchDeviceLifecycleTesting.h"

int logLevel = 0;

typedef enum {
    FakeCreateList,
    FakeRegister,
    FakeUnregister,
    FakeStart,
    FakeStop,
    FakeReleaseList,
    FakeWait,
} FakeOperation;

typedef struct {
    uint64_t identifier;
    int familyID;
    bool running;
} FakeDevice;

typedef struct {
    FakeOperation operation;
    FakeDevice *device;
    MGMultitouchContactCallback callback;
} FakeEvent;

typedef struct {
    FakeDevice **generations[3];
    CFIndex generationCounts[3];
    int generationCount;
    int nextGeneration;
    FakeEvent events[64];
    int eventCount;
} FakeFramework;

static int trackpadCallback(MGMultitouchDeviceRef device, MGMultitouchContact *contacts,
                            int contactCount, double timestamp, int frame) {
    return 0;
}

static int mouseCallback(MGMultitouchDeviceRef device, MGMultitouchContact *contacts,
                         int contactCount, double timestamp, int frame) {
    return 0;
}

static void recordEvent(FakeFramework *framework, FakeOperation operation,
                        FakeDevice *device, MGMultitouchContactCallback callback) {
    framework->events[framework->eventCount++] = (FakeEvent){operation, device, callback};
}

static CFMutableArrayRef fakeCreateDeviceList(void *context) {
    FakeFramework *framework = context;
    int generation = MIN(framework->nextGeneration, framework->generationCount - 1);
    framework->nextGeneration++;
    recordEvent(framework, FakeCreateList, NULL, NULL);
    CFMutableArrayRef devices = CFArrayCreateMutable(kCFAllocatorDefault,
                                                     framework->generationCounts[generation],
                                                     NULL);
    for (CFIndex i = 0; i < framework->generationCounts[generation]; i++)
        CFArrayAppendValue(devices, framework->generations[generation][i]);
    return devices;
}

static int fakeFamilyID(void *context, MGMultitouchDeviceRef device) {
    return ((FakeDevice *)device)->familyID;
}

static uint64_t fakeDeviceID(void *context, MGMultitouchDeviceRef device) {
    return ((FakeDevice *)device)->identifier;
}

static bool fakeIsRunning(void *context, MGMultitouchDeviceRef device) {
    return ((FakeDevice *)device)->running;
}

static void fakeRegisterCallback(void *context, MGMultitouchDeviceRef device,
                                 MGMultitouchContactCallback callback) {
    recordEvent(context, FakeRegister, (FakeDevice *)device, callback);
}

static void fakeUnregisterCallback(void *context, MGMultitouchDeviceRef device,
                                   MGMultitouchContactCallback callback) {
    recordEvent(context, FakeUnregister, (FakeDevice *)device, callback);
}

static void fakeStartDevice(void *context, MGMultitouchDeviceRef device) {
    FakeDevice *fake = (FakeDevice *)device;
    fake->running = true;
    recordEvent(context, FakeStart, fake, NULL);
}

static void fakeStopDevice(void *context, MGMultitouchDeviceRef device) {
    FakeDevice *fake = (FakeDevice *)device;
    fake->running = false;
    recordEvent(context, FakeStop, fake, NULL);
}

static void fakeReleaseDeviceList(void *context, CFMutableArrayRef devices) {
    recordEvent(context, FakeReleaseList, NULL, NULL);
    CFRelease(devices);
}

static void fakeWaitAfterStop(void *context) {
    recordEvent(context, FakeWait, NULL, NULL);
}

static MGMultitouchFrameworkFunctions fakeFunctions(void) {
    return (MGMultitouchFrameworkFunctions){
        fakeCreateDeviceList,
        fakeFamilyID,
        fakeDeviceID,
        fakeIsRunning,
        fakeRegisterCallback,
        fakeUnregisterCallback,
        fakeStartDevice,
        fakeStopDevice,
        fakeReleaseDeviceList,
        fakeWaitAfterStop,
    };
}

static void expect(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static void expectEvent(FakeFramework *framework, int index, FakeOperation operation,
                        FakeDevice *device, MGMultitouchContactCallback callback,
                        NSString *message) {
    expect(index < framework->eventCount, [message stringByAppendingString:@" is missing"]);
    FakeEvent event = framework->events[index];
    expect(event.operation == operation && event.device == device && event.callback == callback,
           message);
}

static MGMultitouchDeviceLifecycle *createLifecycle(FakeFramework *framework) {
    return [[MGMultitouchDeviceLifecycle alloc]
        initWithTrackpadCallback:trackpadCallback
                   mouseCallback:mouseCallback
           deviceRemovedCallback:NULL
              frameworkFunctions:fakeFunctions()
                         context:framework];
}

static void checkRegistrationAndRebuild(void) {
    FakeDevice mouse = {1, 112, false};
    FakeDevice unknownTrackpad = {2, 999, false};
    FakeDevice unsupported = {3, 97, false};
    FakeDevice replacementTrackpad = {4, 129, false};
    FakeDevice *initial[] = {&mouse, &unknownTrackpad, &unsupported};
    FakeDevice *replacement[] = {&replacementTrackpad};
    FakeFramework framework = {
        .generations = {initial, replacement},
        .generationCounts = {3, 1},
        .generationCount = 2,
    };
    MGMultitouchDeviceLifecycle *lifecycle = createLifecycle(&framework);

    [lifecycle start];
    expect(framework.eventCount == 5, @"start touches only supported devices");
    expectEvent(&framework, 0, FakeCreateList, NULL, NULL, @"start enumerates devices");
    expectEvent(&framework, 1, FakeRegister, &mouse, mouseCallback,
                @"start gives the mouse its callback");
    expectEvent(&framework, 2, FakeStart, &mouse, NULL, @"start starts the mouse");
    expectEvent(&framework, 3, FakeRegister, &unknownTrackpad, trackpadCallback,
                @"start treats an unknown supported family as a trackpad");
    expectEvent(&framework, 4, FakeStart, &unknownTrackpad, NULL,
                @"start starts an unknown supported family");

    framework.eventCount = 0;
    [lifecycle rebuild];
    expect(framework.eventCount == 11, @"rebuild performs the complete recovery sequence");
    expectEvent(&framework, 0, FakeUnregister, &mouse, trackpadCallback,
                @"rebuild removes the trackpad callback from the mouse");
    expectEvent(&framework, 1, FakeUnregister, &mouse, mouseCallback,
                @"rebuild removes the mouse callback from the mouse");
    expectEvent(&framework, 2, FakeStop, &mouse, NULL, @"rebuild stops the mouse");
    expectEvent(&framework, 3, FakeUnregister, &unknownTrackpad, trackpadCallback,
                @"rebuild removes the trackpad callback from the trackpad");
    expectEvent(&framework, 4, FakeUnregister, &unknownTrackpad, mouseCallback,
                @"rebuild removes the mouse callback from the trackpad");
    expectEvent(&framework, 5, FakeStop, &unknownTrackpad, NULL, @"rebuild stops the trackpad");
    expectEvent(&framework, 6, FakeReleaseList, NULL, NULL, @"rebuild releases the old list");
    expectEvent(&framework, 7, FakeWait, NULL, NULL, @"rebuild preserves the recovery delay");
    expectEvent(&framework, 8, FakeCreateList, NULL, NULL, @"rebuild enumerates a fresh list");
    expectEvent(&framework, 9, FakeRegister, &replacementTrackpad, trackpadCallback,
                @"rebuild registers the fresh device");
    expectEvent(&framework, 10, FakeStart, &replacementTrackpad, NULL,
                @"rebuild starts the fresh device");

    [lifecycle release];
}

static void checkSameIDReplacement(void) {
    FakeDevice oldMouse = {42, 112, false};
    FakeDevice newMouse = {42, 112, false};
    FakeDevice *initial[] = {&oldMouse};
    FakeDevice *replacement[] = {&newMouse};
    FakeFramework framework = {
        .generations = {initial, replacement},
        .generationCounts = {1, 1},
        .generationCount = 2,
    };
    MGMultitouchDeviceLifecycle *lifecycle = createLifecycle(&framework);
    [lifecycle start];

    framework.eventCount = 0;
    expect([lifecycle replaceDeviceWithIDForTesting:42],
           @"device-change replacement finds the new framework device");
    expectEvent(&framework, 1, FakeUnregister, &oldMouse, trackpadCallback,
                @"replacement unregisters the old trackpad callback");
    expectEvent(&framework, 2, FakeUnregister, &oldMouse, mouseCallback,
                @"replacement unregisters the old mouse callback");
    expectEvent(&framework, 3, FakeStop, &oldMouse, NULL, @"replacement stops the old device");
    expectEvent(&framework, 4, FakeRegister, &newMouse, mouseCallback,
                @"replacement registers the new device");
    expectEvent(&framework, 5, FakeStart, &newMouse, NULL, @"replacement starts the new device");
    expectEvent(&framework, 6, FakeReleaseList, NULL, NULL,
                @"replacement releases its enumeration list");
    expect(framework.eventCount == 7, @"replacement performs one reviewable lifecycle");

    [lifecycle release];
}

int main(void) {
    @autoreleasepool {
        checkRegistrationAndRebuild();
        checkSameIDReplacement();
        NSLog(@"multitouch device lifecycle: all checks passed");
    }
    return 0;
}
