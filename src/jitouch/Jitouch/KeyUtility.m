//
//  KeyUtility.m
//  Jitouch
//
//  Copyright 2021 Supasorn Suwajanakorn and Sukolsak Sakshuwong. All rights reserved.
//  Modified work Copyright 2026 Nathan Cheng. All rights reserved.
//

#import "KeyUtility.h"
#import "KeyEventSequence.h"
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/IOLLEvent.h>

// to suppress "'CGPostKeyboardEvent' is deprecated" warnings
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

@implementation KeyUtility

static CGKeyCode a[128];

static void languageChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    for (int i = 0; i < 128; i++)
        a[i] = (CGKeyCode)i;

    // TISGetInputSourceProperty returns a value owned by the input source, so
    // the source is held until the comparisons are done.
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (source == NULL)
        return;
    NSString *inputSource = (NSString*)TISGetInputSourceProperty(source, kTISPropertyLocalizedName);
    if ([inputSource isEqualToString:@"Dvorak"] || [inputSource isEqualToString:@"Svorak"]) {
        a[13] = 43; //w -> ,
        a[12] = 7;  //q -> x
        a[17] = 40; //t -> k
        a[4] = 38;  //h -> j
        a[15] = 31; //r -> o
        a[45] = 37; //n -> l
        a[8] = 34; //c -> i
        a[9] = 47; //v -> >
        a[31] = 1; //o ->
        a[37] = 45; //l -> n
        a[3] = 32; // f -> u
        a[40] = 17;
    } else if ([inputSource isEqualToString:@"French"]) {
        a[13] = 6;  //w -> z
        a[12] = 0;  //q -> a
    }
    CFRelease(source);
}

- (id)init {
    self = [super init];
    if (self) {
        languageChanged(NULL, NULL, NULL, NULL, NULL);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(), self, languageChanged, kTISNotifySelectedKeyboardInputSourceChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        keyMap = [[NSMutableDictionary alloc] init];
        for (CGKeyCode i = 0; i < 128; i++) {
            [keyMap setObject:[NSNumber numberWithUnsignedInt:i] forKey:[KeyUtility codeToChar:i]];
        }
    }
    return self;
}

// The notification center holds an unretained pointer to this object, so the
// observer is removed before it goes away.
- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDistributedCenter(), self,
                                       kTISNotifySelectedKeyboardInputSourceChanged, NULL);
    [keyMap release];
    [super dealloc];
}

// The key carries the complete modifier flags conventional hotkey APIs read,
// while explicit modifier transitions support listeners that track hardware-
// shaped keyboard state.
- (void)simulateKeyCode:(CGKeyCode)code ShftDown:(BOOL)shft CtrlDown:(BOOL)ctrl AltDown:(BOOL)alt CmdDown:(BOOL)cmd {
    // Each modifier includes its generic mask and device-dependent left-side
    // bit. Side-specific hotkeys test the device bits, which generic masks omit.
    CGEventFlags flags = 0;
    if (shft) flags |= kCGEventFlagMaskShift | NX_DEVICELSHIFTKEYMASK;
    if (ctrl) flags |= kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK;
    if (alt)  flags |= kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK;
    if (cmd)  flags |= kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK;

    [self simulateKeyCode:code hasKey:YES ModifierFlags:flags];
}

- (void)simulateKeyCode:(CGKeyCode)code hasKey:(BOOL)hasKey ModifierFlags:(CGEventFlags)flags {

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGKeyCode key = a[code];
    CGEventFlags physicalFlags = CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState);
    MGKeyEventStep steps[18];
    size_t count = MGPlanKeyEventSequence(key, hasKey, flags, physicalFlags, steps);
    CGEventRef events[18] = {NULL};

    // Build the full sequence before posting any part of it. A failed event
    // allocation therefore cannot leave a synthetic modifier held down.
    for (size_t i = 0; i < count; i++) {
        events[i] = CGEventCreateKeyboardEvent(source, steps[i].keyCode, steps[i].keyDown);
        if (events[i] == NULL) {
            for (size_t j = 0; j < i; j++)
                CFRelease(events[j]);
            if (source) CFRelease(source);
            return;
        }
        // A bare configured key keeps the old behavior of inheriting physical
        // modifiers. A configured chord owns the flags on its whole sequence.
        if (flags)
            CGEventSetFlags(events[i], steps[i].flags);
    }

    for (size_t i = 0; i < count; i++) {
        // Posted at the session tap. The HID tap looks more like a physical
        // key and does reach the macOS shortcut handler, but it defeats the
        // side-specific modifier bits this sequence sets, so a binding such as
        // right-Control plus Space stops reaching an application that listens
        // for that exact chord. A binding for a macOS view uses its built-in
        // action instead, which asks macOS directly and needs no keystroke.
        CGEventPost(kCGSessionEventTap, events[i]);
        CFRelease(events[i]);
    }
    if (source) CFRelease(source);
}

