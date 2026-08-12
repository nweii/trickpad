// Adapts the private MultitouchSupport and IOKit device lifecycles to two contact callbacks.
// Framework declarations and recovery ordering stay local to this file.

#import "MultitouchDeviceLifecycle.h"
#import "MultitouchDeviceLifecycleTesting.h"

#import <IOKit/IOKitLib.h>
#import <inttypes.h>
#import <unistd.h>

#import "Settings.h"

// kIOMasterPortDefault is the macOS 11 spelling of the main IOKit port.
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

typedef int (*MTContactCallbackFunction)(MGMultitouchDeviceRef, MGMultitouchContact *, int, double, int);

CFMutableArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MGMultitouchDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MGMultitouchDeviceRef, int);
void MTUnregisterContactFrameCallback(MGMultitouchDeviceRef, MTContactCallbackFunction);
void MTDeviceStop(MGMultitouchDeviceRef);
bool MTDeviceIsRunning(MGMultitouchDeviceRef);
void MTDeviceGetFamilyID(MGMultitouchDeviceRef, int *);
OSStatus MTDeviceGetDeviceID(MGMultitouchDeviceRef, uint64_t *) __attribute__((weak_import));

static const int kBuiltinTrackpadFamilyIDs[] = {
    98, 99, 100, // built-in trackpad
    101, // retina mbp
    102, // retina macbook with the Force Touch trackpad (2015)
    103, // retina mbp 13" with the Force Touch trackpad (2015)
    104,
    105, // macbook with touch bar, m1 pro mbp
    113, // m2 mbp with touch bar
};
static const int kMagicMouseFamilyIDs[] = {
    112, // magic mouse & magic mouse 2
};
static const int kMagicTrackpadFamilyIDs[] = {
    128, // magic trackpad
    129, // magic trackpad 2
    130, // magic trackpad 3?
};
static const int kMinimumSupportedFamilyID = 98;

typedef enum {
    MGMultitouchDeviceUnsupported,
    MGMultitouchDeviceTrackpad,
    MGMultitouchDeviceMouse,
} MGMultitouchDeviceKind;

typedef struct {
    MGMultitouchFrameworkFunctions framework;
    void *frameworkContext;
    CFMutableArrayRef deviceList;
    MGMultitouchContactCallback trackpadCallback;
    MGMultitouchContactCallback mouseCallback;
    MGMultitouchDeviceRemovedCallback deviceRemovedCallback;
    BOOL observeDeviceChanges;
    IONotificationPortRef notificationPort;
    io_iterator_t addedIterator;
    io_iterator_t removedIterator;
} MGMultitouchDeviceLifecycleState;

@interface MGMultitouchDeviceLifecycle () {
    MGMultitouchDeviceLifecycleState *_state;
}
- (void)replaceDeviceWithTimer:(NSTimer *)timer;
- (void)handleRemovedIterator:(io_iterator_t)iterator;
@end

static BOOL familyIsInList(int familyID, const int *familyIDs, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (familyIDs[i] == familyID)
            return YES;
    }
    return NO;
}

static MGMultitouchDeviceKind deviceKindForFamilyID(int familyID) {
    if (familyIsInList(familyID, kMagicMouseFamilyIDs,
                       sizeof(kMagicMouseFamilyIDs) / sizeof(kMagicMouseFamilyIDs[0])))
        return MGMultitouchDeviceMouse;
    if (familyIsInList(familyID, kBuiltinTrackpadFamilyIDs,
                       sizeof(kBuiltinTrackpadFamilyIDs) / sizeof(kBuiltinTrackpadFamilyIDs[0])) ||
        familyIsInList(familyID, kMagicTrackpadFamilyIDs,
                       sizeof(kMagicTrackpadFamilyIDs) / sizeof(kMagicTrackpadFamilyIDs[0])) ||
        familyID >= kMinimumSupportedFamilyID) // Unknown IDs are treated as trackpads.
        return MGMultitouchDeviceTrackpad;
    return MGMultitouchDeviceUnsupported;
}

