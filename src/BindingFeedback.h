// Words the explanations Trickpad shows when a binding does not do what the
// user configured. Pure Foundation, so every message is checked in isolation.

#import <Foundation/Foundation.h>

// The headline for a binding that failed, naming it by its gesture as Current
// Gestures does, and by its kind ("menu", "URL", "script") when given. When
// mayHaveRun is YES, the headline does not claim the binding failed.
NSString *MGBindingFailureTitle(NSString *gestureName, NSString *kind, BOOL mayHaveRun);

// A URL binding whose configured URL could not be resolved, or that no
// installed application opens. Only the configured URL is quoted, never the
// resolved one, which may contain clipboard contents.
NSString *MGURLFailureMessage(NSString *configuredURL, NSString *resolutionProblem);

// A script that could not start, with the reason macOS gave.
NSString *MGScriptLaunchFailureMessage(NSString *scriptPath, NSString *reason);

// A script that ran and exited with a nonzero status.
NSString *MGScriptExitMessage(NSString *scriptPath, int status);

// Keystrokes macOS blocks because Trickpad lacks Accessibility access.
NSString *MGKeystrokesNeedAccessibilityMessage(void);
