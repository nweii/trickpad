//
//  ConfigCheck.m
//  Trickpad
//
//  Copyright 2026 Nathan Cheng. All rights reserved.
//
//  Asserts that a configuration file parses into the keycodes and flags the
//  engine will dispatch. Run with scripts/check.sh.
//

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import "Config.h"

static int failures = 0;

static void fail(NSString *what, id expected, id actual) {
    fprintf(stderr, "FAIL  %s\n      expected %s\n      got      %s\n",
            [what UTF8String], [[expected description] UTF8String],
            [[actual description] UTF8String]);
    failures++;
}

// Finds a binding by its engine gesture name in parsed settings.
static NSDictionary *bindingFor(NSDictionary *settings, NSString *deviceKey, NSString *gesture) {
    for (NSDictionary *app in [settings objectForKey:deviceKey]) {
        for (NSDictionary *g in [app objectForKey:@"Gestures"]) {
            if ([[g objectForKey:@"Gesture"] isEqualToString:gesture])
                return g;
        }
    }
    return nil;
}

static NSDictionary *bindingForApplication(NSDictionary *settings, NSString *deviceKey,
                                           NSString *application, NSString *gesture) {
    for (NSDictionary *app in [settings objectForKey:deviceKey]) {
        if (![[app objectForKey:@"Application"] isEqualToString:application])
            continue;
        for (NSDictionary *g in [app objectForKey:@"Gestures"]) {
            if ([[g objectForKey:@"Gesture"] isEqualToString:gesture])
                return g;
        }
    }
    return nil;
}

// Most semantic checks predate the TOML surface. Convert their compact fixture
// spelling here so each assertion continues to exercise the production parser.
static NSString *TOMLFixture(NSString *text) {
    NSMutableString *result = [NSMutableString string];
    NSString *section = nil;
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = raw;
        if ([line hasPrefix:@"[mouse \""] && [line hasSuffix:@"\"]"]) {
            NSString *app = [line substringWithRange:NSMakeRange(8, [line length] - 10)];
            line = [NSString stringWithFormat:@"[MOUSE.\"%@\"]", app];
            section = @"MOUSE";
        } else if ([line hasPrefix:@"[trackpad \""] && [line hasSuffix:@"\"]"]) {
            NSString *app = [line substringWithRange:NSMakeRange(11, [line length] - 13)];
            line = [NSString stringWithFormat:@"[TRACKPAD.\"%@\"]", app];
            section = @"TRACKPAD";
        } else if ([[line lowercaseString] isEqualToString:@"[mouse]"]) {
            line = @"[MOUSE]";
            section = @"MOUSE";
        } else if ([[line lowercaseString] isEqualToString:@"[trackpad]"]) {
            line = @"[TRACKPAD]";
            section = @"TRACKPAD";
        } else if ([[line lowercaseString] isEqualToString:@"[general]"]) {
            line = @"[GENERAL]";
            section = @"GENERAL";
        } else if (([section isEqualToString:@"MOUSE"] ||
                    [section isEqualToString:@"TRACKPAD"])) {
            NSRange brace = [line rangeOfString:@"{"];
            NSRange equals = [line rangeOfString:@"="];
            if (brace.location != NSNotFound &&
                (equals.location == NSNotFound || brace.location < equals.location)) {
                line = [line stringByReplacingCharactersInRange:NSMakeRange(brace.location, 1)
                                                      withString:@"= {"];
            } else if (equals.location != NSNotFound) {
                NSString *prefix = [line substringToIndex:equals.location + 1];
                NSString *valueAndComment = [[line substringFromIndex:equals.location + 1]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSRange comment = [valueAndComment rangeOfString:@" #"];
                NSString *value = comment.location == NSNotFound ? valueAndComment :
                    [valueAndComment substringToIndex:comment.location];
                NSString *suffix = comment.location == NSNotFound ? @"" :
                    [valueAndComment substringFromIndex:comment.location];
                if (![value hasPrefix:@"\""] && ![value hasPrefix:@"{"]) {
                    NSData *json = [NSJSONSerialization dataWithJSONObject:@[value] options:0 error:NULL];
                    NSString *array = [[[NSString alloc] initWithData:json
                                                              encoding:NSUTF8StringEncoding] autorelease];
                    NSString *quoted = [[array substringWithRange:NSMakeRange(1, [array length] - 2)]
                        stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
                    line = [NSString stringWithFormat:@"%@ %@%@", prefix, quoted, suffix];
                }
            }
        } else if ([section isEqualToString:@"GENERAL"] &&
                   [line hasPrefix:@"dominant-hand = "] &&
                   [line rangeOfString:@"\""].location == NSNotFound) {
            NSString *value = [line substringFromIndex:[@"dominant-hand = " length]];
            line = [NSString stringWithFormat:@"dominant-hand = \"%@\"", value];
        }
        [result appendFormat:@"%@\n", line];
    }
    return result;
}

static NSDictionary *parse(NSString *text) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mg-check.toml"];
    [TOMLFixture(text) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return [Config settingsFromFile:path];
}

static NSDictionary *parseWithProblems(NSString *text, NSArray **problems) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mg-check.toml"];
    [TOMLFixture(text) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return [Config settingsFromFile:path problems:problems];
}

static NSDictionary *parseRawTOML(NSString *text, NSArray **problems) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mg-check.toml"];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return [Config settingsFromFile:path problems:problems];
}

static ConfigResult *parseResult(NSString *text) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mg-check.toml"];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return [Config resultFromFile:path];
}

static NSString *section(NSString *text, NSString *start, NSString *end) {
    NSRange startRange = [text rangeOfString:start];
    if (startRange.location == NSNotFound)
        return nil;
    NSUInteger bodyStart = NSMaxRange(startRange);
    NSRange searchRange = NSMakeRange(bodyStart, [text length] - bodyStart);
    NSRange endRange = [text rangeOfString:end options:0 range:searchRange];
    NSUInteger bodyEnd = endRange.location == NSNotFound ? [text length] : endRange.location;
    return [text substringWithRange:NSMakeRange(bodyStart, bodyEnd - bodyStart)];
}

static void expectDeviceSlugs(NSString *label, NSString *text, NSDictionary *slugs) {
    if (text == nil) {
        fail(label, @"a device section", @"missing");
        return;
    }
    for (NSString *slug in slugs) {
        if ([text rangeOfString:slug].location == NSNotFound)
            fail([NSString stringWithFormat:@"%@ documents %@", label, slug], @"present", @"missing");
    }
}