static CFMutableArrayRef createDeviceList(void *context) {
    return MTDeviceCreateList();
}

static int deviceFamilyID(void *context, MGMultitouchDeviceRef device) {
    int familyID = 0;
    MTDeviceGetFamilyID(device, &familyID);
    return familyID;
}

static uint64_t deviceID(void *context, MGMultitouchDeviceRef device) {
    uint64_t identifier = 0;
    MTDeviceGetDeviceID(device, &identifier);
    return identifier;
}

static bool deviceIsRunning(void *context, MGMultitouchDeviceRef device) {
    return MTDeviceIsRunning(device);
}

static void registerCallback(void *context, MGMultitouchDeviceRef device,
                             MGMultitouchContactCallback callback) {
    MTRegisterContactFrameCallback(device, callback);
}

static void unregisterCallback(void *context, MGMultitouchDeviceRef device,
                               MGMultitouchContactCallback callback) {
    MTUnregisterContactFrameCallback(device, callback);
}

static void startDevice(void *context, MGMultitouchDeviceRef device) {
    MTDeviceStart(device, 0);
}

static void stopDevice(void *context, MGMultitouchDeviceRef device) {
    MTDeviceStop(device);
}

static void releaseDeviceList(void *context, CFMutableArrayRef deviceList) {
    CFRelease(deviceList);
}

static void waitAfterStop(void *context) {
    sleep(1);
}

static MGMultitouchFrameworkFunctions productionFrameworkFunctions(void) {
    return (MGMultitouchFrameworkFunctions){
        createDeviceList,
        deviceFamilyID,
        deviceID,
        deviceIsRunning,
        registerCallback,
        unregisterCallback,
        startDevice,
        stopDevice,
        releaseDeviceList,
        waitAfterStop,
    };
}

static void logDevice(MGMultitouchDeviceLifecycleState *state, NSString *action,
                      CFIndex index, MGMultitouchDeviceRef device, int familyID) {
    if (logLevel < LOG_LEVEL_INFO)
        return;
    uint64_t identifier = state->framework.deviceID(state->frameworkContext, device);
    BOOL running = state->framework.isRunning(state->frameworkContext, device);
    NSLog(@"%@ device %li %" PRIu64 " family %d (%s)", action, (long)index,
          identifier, familyID, running ? "running" : "not running");
}

static void logDeviceState(MGMultitouchDeviceLifecycleState *state, CFIndex index,
                           MGMultitouchDeviceRef device, int familyID) {
    if (logLevel < LOG_LEVEL_INFO)
        return;
    uint64_t identifier = state->framework.deviceID(state->frameworkContext, device);
    BOOL running = state->framework.isRunning(state->frameworkContext, device);
    NSLog(@"Device %li %" PRIu64 " family %d is %s", (long)index, identifier,
          familyID, running ? "running" : "not running");
}

static void startDeviceAtIndex(MGMultitouchDeviceLifecycleState *state,
                               MGMultitouchDeviceRef device, CFIndex index) {
    int familyID = state->framework.familyID(state->frameworkContext, device);
    MGMultitouchDeviceKind kind = deviceKindForFamilyID(familyID);
    logDevice(state, @"Start", index, device, familyID);
    if (kind == MGMultitouchDeviceMouse) {
        state->framework.registerCallback(state->frameworkContext, device,
                                          state->mouseCallback);
        state->framework.startDevice(state->frameworkContext, device);
    } else if (kind == MGMultitouchDeviceTrackpad) {
        state->framework.registerCallback(state->frameworkContext, device,
                                          state->trackpadCallback);
        state->framework.startDevice(state->frameworkContext, device);
    }
    logDeviceState(state, index, device, familyID);
}

