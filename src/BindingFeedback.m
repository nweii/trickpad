// Composes binding feedback text. Quotes follow their source: configured
// values keep the user's spelling, and nothing resolved at dispatch time, such
// as clipboard contents, is quoted.

#import "BindingFeedback.h"

NSString *MGBindingFailureTitle(NSString *gestureName, NSString *kind, BOOL mayHaveRun) {
    NSString *binding = [kind length] > 0 ? [kind stringByAppendingString:@" binding"] : @"binding";
    NSString *subject = [gestureName length] > 0
        ? [NSString stringWithFormat:@"The “%@” %@", gestureName, binding]
        : [@"A " stringByAppendingString:binding];
    return [subject stringByAppendingString:mayHaveRun ? @" may not have run" : @" didn’t run"];
}

NSString *MGURLFailureMessage(NSString *configuredURL, NSString *resolutionProblem) {
    if ([resolutionProblem length] > 0)
        return [NSString stringWithFormat:@"Trickpad couldn’t build the link from “%@”: %@.",
                configuredURL, resolutionProblem];
    NSRange colon = [configuredURL rangeOfString:@":"];
    if (colon.location == NSNotFound)
        return [NSString stringWithFormat:@"No app on this Mac opens “%@”.", configuredURL];
    return [NSString stringWithFormat:@"No app on this Mac opens “%@” links.",
            [configuredURL substringToIndex:NSMaxRange(colon)]];
}

NSString *MGScriptLaunchFailureMessage(NSString *scriptPath, NSString *reason) {
    NSString *name = [scriptPath lastPathComponent];
    if ([reason length] == 0)
        return [NSString stringWithFormat:@"Trickpad couldn’t start “%@”.", name];
    return [NSString stringWithFormat:@"Trickpad couldn’t start “%@”: %@.", name,
            [reason hasSuffix:@"."] ? [reason substringToIndex:[reason length] - 1] : reason];
}

NSString *MGScriptExitMessage(NSString *scriptPath, int status) {
    return [NSString stringWithFormat:@"“%@” stopped with exit code %d.",
            [scriptPath lastPathComponent], status];
}

NSString *MGClipboardRequestTitle(void) {
    return @"Trickpad is reading the clipboard";
}

NSString *MGClipboardRequestMessage(NSString *gestureName) {
    NSString *binding = [gestureName length] > 0
        ? [NSString stringWithFormat:@"Your “%@” URL binding", gestureName] : @"A URL binding";
    return [binding stringByAppendingString:@" uses the clipboard. To stop macOS asking each time, "
            @"choose Allow in Paste from Other Apps."];
}

NSString *MGClipboardDeniedMessage(void) {
    return @"This binding uses the clipboard, and macOS is set to deny Trickpad clipboard access. "
           @"Allow it in System Settings > Privacy & Security > Paste from Other Apps.";
}

NSString *MGKeystrokesNeedAccessibilityMessage(void) {
    return @"Trickpad needs Accessibility access to send keystrokes. Turn it on in "
           @"System Settings > Privacy & Security > Accessibility.";
}