static void expectKey(NSString *label, NSString *value, int keycode, NSUInteger flags) {
    NSString *conf = [NSString stringWithFormat:@"[mouse]\nhold-right-tap-left = %@\n", value];
    NSDictionary *g = bindingFor(parse(conf), @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap");
    if (g == nil) {
        fail(label, @"a binding", @"none");
        return;
    }
    if ([[g objectForKey:@"KeyCode"] intValue] != keycode)
        fail([label stringByAppendingString:@" keycode"], @(keycode), [g objectForKey:@"KeyCode"]);
    if ([[g objectForKey:@"ModifierFlags"] unsignedIntegerValue] != flags)
        fail([label stringByAppendingString:@" flags"], @(flags), [g objectForKey:@"ModifierFlags"]);
}

static void expectKeyDisplay(NSString *label, NSString *value, NSString *display) {
    NSString *conf = [NSString stringWithFormat:@"[mouse]\nhold-right-tap-left = %@\n", value];
    NSDictionary *g = bindingFor(parse(conf), @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap");
    NSString *actual = g == nil ? nil : [Config keystrokeDisplayNameForBinding:g];
    if (![actual isEqualToString:display])
        fail(label, display, actual ?: @"none");
}

static NSArray *directDispatchLines(NSString *source) {
    NSMutableArray *lines = [NSMutableArray array];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    BOOL inBlockComment = NO;
    for (NSString *line in [source componentsSeparatedByCharactersInSet:
                            [NSCharacterSet newlineCharacterSet]]) {
        NSMutableString *code = [NSMutableString string];
        NSUInteger cursor = 0;
        while (cursor < [line length]) {
            if (inBlockComment) {
                NSRange end = [line rangeOfString:@"*/" options:0
                                            range:NSMakeRange(cursor, [line length] - cursor)];
                if (end.location == NSNotFound) {
                    cursor = [line length];
                    continue;
                }
                inBlockComment = NO;
                cursor = NSMaxRange(end);
                continue;
            }
            NSRange remainder = NSMakeRange(cursor, [line length] - cursor);
            NSRange lineComment = [line rangeOfString:@"//" options:0 range:remainder];
            NSRange blockComment = [line rangeOfString:@"/*" options:0 range:remainder];
            NSUInteger nextComment = MIN(
                lineComment.location == NSNotFound ? [line length] : lineComment.location,
                blockComment.location == NSNotFound ? [line length] : blockComment.location);
            [code appendString:[line substringWithRange:
                                NSMakeRange(cursor, nextComment - cursor)]];
            if (nextComment == [line length]) {
                cursor = [line length];
            } else if (blockComment.location == nextComment) {
                inBlockComment = YES;
                cursor = NSMaxRange(blockComment);
            } else {
                cursor = [line length];
            }
        }
        NSString *trimmed = [code stringByTrimmingCharactersInSet:whitespace];
        if ([trimmed hasPrefix:@"static void dispatchCommand("] ||
            [trimmed rangeOfString:@"dispatchCommand("].location == NSNotFound)
            continue;
        [lines addObject:trimmed];
    }
    return lines;
}

static NSArray *unexpectedDirectDispatchLines(NSString *source) {
    NSSet *allowed = [NSSet setWithArray:@[
        @"dispatchCommand(gesture, device);",
        @"dispatchCommand(commandString, CHARRECOGNITION);",
        @"dispatchCommand(gesture, MAGICMOUSE);",
    ]];
    NSMutableArray *unexpected = [NSMutableArray array];
    for (NSString *line in directDispatchLines(source)) {
        if (![allowed containsObject:line])
            [unexpected addObject:line];
    }
    return unexpected;
}

static NSUInteger directDispatchLineCount(NSString *source, NSString *line) {
    NSUInteger count = 0;
    for (NSString *candidate in directDispatchLines(source)) {
        if ([candidate isEqualToString:line])
            count++;
    }
    return count;
}

int main(void) {
    @autoreleasepool {
        NSUInteger CMD = kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK;
        NSUInteger SHIFT = kCGEventFlagMaskShift | NX_DEVICELSHIFTKEYMASK;
        NSUInteger CTRL = kCGEventFlagMaskControl | NX_DEVICELCTLKEYMASK;

        NSArray *tomlProblems = nil;
        NSDictionary *tomlSettings = parseRawTOML(
            @"[MOUSE]\n\nhold-right-tap-left = \"cmd+shift+a\"\n\n"
             @"[TRACKPAD.\"Final Cut Pro\"]\n\n"
             @"three-finger-tap = { action = \"url:example://a/#section\", defer = true }\n",
            &tomlProblems);
        if (tomlSettings == nil || [tomlProblems count] != 0)
            fail(@"standard TOML loads", @"settings without problems",
                 tomlSettings ?: tomlProblems);
        NSDictionary *tomlAppBinding = bindingForApplication(
            tomlSettings, @"TrackpadCommands", @"Final Cut Pro", @"Three-Finger Tap");
        if (![[tomlAppBinding objectForKey:@"OpenURL"] isEqualToString:@"example://a/#section"] ||
            ![[tomlAppBinding objectForKey:@"Defer"] boolValue])
            fail(@"TOML application table and inline options",
                 @"a deferred URL binding", tomlAppBinding ?: @"missing");

        tomlSettings = parseRawTOML(
            @"[MOUSE]\n"
             @"two-finger-click = [\"ctrl+space\", \"wait:120\", \"escape\"]\n",
            &tomlProblems);
        NSDictionary *sequenceBinding = bindingFor(
            tomlSettings, @"MagicMouseCommands", @"Two-Finger Click");
        NSArray *sequence = [sequenceBinding objectForKey:@"Sequence"];
        if ([tomlProblems count] != 0 || [sequence count] != 3 ||
            [[[sequence objectAtIndex:0] objectForKey:@"KeyCode"] intValue] != 49 ||
            ![[[sequence objectAtIndex:1] objectForKey:@"WaitMilliseconds"] isEqual:@120] ||
            [[[sequence objectAtIndex:2] objectForKey:@"KeyCode"] intValue] != 53)
            fail(@"TOML array binding preserves parsed steps in order",
                 @"Control-Space, 120 ms, Escape", sequenceBinding ?: tomlProblems);

        tomlSettings = parseRawTOML(
            @"[TRACKPAD]\n"
             @"three-finger-tap = { action = [\"mission-control\", \"url:things:///show\"], haptic = false }\n"
             @"[TRACKPAD.\"Final Cut Pro\"]\n"
             @"three-finger-tap = [\"sound:Glass\", \"say:done\"]\n",
            &tomlProblems);
        sequenceBinding = bindingFor(
            tomlSettings, @"TrackpadCommands", @"Three-Finger Tap");
        sequence = [sequenceBinding objectForKey:@"Sequence"];
        NSDictionary *scopedSequenceBinding = bindingForApplication(
            tomlSettings, @"TrackpadCommands", @"Final Cut Pro", @"Three-Finger Tap");
        NSArray *scopedSequence = [scopedSequenceBinding objectForKey:@"Sequence"];
        if ([tomlProblems count] != 0 || [sequence count] != 2 ||
            ![[[sequence objectAtIndex:0] objectForKey:@"Command"] isEqualToString:@"Mission Control"] ||
            ![[[sequence objectAtIndex:1] objectForKey:@"OpenURL"] isEqualToString:@"things:///show"] ||
            [sequenceBinding objectForKey:@"HapticFeedback"] == nil ||
            [[sequenceBinding objectForKey:@"HapticFeedback"] boolValue] ||
            ![[[scopedSequence objectAtIndex:0] objectForKey:@"PlaySound"] isEqualToString:@"Glass"] ||
            ![[[scopedSequence objectAtIndex:1] objectForKey:@"SpeakText"] isEqualToString:@"done"])
            fail(@"expanded and application-scoped sequences reuse value forms",
                 @"action, URL, sound, and speech steps", tomlSettings ?: tomlProblems);

        NSDictionary *invalidSequences = @{
            @"[\"wait:0\", \"escape\"]": @"element 1",
            @"[\"wait:1.5\", \"escape\"]": @"whole number",
            @"[\"wait:2000\", \"wait:1001\", \"escape\"]": @"3000 ms",
            @"[\"escape\", \"not-a-key\"]": @"element 2",
            @"[\"off\", \"escape\"]": @"off is not an action",
            @"[]": @"at least one element",
            @"[\"escape\", 12]": @"element 2 must be a binding string",
        };
        for (NSString *value in invalidSequences) {
            NSArray *problems = nil;
            NSString *configuration = [NSString stringWithFormat:
                @"[MOUSE]\ntwo-finger-click = %@\none-finger-tap = \"return\"\n", value];
            NSDictionary *parsed = parseRawTOML(configuration, &problems);
            NSDictionary *valid = bindingFor(parsed, @"MagicMouseCommands", @"One-Finger Tap");
            NSString *reported = [problems count] > 0 ? [problems objectAtIndex:0] : @"";
            if (bindingFor(parsed, @"MagicMouseCommands", @"Two-Finger Click") != nil ||
                valid == nil || [reported rangeOfString:[invalidSequences objectForKey:value]].location == NSNotFound)
                fail([@"invalid sequence is reported and skipped: " stringByAppendingString:value],
                     [invalidSequences objectForKey:value], reported);
        }

        tomlSettings = parseRawTOML(
            @"[MOUSE]\n"
             @"two-finger-click = [\"wait:1000\", \"wait:2000\", \"escape\"]\n",
            &tomlProblems);
        if ([tomlProblems count] != 0 ||
            bindingFor(tomlSettings, @"MagicMouseCommands", @"Two-Finger Click") == nil)
            fail(@"sequence accepts waits totaling the cap", @"a binding", tomlProblems);

        NSArray *standaloneWaitProblems = nil;
        tomlSettings = parseRawTOML(
            @"[MOUSE]\ntwo-finger-click = \"wait:100\"\n", &standaloneWaitProblems);
        NSString *standaloneWaitProblem = [standaloneWaitProblems count] > 0
            ? [standaloneWaitProblems objectAtIndex:0] : @"";
        if (bindingFor(tomlSettings, @"MagicMouseCommands", @"Two-Finger Click") != nil ||
            [standaloneWaitProblem rangeOfString:@"only inside a sequence array"].location == NSNotFound)
            fail(@"wait outside an array is reported and skipped",
                 @"sequence-only diagnostic", standaloneWaitProblem);

        ConfigResult *sourceResult = parseResult(
            @"[MOUSE]\n"
             @"two-finger-click = \"escape\" # close the overlay\n"
             @"made-up-gesture = \"return\" # needs a recognizer\n"
             @"[TRACKPAD]\n"
             @"three-finger-click = \"escape\" # global trackpad note\n"
             @"[TRACKPAD.\"Safari\"]\n"
             @"three-finger-click = \"off\" # keep Safari's click\n"
             @"[TRACKPAD.\"Chrome\"]\n"
             @"three-finger-click = { haptic = false }\n");
        NSDictionary *commentedBinding = bindingFor(
            [sourceResult settings], @"MagicMouseCommands", @"Two-Finger Click");
        NSString *comment = [sourceResult commentForDevice:@"Mouse"
                                               application:@"All Applications"
                                                   gesture:@"Two-Finger Click"];
        if (![comment isEqualToString:@"close the overlay"] ||
            [commentedBinding objectForKey:@"SourceComment"] != nil)
            fail(@"configuration result carries binding comments",
                 @"comment outside the settings dictionary", comment ?: @"missing");
        NSDictionary *diagnostic = [[sourceResult diagnostics] firstObject];
        if (![[diagnostic objectForKey:@"Device"] isEqualToString:@"Mouse"] ||
            ![[diagnostic objectForKey:@"Title"] hasPrefix:@"made-up-gesture"] ||
            ![[diagnostic objectForKey:@"Reason"] containsString:@"no mouse gesture"] ||
            ![[diagnostic objectForKey:@"Message"] containsString:@"line 3"])
            fail(@"configuration result carries structured skipped binding details",
                 @"Mouse, source title, reason, and message", diagnostic ?: @"missing");
        NSDictionary *offBinding = bindingForApplication(
            [sourceResult settings], @"TrackpadCommands", @"Safari", @"Three-Finger Click");
        comment = [sourceResult commentForDevice:@"Trackpad"
                                     application:@"Safari"
                                         gesture:@"Three-Finger Click"];
        if (offBinding == nil ||
            ![comment isEqualToString:@"keep Safari's click"] ||
            [[offBinding objectForKey:@"Enable"] boolValue])
            fail(@"configuration result preserves scoped Off comments",
                 @"disabled binding with its comment", offBinding ?: @"missing");
        comment = [sourceResult commentForDevice:@"Trackpad"
                                     application:@"Chrome"
                                         gesture:@"Three-Finger Click"];
        if (comment != nil)
            fail(@"an uncommented app override does not inherit the global comment",
                 @"no comment", comment);

        // CRLF endings: a comment must not smuggle its carriage return into the
        // reconstructed text, where it becomes a phantom line that inflates the
        // reported line number of every diagnostic after it.
        ConfigResult *crlfResult = parseResult(
            @"[MOUSE]\r\n"
             @"two-finger-click = \"escape\" # close the overlay\r\n"
             @"made-up-gesture = \"return\"\r\n");
        NSString *crlfComment = [crlfResult commentForDevice:@"Mouse"
                                                 application:@"All Applications"
                                                     gesture:@"Two-Finger Click"];
        NSDictionary *crlfDiagnostic = [[crlfResult diagnostics] firstObject];
        if (![crlfComment isEqualToString:@"close the overlay"] ||
            ![[crlfDiagnostic objectForKey:@"Message"] containsString:@"line 3"])
            fail(@"CRLF comments keep line numbers and comments intact",
                 @"comment attached and diagnostic on line 3",
                 [crlfDiagnostic objectForKey:@"Message"] ?: @"missing");

        tomlSettings = parseRawTOML(@"[MOUSE]\nhold-right-tap-left = return\n",
                                    &tomlProblems);
        if (tomlSettings != nil || [tomlProblems count] != 1)
            fail(@"unquoted TOML string rejects reload",
                 @"no settings and one problem", tomlSettings ?: tomlProblems);

        tomlSettings = parseRawTOML(@"[GENERAL]\nenable-mouse = \"yes\"\n",
                                    &tomlProblems);
        if ([[tomlSettings objectForKey:@"enMMAll"] intValue] != 1 ||
            [tomlProblems count] != 1)
            fail(@"TOML booleans require boolean values",
                 @"default enabled and one problem",
                 [NSString stringWithFormat:@"%@; %@", [tomlSettings objectForKey:@"enMMAll"],
                                                    tomlProblems]);

        NSString *bypassingRecognizer =
            @"static void recognizer(void) {\n"
             "    dispatchCommand(@\"New Gesture\", TRACKPAD);\n"
             "}\n";
        if ([unexpectedDirectDispatchLines(bypassingRecognizer) count] != 1)
            fail(@"direct recognizer dispatch guard", @"one violation", @"not detected");

        // Bare keys and key names containing the separator must parse.
        expectKey(@"return", @"return", 36, 0);
        expectKey(@"enter alias", @"enter", 36, 0);
        expectKey(@"escape", @"escape", 53, 0);
        expectKey(@"page-down survives hyphen split", @"page-down", 121, 0);
        expectKey(@"forward-delete survives hyphen split", @"forward-delete", 117, 0);

        // Every documented spelling of a chord must produce the same binding.
        expectKey(@"plus separator", @"cmd+shift+a", 0, CMD | SHIFT);
        expectKey(@"hyphen separator", @"command-shift-a", 0, CMD | SHIFT);
        expectKey(@"space separator", @"Cmd Shift A", 0, CMD | SHIFT);
        expectKey(@"symbols without separators", @"⌘⇧A", 0, CMD | SHIFT);
        expectKey(@"mixed case", @"CMD+Shift+A", 0, CMD | SHIFT);
        expectKey(@"alt is option", @"ctrl+alt+right", 124,
                  CTRL | kCGEventFlagMaskAlternate | NX_DEVICELALTKEYMASK);
        expectKey(@"quoted value", @"\"cmd+shift+a\"", 0, CMD | SHIFT);
        expectKey(@"right control", @"right-control+space", 49,
                  kCGEventFlagMaskControl | NX_DEVICERCTLKEYMASK);
        expectKey(@"right control with hyphen separators", @"right-control-space", 49,
                  kCGEventFlagMaskControl | NX_DEVICERCTLKEYMASK);
        expectKey(@"right-side modifier chord",
                  @"right-shift+right-option+right-command+a", 0,
                  kCGEventFlagMaskShift | NX_DEVICERSHIFTKEYMASK |
                  kCGEventFlagMaskAlternate | NX_DEVICERALTKEYMASK |
                  kCGEventFlagMaskCommand | NX_DEVICERCMDKEYMASK);
        expectKeyDisplay(@"digit shortcut display", @"shift+cmd+4", @"⇧⌘4");
        expectKeyDisplay(@"right modifier display", @"right-control+space",
                         @"Right Control + Space");
        expectKeyDisplay(@"mixed modifier side display", @"left-shift+right-command+4",
                         @"Left Shift + Right Command + 4");

        NSDictionary *punctuation = @{
            @"[": @33, @"]": @30, @"-": @27, @"=": @24, @";": @41,
            @"'": @39, @",": @43, @".": @47, @"/": @44, @"\\": @42, @"`": @50,
        };
        for (NSString *key in punctuation)
            expectKey([@"punctuation " stringByAppendingString:key], key,
                      [[punctuation objectForKey:key] intValue], 0);

        // An unknown token must reject the value instead of binding the last
        // token that happened to parse.
        for (NSString *bad in @[@"cmd+bogus+a", @"a+b", @"cmd+", @"nonsense"]) {
            NSString *conf = [NSString stringWithFormat:@"[mouse]\nhold-right-tap-left = %@\n", bad];
            if (bindingFor(parse(conf), @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap") != nil)
                fail([@"malformed value rejected: " stringByAppendingString:bad], @"nothing", @"a binding");
        }

        // A slug mapped to two engine gesture names must produce both bindings.
        NSDictionary *s = parse(@"[mouse]\nhold-right-tap-left = return\n");
        if (bindingFor(s, @"MagicMouseCommands", @"Middle-Fix Index-Far-Tap") == nil)
            fail(@"one slug binds near and far", @"far variant present", @"missing");

        s = parse(@"[MOUSE]\n\nhold-right-tap-left = return\n");
        if (bindingFor(s, @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap") == nil)
            fail(@"uppercase section with spacing", @"binding present", @"missing");

        // A built-in action must dispatch by name instead of as a keystroke.
        s = parse(@"[trackpad]\nthree-finger-tap = middle-click\n");
        NSDictionary *g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"IsAction"] boolValue])
            fail(@"action is not a keystroke", @YES, [g objectForKey:@"IsAction"]);
        if (![[g objectForKey:@"Command"] isEqualToString:@"Middle Click"])
            fail(@"action name", @"Middle Click", [g objectForKey:@"Command"]);

        NSArray *mouseClickProblems = nil;
        s = parseWithProblems(@"[mouse]\ntwo-finger-click = return\nthree-finger-click = escape\n",
                              &mouseClickProblems);
        if ([mouseClickProblems count] != 0)
            fail(@"mouse physical clicks load without a setting", @0,
                 @([mouseClickProblems count]));

        // The setting is accepted for compatibility with existing files and
        // has no effect; either value leaves the bindings loaded and reports
        // nothing.
        NSArray *inertFlagProblems = nil;
        s = parseWithProblems(@"[mouse]\ntwo-finger-click = return\n"
                              @"[general]\nexperimental-mouse-click-gestures = false\n",
                              &inertFlagProblems);
        if (bindingFor(s, @"MagicMouseCommands", @"Two-Finger Click") == nil ||
            [inertFlagProblems count] != 0)
            fail(@"experimental-mouse-click-gestures is accepted and inert",
                 @"a binding and no problems",
                 [NSString stringWithFormat:@"%@; %lu problems",
                  bindingFor(s, @"MagicMouseCommands", @"Two-Finger Click") ?: @"no binding",
                  (unsigned long)[inertFlagProblems count]]);

        s = parse(@"[mouse]\ntwo-finger-click = return\nthree-finger-click = escape\n"
                  @"[general]\nexperimental-mouse-click-gestures = true\n");
        if (bindingFor(s, @"MagicMouseCommands", @"Two-Finger Click") == nil)
            fail(@"mouse two-finger physical click is configurable",
                 @"a binding", @"missing");
        if (bindingFor(s, @"MagicMouseCommands", @"Three-Finger Click") == nil)
            fail(@"mouse three-finger physical click is configurable",
                 @"a binding", @"missing");
        s = parse(@"[trackpad]\nthree-finger-click = escape\nfour-finger-click = return\n");
        if (bindingFor(s, @"TrackpadCommands", @"Three-Finger Click") == nil)
            fail(@"trackpad three-finger physical click is configurable",
                 @"a binding", @"missing");
        if (bindingFor(s, @"TrackpadCommands", @"Four-Finger Click") == nil)
            fail(@"trackpad four-finger physical click is configurable",
                 @"a binding", @"missing");
        s = parse(@"[trackpad]\nfive-finger-tap = escape\n");
        if (bindingFor(s, @"TrackpadCommands", @"Five-Finger Tap") == nil)
            fail(@"trackpad five-finger tap is configurable",
                 @"a binding", @"missing");

        s = parse(@"[mouse]\n"
                  @"two-finger-click = return\n"
                  @"[mouse \"Safari\"]\n"
                  @"two-finger-click = escape\n"
                  @"three-finger-click = cmd+a\n"
                  @"[general]\nexperimental-mouse-click-gestures = true\n");
        NSDictionary *globalClick = bindingForApplication(
            s, @"MagicMouseCommands", @"All Applications", @"Two-Finger Click");
        NSDictionary *safariClick = bindingForApplication(
            s, @"MagicMouseCommands", @"Safari", @"Two-Finger Click");
        if ([[globalClick objectForKey:@"KeyCode"] intValue] != 36)
            fail(@"global binding remains available beside app scope", @36,
                 [globalClick objectForKey:@"KeyCode"] ?: @"missing");
        if ([[safariClick objectForKey:@"KeyCode"] intValue] != 53)
            fail(@"app section overrides its gesture", @53,
                 [safariClick objectForKey:@"KeyCode"] ?: @"missing");
        if (bindingForApplication(s, @"MagicMouseCommands", @"Safari",
                                  @"Three-Finger Click") == nil)
            fail(@"app section groups several bindings", @"a binding", @"missing");

        s = parse(@"[trackpad]\nthree-finger-tap { action = \"escape\" }\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if ([[g objectForKey:@"KeyCode"] intValue] != 53)
            fail(@"expanded binding accepts an action property", @53,
                 [g objectForKey:@"KeyCode"] ?: @"missing");

        s = parse(@"[trackpad]\nthree-finger-tap { action = \"escape\", defer = true }\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"Defer"] boolValue])
            fail(@"expanded tap binding can defer its action", @YES,
                 [g objectForKey:@"Defer"] ?: @"missing");

        // A double tap is its own binding, on either device, and a single tap
        // beside it needs an explicit defer to survive the repeat. Deferring
        // the double tap itself has nothing to wait for and is skipped.
        s = parse(@"[trackpad]\nthree-finger-tap { action = \"escape\", defer = true }\n"
                  @"three-finger-double-tap = \"cmd+shift+return\"\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Double-Tap");
        if ([[g objectForKey:@"KeyCode"] intValue] != 36)
            fail(@"a double tap binds beside its deferred single tap", @36,
                 [g objectForKey:@"KeyCode"] ?: @"missing");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"Defer"] boolValue])
            fail(@"a single tap beside its double tap keeps its deferral", @YES,
                 [g objectForKey:@"Defer"] ?: @"missing");

        s = parse(@"[mouse]\ntwo-finger-double-tap = \"escape\"\n");
        if (bindingFor(s, @"MagicMouseCommands", @"Two-Finger Tap") != nil)
            fail(@"binding only the double tap leaves the single tap unbound",
                 @"no single-tap binding", @"a binding");
        g = bindingFor(s, @"MagicMouseCommands", @"Two-Finger Double-Tap");
        if ([[g objectForKey:@"KeyCode"] intValue] != 53)
            fail(@"a mouse double tap binds on its own", @53,
                 [g objectForKey:@"KeyCode"] ?: @"missing");

        NSArray *doubleDeferProblems = nil;
        s = parseWithProblems(@"[trackpad]\nthree-finger-double-tap { action = \"escape\", defer = true }\n",
                              &doubleDeferProblems);
        if (bindingFor(s, @"TrackpadCommands", @"Three-Finger Double-Tap") != nil ||
            [doubleDeferProblems count] == 0)
            fail(@"defer on a double tap is reported and skipped",
                 @"a problem and no binding", @"a binding");

        // Every tap slug that has a double-tap sibling must reach it through
        // the one map dispatch reads, or the sibling can never fire.
        for (NSDictionary *slugs in @[[Config mouseGestureSlugs], [Config trackpadGestureSlugs]]) {
            for (NSString *slug in slugs) {
                if (![slug hasSuffix:@"-double-tap"])
                    continue;
                NSString *single = [slug stringByReplacingOccurrencesOfString:@"-double-tap"
                                                                   withString:@"-tap"];
                NSString *singleEngine = [[slugs objectForKey:single] firstObject];
                NSString *reached = [Config doubleTapGestureName:singleEngine];
                NSString *expected = [[slugs objectForKey:slug] firstObject];
                if (![reached isEqualToString:expected])
                    fail([@"repeating " stringByAppendingString:single], expected, reached ?: @"nil");
            }
        }

        s = parse(@"[trackpad]\nthree-finger-click { action = \"escape\", haptic = false }\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Click");
        if ([g objectForKey:@"HapticFeedback"] == nil ||
            [[g objectForKey:@"HapticFeedback"] boolValue])
            fail(@"expanded trackpad binding can disable haptics", @NO,
                 [g objectForKey:@"HapticFeedback"] ?: @"missing");

        s = parse(@"[trackpad]\nthree-finger-tap { action = \"url:https://example.com/a,b\", haptic = false }\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"OpenURL"] isEqualToString:@"https://example.com/a,b"])
            fail(@"commas inside a quoted expanded action remain part of the action",
                 @"https://example.com/a,b", [g objectForKey:@"OpenURL"] ?: @"missing");

        s = parse(@"[trackpad]\nthree-finger-tap {\n"
                  @"  action = \"url:things:///add?title={{clipboard|urlencode}}\",\n"
                  @"  haptic = false\n}\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"OpenURL"]
                isEqualToString:@"things:///add?title={{clipboard|urlencode}}"])
            fail(@"substitution braces do not close a multiline binding block",
                 @"configured substitution", [g objectForKey:@"OpenURL"] ?: @"missing");

        NSArray *unterminatedProblems = nil;
        s = parseWithProblems(@"[trackpad]\n"
                              @"three-finger-tap { action = \"escape\"\n"
                              @"[mouse]\n"
                              @"two-finger-click = return\n"
                              @"[general]\nexperimental-mouse-click-gestures = true\n",
                              &unterminatedProblems);
        if (s != nil || [unterminatedProblems count] != 1)
            fail(@"invalid TOML rejects the whole reload",
                 @"no settings and one problem",
                 [NSString stringWithFormat:@"%@; %lu problems",
                  s ?: @"no settings", (unsigned long)[unterminatedProblems count]]);

        NSArray *expandedProblems = nil;
        s = parseWithProblems(@"[trackpad]\nthree-finger-tap { action = escape }\n",
                              &expandedProblems);
        if (bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap") != nil)
            fail(@"expanded action values are quoted", @"nothing", @"a binding");

        s = parse(@"[trackpad]\n"
                  @"three-finger-click = escape\n"
                  @"[trackpad \"Safari\"]\n"
                  @"three-finger-click { haptic = false }\n");
        g = bindingForApplication(s, @"TrackpadCommands", @"Safari", @"Three-Finger Click");
        if ([[g objectForKey:@"KeyCode"] intValue] != 53 ||
            [g objectForKey:@"HapticFeedback"] == nil ||
            [[g objectForKey:@"HapticFeedback"] boolValue])
            fail(@"app binding inherits its global action and overrides one property",
                 @"escape with haptics off", g ?: @"missing");

        NSArray *inheritanceProblems = nil;
        s = parseWithProblems(@"[trackpad \"Safari\"]\n"
                              @"three-finger-click { haptic = false }\n",
                              &inheritanceProblems);
        if ([[s objectForKey:@"BindingCount"] integerValue] != 0 ||
            [inheritanceProblems count] != 1)
            fail(@"property-only app binding requires a loaded global action",
                 @"zero bindings and one problem",
                 [NSString stringWithFormat:@"%@ bindings, %lu problems",
                  [s objectForKey:@"BindingCount"],
                  (unsigned long)[inheritanceProblems count]]);

        s = parse(@"[mouse]\ntwo-finger-click = return\n"
                  @"[mouse \"Safari\"]\ntwo-finger-click = off\n"
                  @"[general]\nexperimental-mouse-click-gestures = true\n");
        g = bindingForApplication(s, @"MagicMouseCommands", @"Safari", @"Two-Finger Click");
        if (g == nil || [[g objectForKey:@"Enable"] boolValue])
            fail(@"app section can exclude a global gesture", @"disabled binding", g ?: @"missing");
        if ([[s objectForKey:@"BindingCount"] integerValue] != 1)
            fail(@"binding count includes active declarations and excludes off rules",
                 @1, [s objectForKey:@"BindingCount"] ?: @"missing");

        s = parse(@"[trackpad]\nthree-finger-click = off\n"
                  @"[trackpad \"Safari\"]\nthree-finger-click { haptic = false }\n");
        g = bindingForApplication(s, @"TrackpadCommands", @"Safari", @"Three-Finger Click");
        if (g == nil || [[g objectForKey:@"Enable"] boolValue])
            fail(@"app property override preserves a global exclusion",
                 @"disabled binding", g ?: @"missing");

        // A bare swipe slug loads under its family engine name beside any
        // directional binding, so dispatch can prefer the direction and fall
        // back to the family.
        s = parse(@"[trackpad]\nthree-finger-swipe = escape\n"
                  @"three-finger-swipe-left = tab\n"
                  @"[mouse]\ntwo-finger-swipe = escape\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Swipe-Any");
        if ([[g objectForKey:@"KeyCode"] intValue] != 53)
            fail(@"bare swipe slug binds the family name", @53, [g objectForKey:@"KeyCode"]);
        g = bindingFor(s, @"TrackpadCommands", @"Three-Swipe-Left");
        if ([[g objectForKey:@"KeyCode"] intValue] != 48)
            fail(@"directional swipe binding stays its own entry", @48, [g objectForKey:@"KeyCode"]);
        if (bindingFor(s, @"TrackpadCommands", @"Three-Swipe-Right") != nil)
            fail(@"bare swipe slug does not expand into directional names",
                 @"no directional entry", @"an entry");
        if (bindingFor(s, @"MagicMouseCommands", @"Two-Swipe-Any") == nil)
            fail(@"mouse bare swipe slug binds its family name", @"a binding", @"missing");

        // Dispatch resolves the recognized direction first and consults this
        // mapping only when no binding names it. Every directional swipe in
        // the vocabulary must reach a family name its own device also exposes.
        if (![[Config directionlessGestureName:@"One-Swipe-Left"] isEqualToString:@"One-Swipe-Any"] ||
            ![[Config directionlessGestureName:@"Two-Swipe-Right"] isEqualToString:@"Two-Swipe-Any"] ||
            ![[Config directionlessGestureName:@"Three-Swipe-Up"] isEqualToString:@"Three-Swipe-Any"] ||
            ![[Config directionlessGestureName:@"Four-Swipe-Down"] isEqualToString:@"Four-Swipe-Any"])
            fail(@"directional swipes map to their family name",
                 @"the -Swipe-Any name for the finger count", @"a different mapping");
        if ([Config directionlessGestureName:@"Three-Swipe-Any"] != nil ||
            [Config directionlessGestureName:@"Top-Left-Corner Click"] != nil ||
            [Config directionlessGestureName:@"Two-Finger Tap"] != nil)
            fail(@"family fallback applies only to directional swipes",
                 @"nil", @"a family name");
        for (NSDictionary *slugs in @[[Config mouseGestureSlugs], [Config trackpadGestureSlugs]]) {
            NSMutableSet *deviceEngineNames = [NSMutableSet set];
            for (NSString *slug in slugs)
                [deviceEngineNames addObjectsFromArray:[slugs objectForKey:slug]];
            for (NSString *engineName in deviceEngineNames) {
                NSString *family = [Config directionlessGestureName:engineName];
                if (family != nil && ![deviceEngineNames containsObject:family])
                    fail([@"family fallback is bindable for " stringByAppendingString:engineName],
                         family, @"absent from the device vocabulary");
            }
        }

        // The bare area-click slugs load under one engine name each, which the
        // region cascade tries after the named regions of the same kind.
        s = parse(@"[trackpad]\ncorner-click = escape\nedge-click = tab\n"
                  @"top-left-corner-click = space\n");
        g = bindingFor(s, @"TrackpadCommands", @"Any-Corner Click");
        if ([[g objectForKey:@"KeyCode"] intValue] != 53)
            fail(@"corner-click binds the any-corner name", @53, [g objectForKey:@"KeyCode"]);
        g = bindingFor(s, @"TrackpadCommands", @"Any-Edge Click");
        if ([[g objectForKey:@"KeyCode"] intValue] != 48)
            fail(@"edge-click binds the any-edge name", @48, [g objectForKey:@"KeyCode"]);
        g = bindingFor(s, @"TrackpadCommands", @"Top-Left-Corner Click");
        if ([[g objectForKey:@"KeyCode"] intValue] != 49)
            fail(@"named corner binding stays its own entry", @49, [g objectForKey:@"KeyCode"]);

        // Area-click names accept their words in any order. The pure
        // canonicalizer resolves each reordering to the documented slug, uses
        // adjacency to split the edge-region word-multiset trap, and returns
        // nil for orderings that stay ambiguous or name nothing.
        NSDictionary *reorderings = @{
            // Bare and single-direction forms, every region shape.
            @"click-edge": @"edge-click",
            @"click-corner": @"corner-click",
            @"edge-left-click": @"left-edge-click",
            @"click-top-edge": @"top-edge-click",
            // Corner directions are one vertical and one horizontal word, so
            // the bag alone decides.
            @"corner-click-top-right": @"top-right-corner-click",
            @"left-bottom-corner-click": @"bottom-left-corner-click",
            @"click-corner-right-bottom": @"bottom-right-corner-click",
            // Edge halves, including the issue's example.
            @"top-half-left-edge-click": @"left-edge-top-half-click",
            @"click-right-edge-bottom-half": @"right-edge-bottom-half-click",
            // The trap pair shares a word multiset; adjacency to "edge"
            // resolves each side to a different canonical name.
            @"bottom-half-right-edge-click": @"right-edge-bottom-half-click",
            @"right-half-bottom-edge-click": @"bottom-edge-right-half-click",
            // Edge thirds. "middle" can never be the edge, so the direction on
            // the other side of "edge" claims the slot.
            @"middle-third-left-edge-click": @"left-edge-middle-third-click",
            @"middle-edge-top-third-click": @"top-edge-middle-third-click",
            @"third-bottom-edge-right-click": @"bottom-edge-right-third-click",
            // Canonical names pass through unchanged.
            @"left-edge-top-half-click": @"left-edge-top-half-click",
            @"top-edge-left-half-click": @"top-edge-left-half-click",
            @"top-right-corner-click": @"top-right-corner-click",
        };
        for (NSString *input in reorderings) {
            NSString *canonical = [Config canonicalAreaClickSlug:input
                inSlugs:[Config trackpadGestureSlugs]];
            if (![canonical isEqualToString:[reorderings objectForKey:input]])
                fail([@"reordered area-click canonicalizes: " stringByAppendingString:input],
                     [reorderings objectForKey:input], canonical ?: @"nil");
        }
        for (NSString *rejected in @[
            @"edge-half-top-left-click",   // no direction beside "edge": ambiguous
            @"left-left-edge-click",       // repeated word
            @"middle-edge-click",          // middle is never an edge
            @"top-left-edge-click",        // two directions without a size
            @"three-finger-tap",           // not an area click
            @"top-half-left-corner-click", // sizes belong to edges only
        ]) {
            NSString *canonical = [Config canonicalAreaClickSlug:rejected
                inSlugs:[Config trackpadGestureSlugs]];
            if (canonical != nil)
                fail([@"area-click reordering rejects: " stringByAppendingString:rejected],
                     @"nil", canonical);
        }

        // The generic canonicalizer resolves a bag of words to a slug only
        // when exactly one slug matches, so its safety rests on no two
        // canonical slugs of a device sharing a word multiset. The edge
        // family shares multisets by design and is owned by the adjacency
        // rule above; hold-tap names carry their own beside-the-anchor rule;
        // brush names are ordered by "to" and load only as written. Assert
        // the uniqueness for everything else rather than trusting it.
        for (NSDictionary *slugs in @[[Config mouseGestureSlugs], [Config trackpadGestureSlugs]]) {
            NSMutableDictionary *bags = [NSMutableDictionary dictionary];
            for (NSString *slug in slugs) {
                NSArray *words = [slug componentsSeparatedByString:@"-"];
                if ([words containsObject:@"edge"] || [words containsObject:@"to"] ||
                    ([words containsObject:@"hold"] && [words containsObject:@"tap"]))
                    continue;
                NSString *bag = [[words sortedArrayUsingSelector:@selector(compare:)]
                                 componentsJoinedByString:@"-"];
                if ([bags objectForKey:bag] != nil)
                    fail([@"gesture slugs share a word multiset: " stringByAppendingString:slug],
                         @"unique word multisets", [bags objectForKey:bag]);
                [bags setObject:slug forKey:bag];
            }
        }

        // Every family reorders through the one canonicalizer, on both
        // devices. Area-click inputs pass through the adjacency rule.
        NSDictionary *mouseReorderings = @{
            @"swipe-up-three-finger": @"three-finger-swipe-up",   // directional swipe
            @"swipe-one-finger": @"one-finger-swipe",             // bare swipe
            @"tap-three-finger": @"three-finger-tap",             // tap
            @"tap-front-right": @"front-right-tap",               // positional tap
            @"click-two-finger": @"two-finger-click",             // physical click
            @"tap-right-hold-left": @"hold-left-tap-right",       // hold-tap
            @"left-hold-right-tap": @"hold-left-tap-right",       // hold-tap, prefix order
        };
        for (NSString *input in mouseReorderings) {
            NSString *canonical = [Config canonicalSlug:input
                inSlugs:[Config mouseGestureSlugs]];
            if (![canonical isEqualToString:[mouseReorderings objectForKey:input]])
                fail([@"reordered mouse name canonicalizes: " stringByAppendingString:input],
                     [mouseReorderings objectForKey:input], canonical ?: @"nil");
        }
        NSDictionary *trackpadReorderings = @{
            @"swipe-down-four-finger": @"four-finger-swipe-down", // directional swipe
            @"tap-five-finger": @"five-finger-tap",               // tap
            @"click-four-finger": @"four-finger-click",           // physical click
            @"slide-hold": @"hold-slide",                         // hold-slide
            @"tap-left-hold-right": @"hold-right-tap-left",       // hold-tap
            @"click-corner-top-right": @"top-right-corner-click", // area click
        };
        for (NSString *input in trackpadReorderings) {
            NSString *canonical = [Config canonicalSlug:input
                inSlugs:[Config trackpadGestureSlugs]];
            if (![canonical isEqualToString:[trackpadReorderings objectForKey:input]])
                fail([@"reordered trackpad name canonicalizes: " stringByAppendingString:input],
                     [trackpadReorderings objectForKey:input], canonical ?: @"nil");
        }
        for (NSString *rejected in @[
            @"three-finger-flick",     // word bag matching no slug
            @"swipe-up-four-finger",   // trackpad-only bag on the mouse
            @"tap-hold-left-right",    // no direction beside an anchor: ambiguous
            @"to-index-pinky",         // brush order carries meaning; only canonical loads
        ]) {
            NSString *canonical = [Config canonicalSlug:rejected
                inSlugs:[Config mouseGestureSlugs]];
            if (canonical != nil)
                fail([@"gesture reordering rejects: " stringByAppendingString:rejected],
                     @"nil", canonical);
        }
        if ([Config canonicalSlug:@"to-pinky-index"
              inSlugs:[Config trackpadGestureSlugs]] != nil)
            fail(@"reordered brush name rejects", @"nil", @"a brush slug");

        // Through the parser, a reordered name loads under the canonical
        // engine name, so the menu and reports display only canonical names.
        s = parse(@"[mouse]\nswipe-up-three-finger = space\ntap-three-finger = tab\n");
        g = bindingFor(s, @"MagicMouseCommands", @"Three-Swipe-Up");
        if ([[g objectForKey:@"KeyCode"] intValue] != 49)
            fail(@"reordered swipe name loads canonically", @49, [g objectForKey:@"KeyCode"]);
        g = bindingFor(s, @"MagicMouseCommands", @"Three-Finger Tap");
        if ([[g objectForKey:@"KeyCode"] intValue] != 48)
            fail(@"reordered tap name loads canonically", @48, [g objectForKey:@"KeyCode"]);
        s = parse(@"[trackpad]\ntop-half-left-edge-click = space\n"
                  @"corner-click-top-right = tab\n");
        g = bindingFor(s, @"TrackpadCommands", @"Left-Edge Top-Half Click");
        if ([[g objectForKey:@"KeyCode"] intValue] != 49)
            fail(@"reordered edge-region name loads canonically", @49, [g objectForKey:@"KeyCode"]);
        g = bindingFor(s, @"TrackpadCommands", @"Top-Right-Corner Click");
        if ([[g objectForKey:@"KeyCode"] intValue] != 48)
            fail(@"reordered corner name loads canonically", @48, [g objectForKey:@"KeyCode"]);

        // An ordering that stays ambiguous is skipped with the normal report.
        NSArray *ambiguousProblems = nil;
        s = parseWithProblems(@"[trackpad]\nedge-half-top-left-click = space\n",
                              &ambiguousProblems);
        if ([ambiguousProblems count] != 1 ||
            bindingFor(s, @"TrackpadCommands", @"Left-Edge Top-Half Click") != nil ||
            bindingFor(s, @"TrackpadCommands", @"Top-Edge Left-Half Click") != nil)
            fail(@"ambiguous area-click ordering is skipped with a report",
                 @"one problem and no binding",
                 [NSString stringWithFormat:@"%lu problems",
                  (unsigned long)[ambiguousProblems count]]);

        s = parse(@"[trackpad]\nthree-finger-tap { action = \"escape\", defer = true }\n"
                  @"[trackpad \"Safari\"]\nthree-finger-tap { defer = false }\n");
        g = bindingForApplication(s, @"TrackpadCommands", @"Safari", @"Three-Finger Tap");
        if (g == nil || [[g objectForKey:@"Defer"] boolValue])
            fail(@"app property override can disable global deferral",
                 @"immediate binding", g ?: @"missing");

        NSArray *duplicateTableProblems = nil;
        s = parseWithProblems(@"[mouse]\ntwo-finger-click = return\n"
                              @"[mouse]\ntwo-finger-click = escape\n",
                              &duplicateTableProblems);
        if (s != nil || [duplicateTableProblems count] != 1)
            fail(@"TOML rejects a repeated table",
                 @"no settings and one problem",
                 [NSString stringWithFormat:@"%@; %lu problems",
                  s ?: @"no settings", (unsigned long)[duplicateTableProblems count]]);

        NSArray *legacyProblems = nil;
        s = parseWithProblems(@"mouse.two-finger-tap = escape\n", &legacyProblems);
        if (bindingFor(s, @"MagicMouseCommands", @"Two-Finger Tap") != nil)
            fail(@"device prefixes are not part of TOML schema", @"nothing", @"a binding");
        s = parseWithProblems(@"[mouse]\ntwo-finger-tap.defer = escape\n", &legacyProblems);
        if (bindingFor(s, @"MagicMouseCommands", @"Two-Finger Tap") != nil)
            fail(@"defer is a binding property rather than a gesture suffix", @"nothing", @"a binding");

        // URL bindings preserve their payload exactly and dispatch as actions.
        NSString *customURL = @"raycast://extensions/Raycast/raycast-ai/ai-chat?ref=A%20B&mode=Fast#Prompt";
        s = parse([NSString stringWithFormat:@"[mouse]\nhold-right-tap-left = url:%@\n", customURL]);
        g = bindingFor(s, @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap");
        if (![[g objectForKey:@"OpenURL"] isEqualToString:customURL])
            fail(@"URL preserves case, query, escapes, and fragment", customURL, [g objectForKey:@"OpenURL"]);
        if (![[g objectForKey:@"IsAction"] boolValue])
            fail(@"URL is not a keystroke", @YES, [g objectForKey:@"IsAction"]);

        s = parse(@"[trackpad]\nthree-finger-tap = url:obsidian://daily # trailing comment\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"OpenURL"] isEqualToString:@"obsidian://daily"])
            fail(@"URL permits a trailing comment", @"obsidian://daily", [g objectForKey:@"OpenURL"]);

        // Script bindings resolve a direct executable path at reload. The
        // process launcher receives the path without shell interpretation.
        NSString *scriptPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mg-check-script"];
        [@"#!/bin/sh\nexit 0\n" writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0700}
                                        ofItemAtPath:scriptPath
                                               error:NULL];
        s = parse([NSString stringWithFormat:@"[trackpad]\nthree-finger-tap = script: %@\n", scriptPath]);
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"ScriptPath"] isEqualToString:scriptPath])
            fail(@"script binding preserves its executable path", scriptPath, [g objectForKey:@"ScriptPath"]);
        if (![[g objectForKey:@"IsAction"] boolValue])
            fail(@"script binding is an action", @YES, [g objectForKey:@"IsAction"]);

        s = parse([NSString stringWithFormat:
            @"[trackpad]\nthree-finger-click { action = \"script:%@\", haptic = false }\n",
            scriptPath]);
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Click");
        if (![[g objectForKey:@"ScriptPath"] isEqualToString:scriptPath])
            fail(@"expanded binding accepts a script action", scriptPath,
                 [g objectForKey:@"ScriptPath"] ?: @"missing");

        NSArray *sequenceScriptProblems = nil;
        s = parseRawTOML([NSString stringWithFormat:
            @"[TRACKPAD]\nthree-finger-click = [\"script:%@\", \"url:https://example.com?q={{clipboard|urlencode}}\"]\n",
            scriptPath], &sequenceScriptProblems);
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Click");
        NSArray *scriptSequence = [g objectForKey:@"Sequence"];
        if ([sequenceScriptProblems count] != 0 ||
            ![[[scriptSequence objectAtIndex:0] objectForKey:@"ScriptPath"] isEqualToString:scriptPath] ||
            ![[[scriptSequence objectAtIndex:1] objectForKey:@"OpenURL"]
                isEqualToString:@"https://example.com?q={{clipboard|urlencode}}"])
            fail(@"sequence validates scripts and preserves unresolved URL substitutions",
                 @"validated script and configured URL", g ?: sequenceScriptProblems);

        NSArray *badSequenceScriptProblems = nil;
        s = parseRawTOML(
            @"[TRACKPAD]\nthree-finger-click = [\"escape\", \"script:relative-script\"]\n",
            &badSequenceScriptProblems);
        NSString *badSequenceScriptProblem = [badSequenceScriptProblems count] > 0
            ? [badSequenceScriptProblems objectAtIndex:0] : @"";
        if (bindingFor(s, @"TrackpadCommands", @"Three-Finger Click") != nil ||
            [badSequenceScriptProblem rangeOfString:@"sequence element 2"].location == NSNotFound ||
            [badSequenceScriptProblem rangeOfString:@"absolute path"].location == NSNotFound)
            fail(@"invalid sequence script names its element at reload",
                 @"element 2 and absolute path", badSequenceScriptProblem);

        NSArray *scriptProblems = nil;
        s = parseWithProblems(@"[trackpad]\nthree-finger-tap = script: relative-script\n", &scriptProblems);
        if (bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap") != nil)
            fail(@"relative script path rejected", @"nothing", @"a binding");
        NSString *scriptProblem = [scriptProblems count] > 0 ? [scriptProblems objectAtIndex:0] : @"";
        if ([scriptProblem rangeOfString:@"absolute path"].location == NSNotFound)
            fail(@"relative script path explains the requirement", @"absolute path", scriptProblem);

        // Sound bindings name a file in /System/Library/Sounds and exist so a
        // gesture can be tested without triggering a real action.
        s = parse(@"[trackpad]\nthree-finger-tap = sound:Glass\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"PlaySound"] isEqualToString:@"Glass"])
            fail(@"sound binding records its system sound name", @"Glass",
                 [g objectForKey:@"PlaySound"] ?: @"missing");
        if (![[g objectForKey:@"IsAction"] boolValue])
            fail(@"sound binding is an action", @YES, [g objectForKey:@"IsAction"]);

        NSArray *soundProblems = nil;
        s = parseWithProblems(@"[trackpad]\nthree-finger-tap = sound:NoSuchSound\n", &soundProblems);
        if (bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap") != nil)
            fail(@"unknown sound name rejected", @"nothing", @"a binding");
        NSString *soundProblem = [soundProblems count] > 0 ? [soundProblems objectAtIndex:0] : @"";
        if ([soundProblem rangeOfString:@"/System/Library/Sounds"].location == NSNotFound)
            fail(@"unknown sound name names the sound folder", @"/System/Library/Sounds", soundProblem);

        soundProblems = nil;
        s = parseWithProblems(@"[trackpad]\nthree-finger-tap = sound:/System/Library/Sounds/Glass.aiff\n",
                              &soundProblems);
        if (bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap") != nil)
            fail(@"sound path rejected", @"nothing", @"a binding");
        soundProblem = [soundProblems count] > 0 ? [soundProblems objectAtIndex:0] : @"";
        if ([soundProblem rangeOfString:@"not a path"].location == NSNotFound)
            fail(@"sound path explains the requirement", @"not a path", soundProblem);

        // The sound option confirms a gesture that still does its real work,
        // where the sound: value form replaces the action entirely.
        s = parse(@"[trackpad]\nthree-finger-tap = { action = \"cmd+shift+4\", sound = \"Glass\" }\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"ConfirmSound"] isEqualToString:@"Glass"])
            fail(@"sound option records its system sound name", @"Glass",
                 [g objectForKey:@"ConfirmSound"] ?: @"missing");
        if ([g objectForKey:@"PlaySound"] != nil)
            fail(@"sound option leaves the action alone", @"no PlaySound", @"PlaySound set");
        if ([[g objectForKey:@"KeyCode"] intValue] == 0)
            fail(@"sound option keeps its keystroke action", @"a key code", @"none");

        s = parse(@"[trackpad]\nthree-finger-tap = { action = \"cmd+shift+4\", say = \"screenshot\" }\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"ConfirmSpeech"] isEqualToString:@"screenshot"])
            fail(@"say option records its text", @"screenshot",
                 [g objectForKey:@"ConfirmSpeech"] ?: @"missing");
        if ([[g objectForKey:@"KeyCode"] intValue] == 0)
            fail(@"say option keeps its keystroke action", @"a key code", @"none");

        NSArray *soundOptionProblems = nil;
        s = parseWithProblems(@"[trackpad]\nthree-finger-tap = { action = \"escape\", sound = \"NoSuchSound\" }\n",
                              &soundOptionProblems);
        if (bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap") != nil)
            fail(@"unknown sound option rejected", @"nothing", @"a binding");

        // Speech bindings speak arbitrary text so a test binding can say which
        // gesture fired, not only that one did.
        s = parse(@"[trackpad]\nthree-finger-tap = \"say:three finger tap\"\n");
        g = bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap");
        if (![[g objectForKey:@"SpeakText"] isEqualToString:@"three finger tap"])
            fail(@"speech binding records its text", @"three finger tap",
                 [g objectForKey:@"SpeakText"] ?: @"missing");
        if (![[g objectForKey:@"IsAction"] boolValue])
            fail(@"speech binding is an action", @YES, [g objectForKey:@"IsAction"]);

        NSArray *speechProblems = nil;
        s = parseWithProblems(@"[trackpad]\nthree-finger-tap = \"say:  \"\n", &speechProblems);
        if (bindingFor(s, @"TrackpadCommands", @"Three-Finger Tap") != nil)
            fail(@"empty speech rejected", @"nothing", @"a binding");
        NSString *speechProblem = [speechProblems count] > 0 ? [speechProblems objectAtIndex:0] : @"";
        if ([speechProblem rangeOfString:@"words to speak"].location == NSNotFound)
            fail(@"empty speech explains the requirement", @"words to speak", speechProblem);

        NSDictionary *badURLs = @{
            @"url:raycast//extensions": @"URL is missing a valid scheme followed by \":\"",
            @"url:1raycast://extensions": @"URL scheme must begin with a letter",
            @"url:ray cast://extensions": @"URL contains unencoded whitespace",
            @"url:https://example.com/%ZZ": @"URL contains a malformed percent escape",
        };
        for (NSString *bad in badURLs) {
            NSArray *problems = nil;
            NSString *conf = [NSString stringWithFormat:@"[mouse]\nhold-right-tap-left = %@\n", bad];
            s = parseWithProblems(conf, &problems);
            if (bindingFor(s, @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap") != nil)
                fail([@"malformed URL rejected: " stringByAppendingString:bad], @"nothing", @"a binding");
            NSString *problem = [problems count] > 0 ? [problems objectAtIndex:0] : @"";
            if ([problem rangeOfString:[badURLs objectForKey:bad]].location == NSNotFound)
                fail([@"malformed URL explains: " stringByAppendingString:bad], [badURLs objectForKey:bad], problem);
        }

        // Substitutions are validated at reload and resolved only when the
        // gesture fires. URL encoding treats the clipboard as one component.
        NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
        [parts setYear:2026];
        [parts setMonth:7];
        [parts setDay:31];
        [parts setHour:14];
        [parts setMinute:5];
        NSCalendar *calendar = [[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease];
        [calendar setTimeZone:[NSTimeZone localTimeZone]];
        NSDate *date = [calendar dateFromComponents:parts];
        NSString *problem = nil;
        NSString *resolved = [Config URLByResolvingSubstitutions:
                              @"things:///add?when={{datetime:yyyy-MM-dd'T'HH:mm}}&title={{clipboard|urlencode}}"
                                                        clipboard:@"Café & tea?"
                                                             date:date
                                                          problem:&problem];
        NSString *expectedURL = @"things:///add?when=2026-07-31T14:05&title=Caf%C3%A9%20%26%20tea%3F";
        if (![resolved isEqualToString:expectedURL])
            fail(@"substitutions resolve deterministically", expectedURL, resolved ?: problem);

        resolved = [Config URLByResolvingSubstitutions:@"example://open/{{clipboard}}"
                                             clipboard:@"already-safe"
                                                  date:date
                                               problem:&problem];
        if (![resolved isEqualToString:@"example://open/already-safe"])
            fail(@"raw clipboard substitution", @"example://open/already-safe", resolved ?: problem);

        resolved = [Config URLByResolvingSubstitutions:@"example://open?q={{clipboard|urlencode}}"
                                             clipboard:nil
                                                  date:date
                                               problem:&problem];
        if (![resolved isEqualToString:@"example://open?q="])
            fail(@"empty clipboard becomes an empty value", @"example://open?q=", resolved ?: problem);

        resolved = [Config URLByResolvingSubstitutions:@"example://open?q={{clipboard}}"
                                             clipboard:@"two words"
                                                  date:date
                                               problem:&problem];
        if (resolved != nil || [problem rangeOfString:@"unencoded whitespace"].location == NSNotFound)
            fail(@"expanded URL is revalidated", @"unencoded whitespace problem", resolved ?: problem);

        NSDictionary *badSubstitutions = @{
            @"url:example://open?q={{clipbord}}": @"unknown substitution \"clipbord\"",
            @"url:example://open?q={{clipboard|encode}}": @"unknown clipboard substitution filter \"encode\"",
            @"url:example://open?q={{clipboard}": @"substitution has unmatched braces",
            @"url:example://open?q=clipboard}}": @"substitution has unmatched braces",
            @"url:example://open?q={{datetime:}}": @"datetime substitution needs a format",
            @"url:example://open?q={{datetime:yyyy-MM-dd'T}}": @"datetime substitution has an unmatched quote",
        };
        for (NSString *bad in badSubstitutions) {
            NSArray *problems = nil;
            NSString *conf = [NSString stringWithFormat:@"[mouse]\nhold-right-tap-left = %@\n", bad];
            s = parseWithProblems(conf, &problems);
            if (bindingFor(s, @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap") != nil)
                fail([@"malformed substitution rejected: " stringByAppendingString:bad], @"nothing", @"a binding");
            NSString *reported = [problems count] > 0 ? [problems objectAtIndex:0] : @"";
            if ([reported rangeOfString:[badSubstitutions objectForKey:bad]].location == NSNotFound)
                fail([@"malformed substitution explains: " stringByAppendingString:bad],
                     [badSubstitutions objectForKey:bad], reported);
        }

        s = parse(@"[mouse]\nhold-right-tap-left = url:https://example.com?q={{clipboard|urlencode}}\n");
        g = bindingFor(s, @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap");
        if (![[g objectForKey:@"OpenURL"] isEqualToString:@"https://example.com?q={{clipboard|urlencode}}"])
            fail(@"configured substitution remains unresolved", @"configured expression", [g objectForKey:@"OpenURL"]);

        // Unrecognized names must be skipped without affecting valid lines.
        s = parse(@"[mouse]\nnot-a-gesture = return\nhold-right-tap-left = return\n");
        if (bindingFor(s, @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap") == nil)
            fail(@"unknown gesture does not abort the file", @"later binding present", @"missing");
        s = parse(@"[mouse]\nhold-right-tap-left = not-a-key\n");
        if (bindingFor(s, @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap") != nil)
            fail(@"unknown key is skipped", @"nothing", @"a binding");

        // TOML has one boolean spelling for each value.
        s = parse(@"[general]\nenable-mouse = true\n");
        if ([[s objectForKey:@"enMMAll"] intValue] != 1)
            fail(@"boolean true", @1, [s objectForKey:@"enMMAll"]);
        s = parse(@"[general]\nenable-mouse = false\n");
        if ([[s objectForKey:@"enMMAll"] intValue] != 0)
            fail(@"boolean false", @0, [s objectForKey:@"enMMAll"]);

        s = parse(@"[general]\nhaptic-feedback = true\n");
        if ([[s objectForKey:@"HapticFeedback"] intValue] != 1)
            fail(@"haptic feedback setting enables trackpad confirmation",
                 @1, [s objectForKey:@"HapticFeedback"]);
        s = parse(@"[general]\n");
        if ([[s objectForKey:@"HapticFeedback"] intValue] != 1)
            fail(@"haptic feedback defaults on", @1, [s objectForKey:@"HapticFeedback"]);
        s = parse(@"[general]\nhaptic-feedback = false\n");
        if ([[s objectForKey:@"HapticFeedback"] intValue] != 0)
            fail(@"haptic feedback can be disabled", @0, [s objectForKey:@"HapticFeedback"]);

        s = parse(@"[general]\nverbose-logging = true\n");
        if ([[s objectForKey:@"LogLevel"] intValue] != 3)
            fail(@"verbose logging includes touch geometry", @3, [s objectForKey:@"LogLevel"]);

        s = parse(@"[general]\ndominant-hand = left\n");
        if ([[s objectForKey:@"Handed"] intValue] != 1 ||
            [[s objectForKey:@"MMHanded"] intValue] != 1)
            fail(@"left dominant hand mirrors both devices", @1, [s objectForKey:@"Handed"]);
        s = parse(@"[general]\ndominant-hand = right\n");
        if ([[s objectForKey:@"Handed"] intValue] != 0 ||
            [[s objectForKey:@"MMHanded"] intValue] != 0)
            fail(@"right dominant hand keeps the default axis", @0, [s objectForKey:@"Handed"]);

        s = parse(@"[general]\nmenu-bar-icon = \"trickpad\"\n");
        if (![[s objectForKey:@"MenuBarIcon"] isEqualToString:@"trickpad"])
            fail(@"menu bar icon accepts bundled mark", @"trickpad", [s objectForKey:@"MenuBarIcon"]);
        s = parse(@"[general]\nmenu-bar-icon = \"sf:waveform.path\"\n");
        if (![[s objectForKey:@"MenuBarIcon"] isEqualToString:@"sf:waveform.path"])
            fail(@"menu bar icon accepts SF Symbol", @"sf:waveform.path", [s objectForKey:@"MenuBarIcon"]);

        NSArray *invalidSettings = @[
            @"[general]\nenable-mouse = maybe\n",
            @"[general]\nenable-trackpad = enabled\n",
            @"[general]\nverbose-logging = verbose\n",
            @"[general]\nhaptic-feedback = sometimes\n",
            @"[general]\nexperimental-mouse-click-gestures = maybe\n",
            @"[general]\ndominant-hand = center\n",
            @"[general]\nmenu-bar-icon = \"sf:\"\n",
            @"[general]\ntap-speed = soon\n",
            @"[general]\ntap-speed = 0\n",
            @"[general]\ntap-speed = -0.2\n",
        ];
        for (NSString *text in invalidSettings) {
            NSArray *problems = nil;
            parseWithProblems(text, &problems);
            if ([problems count] == 0)
                fail(@"invalid general setting is reported", @"a problem", @"none");
        }

        // Format 3 is explicit in new files and implicit while the app is in alpha.
        // An older or newer format rejects the whole file.
        if (parse(@"[general]\nconfig-version = 3\n") == nil)
            fail(@"configuration format 3", @"settings", @"nothing");
        if (parse(@"[general]\nenable-mouse = true\n") == nil)
            fail(@"missing configuration version means current format", @"settings", @"nothing");
        NSArray *versionProblems = nil;
        s = parseWithProblems(@"[general]\nconfig-version = 1\n", &versionProblems);
        if (s != nil)
            fail(@"unsupported configuration format rejects file", @"nothing", @"settings");
        NSString *versionProblem = [versionProblems count] > 0 ? [versionProblems objectAtIndex:0] : @"";
        if ([versionProblem rangeOfString:@"this version reads format 3"].location == NSNotFound)
            fail(@"unsupported configuration format explains rejection",
                 @"format 3 explanation", versionProblem);

        // Comments and blank lines must not produce bindings. A # without
        // preceding whitespace is ordinary value content, as URL fragments need.
        s = parse(@"# comment\n\n[mouse]\nhold-right-tap-left = return # trailing\n");
        g = bindingFor(s, @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap");
        if ([[g objectForKey:@"KeyCode"] intValue] != 36)
            fail(@"trailing comment stripped", @36, [g objectForKey:@"KeyCode"]);

        // The shipped example must parse before it is copied into a user config.
        NSString *example = [[[NSProcessInfo processInfo] arguments] count] > 1
            ? [[NSProcessInfo processInfo] arguments][1] : nil;
        if (example != nil) {
            NSDictionary *parsed = [Config settingsFromFile:example];
            if (parsed == nil)
                fail(@"shipped example parses", @"a settings dictionary", @"nil");
            else if (bindingFor(parsed, @"MagicMouseCommands", @"Middle-Fix Index-Near-Tap") == nil)
                fail(@"shipped example binds its documented default", @"a binding", @"missing");
        }

        // Every gesture a slug can reach must have a menu phrase, or the menu
        // falls back to the engine's internal name.
        for (NSDictionary *slugs in @[[Config mouseGestureSlugs], [Config trackpadGestureSlugs]]) {
            for (NSString *slug in slugs) {
                for (NSString *engineName in [slugs objectForKey:slug]) {
                    if ([[Config humanNameForGesture:engineName] isEqualToString:engineName])
                        fail([@"menu phrase for " stringByAppendingString:engineName],
                             @"a description of the motion", engineName);
                }
            }
        }

        NSString *canonicalMouseHold = [Config canonicalGestureName:@"Middle-Fix Index-Far-Tap"
                                                            inSlugs:[Config mouseGestureSlugs]];
        if (![canonicalMouseHold isEqualToString:@"Middle-Fix Index-Near-Tap"])
            fail(@"menu collapses engine aliases for one public gesture",
                 @"Middle-Fix Index-Near-Tap", canonicalMouseHold);

        // Every slug must appear in the canonical gesture reference. The
        // installed agent guide points there instead of duplicating the list.
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        for (NSUInteger i = 2; i < MIN([args count], 4); i++) {
            NSString *doc = [NSString stringWithContentsOfFile:args[i]
                                                        encoding:NSUTF8StringEncoding
                                                           error:NULL];
            if (doc == nil)
                continue;
            if ([doc rangeOfString:@"wait:MS"].location == NSNotFound ||
                [doc rangeOfString:@"[\""].location == NSNotFound)
                fail([NSString stringWithFormat:@"%@ documents sequence arrays and wait:MS",
                      [args[i] lastPathComponent]], @"array syntax and wait:MS", @"missing");
        }
        NSUInteger documentationEnd = MIN([args count], 4);
        for (NSUInteger i = 3; i < documentationEnd; i++) {
            NSString *doc = [NSString stringWithContentsOfFile:args[i] encoding:NSUTF8StringEncoding error:NULL];
            if (doc == nil)
                continue;
            NSString *name = [args[i] lastPathComponent];
            for (NSDictionary *slugs in @[[Config mouseGestureSlugs], [Config trackpadGestureSlugs]]) {
                for (NSString *slug in slugs) {
                    if ([doc rangeOfString:slug].location == NSNotFound)
                        fail([NSString stringWithFormat:@"%@ documents %@", name, slug], @"present", @"missing");
                }
            }
        }

        if ([args count] > 3) {
            NSString *reference = [NSString stringWithContentsOfFile:args[3] encoding:NSUTF8StringEncoding error:NULL];
            expectDeviceSlugs(@"gesture reference mouse section",
                              section(reference, @"## Magic Mouse", @"## Magic Trackpad"),
                              [Config mouseGestureSlugs]);
            expectDeviceSlugs(@"gesture reference trackpad section",
                              section(reference, @"## Magic Trackpad", @"## What a gesture can send"),
                              [Config trackpadGestureSlugs]);
        }

        // Every exposed engine name needs a dispatch site for its own device.
        // A matching name on the other device does not make a binding reachable.
        if ([args count] > 4) {
            NSString *engine = [NSString stringWithContentsOfFile:args[4] encoding:NSUTF8StringEncoding error:NULL];
            NSArray *unexpectedDispatches = unexpectedDirectDispatchLines(engine);
            if ([unexpectedDispatches count] > 0)
                fail(@"recognizers dispatch only through ownership helpers",
                     @"no unexpected direct dispatch", unexpectedDispatches);
            NSUInteger gestureDispatchCount = directDispatchLineCount(
                engine, @"dispatchCommand(gesture, device);");
            if (gestureDispatchCount != 6)
                fail(@"direct gesture dispatch allowlist",
                     @6, @(gestureDispatchCount));
            NSUInteger characterDispatchCount = directDispatchLineCount(
                engine, @"dispatchCommand(commandString, CHARRECOGNITION);");
            if (characterDispatchCount != 3)
                fail(@"character recognition dispatch allowlist",
                     @3, @(characterDispatchCount));
            NSArray *devices = @[
                @[[Config mouseGestureSlugs], @"MAGICMOUSE"],
                @[[Config trackpadGestureSlugs], @"TRACKPAD"],
            ];
            for (NSArray *device in devices) {
                NSDictionary *slugs = device[0];
                NSString *constant = device[1];
                for (NSString *slug in slugs) {
                    for (NSString *engineName in [slugs objectForKey:slug]) {
                        NSString *exclusiveDispatch = [NSString stringWithFormat:
                            @"dispatchExclusiveCommand(@\"%@\", %@", engineName, constant];
                        NSString *exclusiveTapDispatch = [NSString stringWithFormat:
                            @"dispatchExclusiveTapCommand(@\"%@\", %@", engineName, constant];
                        BOOL physicalClick = [engineName hasSuffix:@"-Finger Click"] &&
                            [engine rangeOfString:[NSString stringWithFormat:@"gesture = @\"%@\"", engineName]].location != NSNotFound &&
                            [engine rangeOfString:@"dispatchCommand(gesture, device)"].location != NSNotFound;
                        // Area clicks resolve to one gesture name at mouse-down
                        // and dispatch it through the shared physical-click
                        // mouse-up path, so each name needs a literal in the
                        // engine's region tables rather than its own dispatch.
                        BOOL areaClick = ([engineName rangeOfString:@"-Edge"].location != NSNotFound ||
                             [engineName hasSuffix:@"-Corner Click"]) &&
                            [engine rangeOfString:[NSString stringWithFormat:@"@\"%@\"", engineName]].location != NSNotFound &&
                            [engine rangeOfString:@"pendingTrackpadAreaClickGesture"].location != NSNotFound &&
                            [engine rangeOfString:@"dispatchCommand(gesture, device)"].location != NSNotFound;
                        // Family names have no recognizer of their own: the
                        // directional recognizer dispatches, and the binding
                        // lookup falls back to the family name it maps to.
                        // A double tap has no recognizer either: the single
                        // tap's recognizer dispatches, and a repeat inside the
                        // double-click interval reaches this name instead.
                        BOOL doubleTap = [engineName hasSuffix:@" Double-Tap"] &&
                            [Config doubleTapGestureName:
                                [engineName stringByReplacingOccurrencesOfString:@" Double-Tap"
                                                                      withString:@" Tap"]] != nil &&
                            [engine rangeOfString:@"doubleTapGestureName:gesture"].location != NSNotFound;
                        BOOL swipeFamily = [engineName hasSuffix:@"-Swipe-Any"] &&
                            [Config directionlessGestureName:
                                [engineName stringByReplacingOccurrencesOfString:@"-Any"
                                                                      withString:@"-Left"]] != nil &&
                            [engine rangeOfString:@"directionlessGestureName"].location != NSNotFound;
                        BOOL dispatched = [engine rangeOfString:exclusiveDispatch].location != NSNotFound ||
                            [engine rangeOfString:exclusiveTapDispatch].location != NSNotFound;
                        if (!dispatched && !physicalClick && !areaClick && !swipeFamily && !doubleTap)
                            fail([NSString stringWithFormat:@"%@ %@ has an exclusive recognizer dispatch", constant, slug],
                                 [NSString stringWithFormat:@"%@ or %@", exclusiveDispatch, exclusiveTapDispatch], @"missing");
                    }
                }
            }

            NSString *clickCallback = section(engine, @"static CGEventRef CGEventCallback", @"static int gestureMagicMouseMiddleClick");
            for (NSString *required in @[@"MGTrackpadInteractionBeginPhysicalClick",
                                         @"MGTrackpadInteractionRecordPhysicalDrag",
                                         @"MGTrackpadInteractionFinishPhysicalClick",
                                         @"MGTrackpadInteractionShouldPreservePrimaryClick",
                                         @"trackpadRewritingSecondaryClick",
                                         @"trackpadClickReplacedNative",
                                         @"pendingTrackpadPrimaryDown = CGEventCreateCopy(event)",
                                         @"replayPendingTrackpadPrimaryDown",
                                         @"trackpadClickFingerCount == 3", @"trackpadClickFingerCount == 4",
                                         @"trackpadClickFingerCount == 1",
                                         @"pendingTrackpadAreaClickGesture",
                                         @"MGTrackpadInteractionPendingSingleContactClickPosition",
                                         @"magicMouseThreeFingerFlag", @"device = TRACKPAD",
                                         @"device = MAGICMOUSE", @"dispatchCommand(gesture, device)",
                                         @"dispatchMagicMousePhysicalClickForContactCount"]) {
                if ([clickCallback rangeOfString:required].location == NSNotFound)
                    fail(@"physical click callback retains its device dispatch",
                         required, @"missing");
            }

            if ([engine rangeOfString:@"trackpadHasTwoFingers"].location != NSNotFound)
                fail(@"native trackpad dragging is not suppressed by legacy contact flags",
                     @"no trackpadHasTwoFingers gate", @"legacy gate remains");
            if ([engine rangeOfString:@"MGGestureSequenceFinishFrame"].location == NSNotFound)
                fail(@"gesture ownership ends through the raw-contact lifecycle",
                     @"MGGestureSequenceFinishFrame", @"missing");
            if ([engine rangeOfString:@"ModifierFlags:modifierFlags"].location == NSNotFound)
                fail(@"configured shortcuts preserve modifier sides",
                     @"ModifierFlags:modifierFlags", @"missing");
            for (NSString *required in @[
                @"MGTrackpadInteractionObserveBoundScrollFamily",
                @"MGGestureSequenceObserveBoundScrollFamily",
                // The scroll tap decides per event, not per armed flag, because
                // a gesture's momentum arrives after its contacts are gone.
                @"MGTrackpadInteractionSuppressesScrollEvent",
                @"MGGestureSequenceSuppressesScrollEvent",
            ]) {
                if ([engine rangeOfString:required].location == NSNotFound)
                    fail(@"bound swipe families suppress native scrolling through sequence lift",
                         required, @"missing");
            }
            for (NSString *required in @[
                @"MGTraceRecordCandidate(gesture, @\"shadow-recognized\", @\"catalog-audit\")",
                @"if (hasBinding) disableHorizontalScroll = 1",
            ]) {
                if ([engine rangeOfString:required].location == NSNotFound)
                    fail(@"catalog audit preserves native behavior", required, @"missing");
            }

            for (NSString *command in [[Config actionNames] allValues]) {
                NSString *branch = [NSString stringWithFormat:@"isEqualToString:@\"%@\"", command];
                if ([engine rangeOfString:branch].location == NSNotFound)
                    fail([@"action dispatch " stringByAppendingString:command], branch, @"missing");
            }

            NSArray *invocations = @[
                @"gestureMagicMouseThreeFingerTap(tapData, tapContactCount, timestamp, 0)",
                @"gestureMagicMouseOneFingerTap(tapData, tapContactCount, timestamp)",
                @"gestureMagicMouseOneFixOneTap(tapData, tapContactCount, timestamp)",
                @"gestureMagicMouseTwoFingerSwipe(data, nFingers, timestamp, thumbPresent)",
                @"gestureTrackpadTwoFingerTap(data, nFingers,",
                @"gestureTrackpadHoldSlide(data, nFingers)",
            ];
            for (NSString *invocation in invocations) {
                if ([engine rangeOfString:invocation].location == NSNotFound)
                    fail(@"device callback invokes exposed recognizer", invocation, @"missing");
            }

            NSString *mouseHoldTap = section(engine,
                @"static int gestureMagicMouseOneFixOneTap", @"static int magicMouseCallback");
            if ([mouseHoldTap rangeOfString:@"customMagicMouseTapSuppressionUntil ="].location == NSNotFound)
                fail(@"mouse hold-tap suppresses competing tap recognizers",
                     @"tap suppression", @"missing");

            NSString *mouseTwoFingerTap = section(engine,
                @"static void gestureMagicMouseTwoFingerTap", @"static void gestureMagicMouseThreeFingerTap");
            if ([mouseTwoFingerTap rangeOfString:@"step = 0;"].location != NSNotFound)
                fail(@"rejected mouse two-finger tap waits for every finger to lift",
                     @"named rejection state", @"returned to idle during the touch sequence");

            NSString *mouseCallback = section(engine,
                @"static int magicMouseCallback", @"static void turnOffMagicMouse");
            NSRange threeTapCall = [mouseCallback rangeOfString:
                @"gestureMagicMouseThreeFingerTap(tapData, tapContactCount, timestamp, 0)"];
            NSRange twoTapCall = [mouseCallback rangeOfString:
                @"gestureMagicMouseTwoFingerTap(tapData, tapContactCount, timestamp, 0)"];
            if (threeTapCall.location == NSNotFound || twoTapCall.location == NSNotFound ||
                threeTapCall.location >= twoTapCall.location)
                fail(@"mouse tap discriminator evaluates exact higher count first",
                     @"filtered three-finger tap before filtered two-finger tap", @"missing or reversed");
            for (NSString *required in @[
                @"if (nFingers >= 3)", @"kTwoFingerTapRejectedUntilLift",
                @"gesture = @\"Two-Finger Click\"", @"gesture = @\"Three-Finger Click\"",
                @"customMagicMouseTapSuppressionUntil = CFAbsoluteTimeGetCurrent() + 0.18",
                @"MGMouseClickInteractionMarkHandled",
            ]) {
                if ([engine rangeOfString:required].location == NSNotFound)
                    fail(@"mouse tap and click four-way discriminator wiring",
                         required, @"missing");
            }

            if ([engine rangeOfString:@"objectForKey:@\"Defer\""] .location == NSNotFound ||
                [engine rangeOfString:@"[NSEvent doubleClickInterval]"] .location == NSNotFound ||
                [engine rangeOfString:@"handleGestureKey:"] .location == NSNotFound)
                fail(@"deferred binding uses the Mac double-click interval",
                     @"deferred dispatcher integration", @"missing");

            // One pending window serves both the deferred single tap and the
            // double tap. A second window or timer would drift from it.
            for (NSString *required in @[
                @"[Config doubleTapGestureName:gesture]",
                @"if (deferred || doubleBinding != nil)",
                @"repeat:repeated",
                @"dispatchBindingNow(doubleGesture, device, doubleBinding, doubleApplication)",
            ]) {
                if ([engine rangeOfString:required].location == NSNotFound)
                    fail(@"a repeated tap dispatches its double tap through the one pending window",
                         required, @"missing");
            }

            if ([engine rangeOfString:@"objectForKey:@\"ScriptPath\""] .location == NSNotFound ||
                [engine rangeOfString:@"[ScriptRunner launchScriptAtPath:"] .location == NSNotFound)
                fail(@"script binding launches through ScriptRunner",
                     @"script runner integration", @"missing");

            // Every swipe family that can be mistaken for the device's own
            // scrolling must arm suppression, not the three-finger one alone.
            if ([engine rangeOfString:@"observeBoundSwipeFamilies(TRACKPAD"] .location == NSNotFound ||
                [engine rangeOfString:@"observeBoundSwipeFamilies(MAGICMOUSE"] .location == NSNotFound ||
                [engine rangeOfString:@"@[@\"Three\", @\"Four\"] : @[@\"Two\", @\"Three\"]"] .location == NSNotFound)
                fail(@"every swipe family that overlaps scrolling arms suppression",
                     @"scroll suppression coverage", @"missing");

            if ([engine rangeOfString:@"bindingPreference != nil"] .location == NSNotFound ||
                [engine rangeOfString:@"enabled && device == TRACKPAD"] .location == NSNotFound ||
                [engine rangeOfString:@"NSHapticFeedbackPatternGeneric"] .location == NSNotFound)
                fail(@"enabled trackpad gestures request generic haptic feedback",
                     @"trackpad-only haptic integration", @"missing");

            if ([engine rangeOfString:@"copyBundleIdentifierOfAxui"] .location == NSNotFound ||
                [engine rangeOfString:@"resolvedBindingForGesture"] .location == NSNotFound)
                fail(@"app scopes resolve by display name or bundle identifier",
                     @"shared application binding resolver", @"missing");

            // The area-click cascade resolves most specific first: named
            // corner, the any-corner name, named thirds, halves, whole edges,
            // then the any-edge name. Source order carries that precedence.
            NSString *areaCascade = section(engine,
                @"static NSString *boundTrackpadAreaClickGesture",
                @"#pragma mark - CGEventCallback");
            NSArray *cascadeOrder = @[@"return corner;",
                                      @"@\"Any-Corner Click\"",
                                      @"trackpadAreaEdgeThirdName",
                                      @"trackpadAreaEdgeHalfName",
                                      @"trackpadAreaEdgeWholeName",
                                      @"@\"Any-Edge Click\""];
            NSUInteger previousLocation = 0;
            for (NSString *step in cascadeOrder) {
                NSRange found = [areaCascade rangeOfString:step];
                if (found.location == NSNotFound || found.location < previousLocation) {
                    fail(@"area-click cascade keeps most-specific-first order",
                         [cascadeOrder componentsJoinedByString:@" before "], step);
                    break;
                }
                previousLocation = found.location;
            }

            // The family fallback runs only when no entry names the direction,
            // so an explicit directional "off" keeps excluding the direction.
            NSString *resolver = section(engine,
                @"static NSDictionary *bindingForGestureWithMatch",
                @"static NSDictionary *bindingForGesture(");
            for (NSString *required in @[@"directionlessGestureName:gesture",
                                         @"binding != nil || declared"]) {
                if ([resolver rangeOfString:required].location == NSNotFound)
                    fail(@"binding lookup falls back to the swipe family name",
                         required, @"missing");
            }
        }

        if (failures == 0) {
            printf("config parser: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "config parser: %d failure(s)\n", failures);
        return 1;
    }
}