static void startDeviceList(MGMultitouchDeviceLifecycleState *state) {
    for (CFIndex i = 0; i < CFArrayGetCount(state->deviceList); i++) {
        MGMultitouchDeviceRef device = (MGMultitouchDeviceRef)CFArrayGetValueAtIndex(state->deviceList, i);
        startDeviceAtIndex(state, device, i);
    }
}

static void stopDeviceAtIndex(MGMultitouchDeviceLifecycleState *state,
                              MGMultitouchDeviceRef device, CFIndex index) {
    int familyID = state->framework.familyID(state->frameworkContext, device);
    logDevice(state, @"Stop", index, device, familyID);
    if (familyID >= kMinimumSupportedFamilyID) {
        state->framework.unregisterCallback(state->frameworkContext, device,
                                            state->trackpadCallback);
        state->framework.unregisterCallback(state->frameworkContext, device,
                                            state->mouseCallback);
        state->framework.stopDevice(state->frameworkContext, device);
    }
    logDeviceState(state, index, device, familyID);
}

static void stopDeviceList(MGMultitouchDeviceLifecycleState *state) {
    if (state->deviceList == NULL)
        return;
    for (CFIndex i = 0; i < CFArrayGetCount(state->deviceList); i++) {
        MGMultitouchDeviceRef device = (MGMultitouchDeviceRef)CFArrayGetValueAtIndex(state->deviceList, i);
        stopDeviceAtIndex(state, device, i);
    }
}

static void scheduleDeviceReplacement(MGMultitouchDeviceLifecycle *lifecycle,
                                      uint64_t identifier, int attempt) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
        @"Multitouch ID": [NSNumber numberWithUnsignedLongLong:identifier],
        @"Attempt": [NSNumber numberWithInt:attempt],
    }];
    [NSTimer scheduledTimerWithTimeInterval:(attempt == 0 ? 0.0 : 1.0)
                                     target:lifecycle
                                   selector:@selector(replaceDeviceWithTimer:)
                                   userInfo:info
                                    repeats:NO];
}

static BOOL replaceDeviceWithID(MGMultitouchDeviceLifecycleState *state,
                                uint64_t newDeviceID) {
    BOOL found = NO;
    CFMutableArrayRef candidates = state->framework.createDeviceList(state->frameworkContext);
    for (CFIndex i = 0; i < CFArrayGetCount(candidates); i++) {
        MGMultitouchDeviceRef device = (MGMultitouchDeviceRef)CFArrayGetValueAtIndex(candidates, i);
        if (state->framework.deviceID(state->frameworkContext, device) != newDeviceID)
            continue;

        int familyID = state->framework.familyID(state->frameworkContext, device);
        CFIndex oldIndex = -1;
        for (CFIndex old = 0; old < CFArrayGetCount(state->deviceList); old++) {
            MGMultitouchDeviceRef oldDevice = (MGMultitouchDeviceRef)CFArrayGetValueAtIndex(state->deviceList, old);
            if (state->framework.deviceID(state->frameworkContext, oldDevice) == newDeviceID) {
                if (state->framework.isRunning(state->frameworkContext, oldDevice))
                    stopDeviceAtIndex(state, oldDevice, old);
                oldIndex = old;
                break;
            }
        }
        if (oldIndex >= 0)
            CFArrayRemoveValueAtIndex(state->deviceList, oldIndex);

        startDeviceAtIndex(state, device, i);
        if (deviceKindForFamilyID(familyID) != MGMultitouchDeviceUnsupported) {
            found = YES;
            CFArrayAppendValue(state->deviceList, device);
        }
    }
    state->framework.releaseDeviceList(state->frameworkContext, candidates);
    return found;
}