- (void) simulateKey:(NSString *)key ShftDown:(BOOL)shft CtrlDown:(BOOL)ctrl AltDown:(BOOL)alt CmdDown:(BOOL)cmd {
    CGKeyCode km = [(NSNumber *)[keyMap objectForKey:key] unsignedIntValue];
    [self simulateKeyCode:km ShftDown:shft CtrlDown:ctrl AltDown:alt CmdDown:cmd];
}

- (void)simulateSystemKey:(int)key {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSEvent *event = [NSEvent otherEventWithType:NSSystemDefined location:NSZeroPoint modifierFlags:0xa00 timestamp:0 windowNumber:0 context:NULL subtype:8 data1:(key << 16) | (0xa00) data2:-1];
    CGEventPost(kCGSessionEventTap, [event CGEvent]);

    NSEvent *event2 = [NSEvent otherEventWithType:NSSystemDefined location:NSZeroPoint modifierFlags:0xb00 timestamp:0 windowNumber:0 context:NULL subtype:8 data1:(key << 16) | (0xb00) data2:-1];
    CGEventPost(kCGSessionEventTap, [event2 CGEvent]);

    [pool release];
}

- (CGKeyCode)charToCode:(NSString*) chr {
    return [[keyMap objectForKey:chr] unsignedIntValue];
}

+ (NSString *)codeToChar:(CGKeyCode)keyCode {
    NSString *chr;
    if (keyCode == 123) { //left
        chr = @"←";
    } else if (keyCode == 124) { //right
        chr = @"→";
    } else if (keyCode == 125) { //down
        chr = @"↓";
    } else if (keyCode == 126) { //up
        chr = @"↑";
    } else if (keyCode == 36) { //return
        chr = @"↩";
    } else if (keyCode == 48) { //tab
        chr = @"Tab";
    } else if (keyCode == 49) { //space
        chr = @"Space";
    } else if (keyCode == 51) { //delete
        chr = @"⌫";
    } else if (keyCode == 53) { //escape
        chr = @"⎋";
    } else if (keyCode == 117) { //forward delete
        chr = @"⌦";
    } else if (keyCode == 76) { //enter
        chr = @"⌅";
    } else if (keyCode == 116) { //page up
        chr = @"Page Up";
    } else if (keyCode == 121) { //page down
        chr = @"Page Down";
    } else if (keyCode == 115) { //home
        chr = @"Home";
    } else if (keyCode == 119) { //end
        chr = @"End";
    } else if (keyCode == 122) { //
        chr = @"F1";
    } else if (keyCode == 120) { //
        chr = @"F2";
    } else if (keyCode == 99) { //
        chr = @"F3";
    } else if (keyCode == 118) { //
        chr = @"F4";
    } else if (keyCode == 96) { //
        chr = @"F5";
    } else if (keyCode == 97) { //
        chr = @"F6";
    } else if (keyCode == 98) { //
        chr = @"F7";
    } else if (keyCode == 100) { //
        chr = @"F8";
    } else if (keyCode == 101) { //
        chr = @"F9";
    } else if (keyCode == 109) { //
        chr = @"F10";
    } else if (keyCode == 103) { //
        chr = @"F11";
    } else if (keyCode == 111) { //
        chr = @"F12";
    } else if (keyCode == 33) { //
        chr = @"[";
    } else if (keyCode == 30) { //
        chr = @"]";

    } else {
        switch (keyCode) {
            case 0:
                chr = @"A"; break;
            case 11:
                chr = @"B"; break;
            case 8:
                chr = @"C"; break;
            case 2:
                chr = @"D"; break;
            case 14:
                chr = @"E"; break;
            case 3:
                chr = @"F"; break;
            case 5:
                chr = @"G"; break;
            case 4:
                chr = @"H"; break;
            case 34:
                chr = @"I"; break;
            case 38:
                chr = @"J"; break;
            case 40:
                chr = @"K"; break;
            case 37:
                chr = @"L"; break;
            case 46:
                chr = @"M"; break;
            case 45:
                chr = @"N"; break;
            case 31:
                chr = @"O"; break;
            case 35:
                chr = @"P"; break;
            case 12:
                chr = @"Q"; break;
            case 15:
                chr = @"R"; break;
            case 1:
                chr = @"S"; break;
            case 17:
                chr = @"T"; break;
            case 32:
                chr = @"U"; break;
            case 9:
                chr = @"V"; break;
            case 13:
                chr = @"W"; break;
            case 7:
                chr = @"X"; break;
            case 16:
                chr = @"Y"; break;
            case 6:
                chr = @"Z"; break;
            default:
                chr = [NSString stringWithFormat:@"%d", keyCode];
                break;
        }
    }
    return chr;
}

@end
