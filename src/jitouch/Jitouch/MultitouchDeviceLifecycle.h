// Owns MultitouchSupport device discovery, callback registration, and rebuilds.
// Gesture recognition receives contact frames through the two callbacks only.

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

typedef CFTypeRef *MGMultitouchDeviceRef;
typedef struct MGMultitouchContact MGMultitouchContact;
typedef int (*MGMultitouchContactCallback)(MGMultitouchDeviceRef device,
                                            MGMultitouchContact *contacts,
                                            int contactCount,
                                            double timestamp,
                                            int frame);
typedef void (*MGMultitouchDeviceRemovedCallback)(int familyID);

@interface MGMultitouchDeviceLifecycle : NSObject

- (instancetype)initWithTrackpadCallback:(MGMultitouchContactCallback)trackpadCallback
                            mouseCallback:(MGMultitouchContactCallback)mouseCallback
                    deviceRemovedCallback:(MGMultitouchDeviceRemovedCallback)deviceRemovedCallback;
- (void)start;
- (void)rebuild;

@end