static void multitouchDeviceAdded(void *refCon, io_iterator_t iterator) {
    MGMultitouchDeviceLifecycle *lifecycle = (MGMultitouchDeviceLifecycle *)refCon;
    io_service_t addedDevice;
    while ((addedDevice = IOIteratorNext(iterator))) {
        io_name_t deviceName;
        io_string_t pathName;
        int familyID;
        NSInteger identifier = 0;
        IORegistryEntryGetName(addedDevice, deviceName);
//        NSLog(@"Device's name = %s\n", deviceName);
        IORegistryEntryGetPath(addedDevice, kIOServicePlane, pathName);
//        NSLog(@"Device's path in IOService plane = %s\n", pathName);
        CFTypeRef identifierValue = IORegistryEntrySearchCFProperty(
            addedDevice, pathName, CFSTR("Family ID"), kCFAllocatorDefault, 0);
        if (identifierValue != NULL) {
            familyID = (int)[(NSString *)identifierValue integerValue];
//            NSLog(@"Device's family ID = %@ -> %d", identifierValue, familyID);
            CFRelease(identifierValue);
        }
        identifierValue = IORegistryEntrySearchCFProperty(
            addedDevice, pathName, CFSTR("Multitouch ID"), kCFAllocatorDefault, 0);
        if (identifierValue != NULL) {
            identifier = [(NSString *)identifierValue integerValue];
//            NSLog(@"Device's multitouch ID = %@ -> %llu", identifierValue, (uint64_t)identifier);
            CFRelease(identifierValue);
        }
        IOObjectRelease(addedDevice);
        scheduleDeviceReplacement(lifecycle, (uint64_t)identifier, 0);
    }
}

static void multitouchDeviceRemoved(void *refCon, io_iterator_t iterator) {
    MGMultitouchDeviceLifecycle *lifecycle = (MGMultitouchDeviceLifecycle *)refCon;
    [lifecycle handleRemovedIterator:iterator];
}

@implementation MGMultitouchDeviceLifecycle

- (void)handleRemovedIterator:(io_iterator_t)iterator {
    io_service_t removedDevice;
    while ((removedDevice = IOIteratorNext(iterator))) {
        io_name_t deviceName;
        io_string_t pathName;
        int familyID = -1;
        NSInteger identifier = 0;
        IORegistryEntryGetName(removedDevice, deviceName);
//        NSLog(@"Device's name = %s\n", deviceName);
        IORegistryEntryGetPath(removedDevice, kIOServicePlane, pathName);
//        NSLog(@"Device's path in IOService plane = %s\n", pathName);
        CFTypeRef value = IORegistryEntrySearchCFProperty(
            removedDevice, pathName, CFSTR("Family ID"), kCFAllocatorDefault, 0);
        if (value != NULL) {
            familyID = (int)[(NSString *)value integerValue];
//            NSLog(@"Device's family ID = %@ -> %d", value, familyID);
            CFRelease(value);
        }
        value = IORegistryEntrySearchCFProperty(
            removedDevice, pathName, CFSTR("Multitouch ID"), kCFAllocatorDefault, 0);
        if (value != NULL) {
            identifier = [(NSString *)value integerValue];
//            NSLog(@"Device's multitouch ID = %@ -> %" PRIu64, value, (uint64_t)identifier);
            CFRelease(value);
        }
        IOObjectRelease(removedDevice);

        if (logLevel >= LOG_LEVEL_INFO)
            NSLog(@"Device removed: %" PRIu64 " family %d", (uint64_t)identifier, familyID);
        BOOL wasMagicMouse = deviceKindForFamilyID(familyID) == MGMultitouchDeviceMouse;
        if (wasMagicMouse && logLevel >= LOG_LEVEL_INFO)
            NSLog(@"Turning off magic mouse");
        if (_state->deviceRemovedCallback != NULL)
            _state->deviceRemovedCallback(wasMagicMouse);
    }
}

- (instancetype)initWithTrackpadCallback:(MGMultitouchContactCallback)trackpadCallback
                            mouseCallback:(MGMultitouchContactCallback)mouseCallback
                    deviceRemovedCallback:(MGMultitouchDeviceRemovedCallback)deviceRemovedCallback {
    return [self initWithTrackpadCallback:trackpadCallback
                           mouseCallback:mouseCallback
                   deviceRemovedCallback:deviceRemovedCallback
                      frameworkFunctions:productionFrameworkFunctions()
                                 context:NULL];
}

