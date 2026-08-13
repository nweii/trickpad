//
//  Gesture.h
//  Jitouch
//
//  Copyright 2021 Supasorn Suwajanakorn and Sukolsak Sakshuwong. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class MGMultitouchDeviceLifecycle;

@interface Gesture : NSObject {
    MGMultitouchDeviceLifecycle *multitouchDevices;
}

- (id)init;

- (void)reload;

@end

void turnOffGestures(void);
void cancelPendingGestureSequences(void);
