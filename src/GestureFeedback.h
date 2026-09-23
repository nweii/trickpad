// Shows a short message from Trickpad in a bubble below its menu bar icon,
// without activating Trickpad or taking keyboard focus from the application
// in use.

#import <AppKit/AppKit.h>

// Sets the menu bar item the bubble points at. Pass nil when the icon is
// hidden; messages are then dropped. Call on the main thread.
void MGGestureFeedbackSetAnchor(NSStatusItem *item);

// Where a click on a bubble takes the user: the place the fix belongs.
typedef NS_ENUM(NSInteger, MGFeedbackAction) {
    MGFeedbackActionNone,
    MGFeedbackActionEditSettings,
    MGFeedbackActionAccessibilitySettings,
};

// Sets what a click does for action. Call on the main thread.
void MGGestureFeedbackSetActionHandler(MGFeedbackAction action, dispatch_block_t handler);

// Shows a bold title and a plain detail line for a few seconds, replacing any
// message already showing. Either may be nil. With an action, a dimmed last
// line says where a click leads, and a click goes there; otherwise a click
// only closes the bubble. Safe to call from any thread.
void MGShowGestureFeedback(NSString *title, NSString *detail, MGFeedbackAction action);