- (instancetype)initWithTrackpadCallback:(MGMultitouchContactCallback)trackpadCallback
                            mouseCallback:(MGMultitouchContactCallback)mouseCallback
                    deviceRemovedCallback:(MGMultitouchDeviceRemovedCallback)deviceRemovedCallback
                       frameworkFunctions:(MGMultitouchFrameworkFunctions)functions
                                  context:(void *)context {
    self = [super init];
    if (self != nil) {
        _state = calloc(1, sizeof(MGMultitouchDeviceLifecycleState));
        _state->framework = functions;
        _state->frameworkContext = context;
        _state->trackpadCallback = trackpadCallback;
        _state->mouseCallback = mouseCallback;
        _state->deviceRemovedCallback = deviceRemovedCallback;
        _state->observeDeviceChanges = (context == NULL);
    }
    return self;
}

- (void)start {
    _state->deviceList = _state->framework.createDeviceList(_state->frameworkContext);
    // Keep this list for callback registrations. Releasing it here crashes.
    startDeviceList(_state);
    if (!_state->observeDeviceChanges)
        return;

    /*
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, matchingDict);
    if (service) {
        hasMagicMouse = YES;
    }
    */

    _state->notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
    CFRunLoopSourceRef source = IONotificationPortGetRunLoopSource(_state->notificationPort);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);

    CFMutableDictionaryRef matching = IOServiceNameMatching("AppleMultitouchDevice");
    matching = (CFMutableDictionaryRef)CFRetain(matching);
    // Device added notification
    IOServiceAddMatchingNotification(_state->notificationPort, kIOFirstMatchNotification,
                                     matching, multitouchDeviceAdded, self,
                                     &_state->addedIterator);
    io_service_t existing;
    while ((existing = IOIteratorNext(_state->addedIterator))) {
        // Remove existing devices; already added
        IOObjectRelease(existing);
    }
    multitouchDeviceAdded(self, _state->addedIterator);

    // Device removed notification
    IOServiceAddMatchingNotification(_state->notificationPort, kIOTerminatedNotification,
                                     matching, multitouchDeviceRemoved, self,
                                     &_state->removedIterator);
    multitouchDeviceRemoved(self, _state->removedIterator);
}

- (void)rebuild {
    stopDeviceList(_state);
    _state->framework.releaseDeviceList(_state->frameworkContext, _state->deviceList);
    _state->deviceList = NULL;
    _state->framework.waitAfterStop(_state->frameworkContext);
    _state->deviceList = _state->framework.createDeviceList(_state->frameworkContext);
    startDeviceList(_state);
}

- (void)replaceDeviceWithTimer:(NSTimer *)timer {
    NSMutableDictionary *info = [timer userInfo];
    int attempt = [info[@"Attempt"] intValue];
    uint64_t identifier = [info[@"Multitouch ID"] unsignedLongLongValue];
    if (logLevel >= LOG_LEVEL_INFO)
        NSLog(@"Adding device: %" PRIu64 ", try %d", identifier, attempt);
    if (!replaceDeviceWithID(_state, identifier) && attempt < 3)
        scheduleDeviceReplacement(self, identifier, attempt + 1);
}

- (BOOL)replaceDeviceWithIDForTesting:(uint64_t)deviceID {
    return replaceDeviceWithID(_state, deviceID);
}

- (void)dealloc {
    if (_state->deviceList != NULL)
        _state->framework.releaseDeviceList(_state->frameworkContext, _state->deviceList);
    if (_state->addedIterator != IO_OBJECT_NULL)
        IOObjectRelease(_state->addedIterator);
    if (_state->removedIterator != IO_OBJECT_NULL)
        IOObjectRelease(_state->removedIterator);
    if (_state->notificationPort != NULL)
        IONotificationPortDestroy(_state->notificationPort);
    free(_state);
    [super dealloc];
}

@end
