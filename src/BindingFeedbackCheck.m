// Checks binding feedback wording: titles name the gesture and binding kind,
// URL messages never quote resolved values, and script messages name the file.

#import <Foundation/Foundation.h>
#import "BindingFeedback.h"

static int failures = 0;

static void expect(NSString *actual, NSString *expected, const char *message) {
    if ([actual isEqualToString:expected])
        return;
    fprintf(stderr, "FAIL  %s\n      got %s\n", message, [actual UTF8String]);
    failures++;
}

int main(void) {
    @autoreleasepool {
        expect(MGBindingFailureTitle(@"Tap with three fingers", @"menu", NO),
               @"The “Tap with three fingers” menu binding didn’t run",
               "a title names the gesture and binding kind");
        expect(MGBindingFailureTitle(@"Tap with three fingers", @"menu", YES),
               @"The “Tap with three fingers” menu binding may not have run",
               "an unconfirmed result is not called a failure");
        expect(MGBindingFailureTitle(nil, nil, NO), @"A binding didn’t run",
               "a title without a gesture or kind still reads naturally");
        expect(MGURLFailureMessage(@"raycast-x://extensions/raycast/snippets", nil),
               @"No app on this Mac opens “raycast-x:” links.",
               "an unopened URL names only its scheme");
        expect(MGURLFailureMessage(@"things:///add?title={{clipboard|urlencode}}", @"the clipboard is empty"),
               @"Trickpad couldn’t build the link from “things:///add?title={{clipboard|urlencode}}”: the clipboard is empty.",
               "an unresolved URL quotes the configured value and its problem");
        expect(MGScriptLaunchFailureMessage(@"/Users/me/bin/sync-notes", @"Script file is not executable"),
               @"Trickpad couldn’t start “sync-notes”: Script file is not executable.",
               "a launch failure names the script file and reason");
        expect(MGScriptLaunchFailureMessage(@"/Users/me/bin/sync-notes", @"Permission denied."),
               @"Trickpad couldn’t start “sync-notes”: Permission denied.",
               "a reason's own period is not doubled");
        expect(MGScriptExitMessage(@"/Users/me/bin/sync-notes", 2),
               @"“sync-notes” stopped with exit code 2.",
               "a nonzero exit names the script and code");
        if ([MGClipboardDeniedMessage() rangeOfString:@"Paste from Other Apps"].location == NSNotFound) {
            fprintf(stderr, "FAIL  the clipboard message names the System Settings pane\n");
            failures++;
        }
        if ([MGKeystrokesNeedAccessibilityMessage() rangeOfString:@"Accessibility"].location == NSNotFound) {
            fprintf(stderr, "FAIL  the keystroke message names its cause\n");
            failures++;
        }
    }
    if (failures > 0)
        return 1;
    printf("binding feedback: ok\n");
    return 0;
}
