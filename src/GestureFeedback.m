// Presents gesture feedback in a popover anchored to the menu bar icon. The
// popover closes itself after a few seconds or when clicked, and showing it
// never activates Trickpad, so the next keystroke still reaches the
// application the user is working in. A click is deliberate, so opening the
// settings from one may bring an editor forward.

#import "GestureFeedback.h"

static const NSTimeInterval kVisibleSeconds = 5.0;
static const CGFloat kMaximumTextWidth = 280.0;
static const CGFloat kPadding = 12.0;

static NSStatusItem *anchorItem = nil;
static NSPopover *popover = nil;
static NSTextField *titleLabel = nil;
static NSTextField *detailLabel = nil;
static NSTextField *hintLabel = nil;
static dispatch_block_t editSettingsHandler = nil;
static dispatch_block_t accessibilityHandler = nil;
static MGFeedbackAction currentAction = MGFeedbackActionNone;
// Identifies the latest message, so an earlier message's close timer cannot
// close a later one.
static NSUInteger messageGeneration = 0;

@interface MGGestureFeedbackController : NSViewController
@end

@implementation MGGestureFeedbackController

- (void)loadView {
    NSView *view = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    titleLabel = [[NSTextField wrappingLabelWithString:@""] retain];
    [titleLabel setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
    detailLabel = [[NSTextField wrappingLabelWithString:@""] retain];
    hintLabel = [[NSTextField wrappingLabelWithString:@""] retain];
    [hintLabel setTextColor:[NSColor secondaryLabelColor]];
    [hintLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    for (NSTextField *label in @[titleLabel, detailLabel, hintLabel]) {
        [label setPreferredMaxLayoutWidth:kMaximumTextWidth];
        [label setSelectable:NO];
        [view addSubview:label];
    }
    NSClickGestureRecognizer *click = [[[NSClickGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismiss:)] autorelease];
    [view addGestureRecognizer:click];
    [self setView:view];
}

- (void)dismiss:(id)sender {
    [popover performClose:nil];
    dispatch_block_t handler = currentAction == MGFeedbackActionEditSettings ? editSettingsHandler
        : currentAction == MGFeedbackActionAccessibilitySettings ? accessibilityHandler : nil;
    if (handler != nil)
        handler();
}

@end

void MGGestureFeedbackSetActionHandler(MGFeedbackAction action, dispatch_block_t handler) {
    dispatch_block_t *slot = action == MGFeedbackActionEditSettings ? &editSettingsHandler
        : action == MGFeedbackActionAccessibilitySettings ? &accessibilityHandler : NULL;
    if (slot == NULL)
        return;
    [*slot release];
    *slot = [handler copy];
}

static NSString *hintForAction(MGFeedbackAction action) {
    switch (action) {
        case MGFeedbackActionEditSettings: return editSettingsHandler ? @"Click to edit settings." : nil;
        case MGFeedbackActionAccessibilitySettings:
            return accessibilityHandler ? @"Click to open Accessibility settings." : nil;
        case MGFeedbackActionNone: return nil;
    }
    return nil;
}

void MGGestureFeedbackSetAnchor(NSStatusItem *item) {
    if (item == anchorItem)
        return;
    if (item == nil && [popover isShown])
        [popover close];
    [anchorItem release];
    anchorItem = [item retain];
}

static const CGFloat kLineGap = 4.0;

static void showOnMain(NSString *title, NSString *detail, MGFeedbackAction action) {
    NSStatusBarButton *button = [anchorItem button];
    if (button == nil || [button window] == nil)
        return;
    if (popover == nil) {
        popover = [[NSPopover alloc] init];
        // Application-defined behavior keeps the popover from closing, or
        // activating Trickpad, in response to clicks elsewhere.
        [popover setBehavior:NSPopoverBehaviorApplicationDefined];
        [popover setAnimates:YES];
        [popover setContentViewController:[[[MGGestureFeedbackController alloc] init] autorelease]];
    }
    [[popover contentViewController] view];
    [titleLabel setStringValue:title ?: @""];
    [detailLabel setStringValue:detail ?: @""];
    NSString *hint = hintForAction(action);
    currentAction = hint != nil ? action : MGFeedbackActionNone;
    [hintLabel setStringValue:hint ?: @""];
    // Views are laid out from the bottom up: hint, then detail, then title.
    CGFloat y = kPadding;
    CGFloat width = 0;
    for (NSTextField *label in @[hintLabel, detailLabel, titleLabel]) {
        BOOL visible = [[label stringValue] length] > 0;
        [label setHidden:!visible];
        if (!visible)
            continue;
        if (y > kPadding)
            y += kLineGap;
        NSSize size = [label fittingSize];
        [label setFrame:NSMakeRect(kPadding, y, size.width, size.height)];
        y += size.height;
        width = MAX(width, size.width);
    }
    [popover setContentSize:NSMakeSize(width + 2 * kPadding, y + kPadding)];
    if (![popover isShown])
        [popover showRelativeToRect:[button bounds] ofView:button preferredEdge:NSRectEdgeMinY];

    NSUInteger shown = ++messageGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVisibleSeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (messageGeneration == shown && [popover isShown])
            [popover performClose:nil];
    });
}

void MGShowGestureFeedback(NSString *title, NSString *detail, MGFeedbackAction action) {
    if ([title length] == 0 && [detail length] == 0)
        return;
    NSString *copiedTitle = [[title copy] autorelease];
    NSString *copiedDetail = [[detail copy] autorelease];
    dispatch_async(dispatch_get_main_queue(), ^{
        showOnMain(copiedTitle, copiedDetail, action);
    });
}
