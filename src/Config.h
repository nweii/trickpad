//
//  Config.h
//  Trickpad
//
//  Copyright 2026 Nathan Cheng. All rights reserved.
//
//  Reads the TOML configuration file and produces the settings dictionary the
//  vendored engine already consumes, so nothing downstream needs to know the
//  configuration stopped being a plist.
//

#import <Foundation/Foundation.h>

@interface ConfigResult : NSObject {
    NSDictionary *_settings;
    NSArray *_diagnostics;
    NSDictionary *_sourceComments;
}

// The settings dictionary keeps the exact shape the gesture engine consumes.
// It is nil when the file cannot be read or the complete reload is rejected.
@property(nonatomic, readonly, retain) NSDictionary *settings;

// Each diagnostic carries Message. An applied normalization carries warning
// Severity. A skipped binding also carries Device, Title, and Reason so
// presentation code does not interpret the message.
@property(nonatomic, readonly, retain) NSArray *diagnostics;

// Returns the trailing comment for one configured engine binding.
- (NSString *)commentForDevice:(NSString *)device
                   application:(NSString *)application
                       gesture:(NSString *)gesture;

@end

@interface Config : NSObject

// ~/.config/trickpad/config.toml, or the path in TRICKPAD_CONFIG. Returns nil
// when no configuration file exists.
+ (NSString *)resolvedPath;

// ~/.config/trickpad, where the configuration and its agent notes live.
+ (NSString *)configDirectory;

// Parses one source file into the engine settings and the source metadata used
// to explain that reload.
+ (ConfigResult *)resultFromFile:(NSString *)path;

// Parses the file at `path` into a settings dictionary shaped like the plist
// that Settings loadSettings2: expects. Returns nil if the file cannot be read
// or is invalid TOML. Schema errors are reported and skipped individually.
+ (NSDictionary *)settingsFromFile:(NSString *)path;

// As above, and fills outProblems with TOML or schema diagnostics. Invalid TOML
// returns nil; recognized schema errors are reported while valid bindings load.
+ (NSDictionary *)settingsFromFile:(NSString *)path problems:(NSArray **)outProblems;

// Resolves the supported substitutions in a URL binding. Explicit clipboard
// and date inputs keep resolution deterministic for parser checks.
+ (NSString *)URLByResolvingSubstitutions:(NSString *)url
                                clipboard:(NSString *)clipboard
                                     date:(NSDate *)date
                                  problem:(NSString **)outProblem;

// Every gesture slug the configuration accepts, mapped to the engine gesture
// names it binds. One slug can bind several names where the engine splits a
// single motion into variants a person would not distinguish.
+ (NSDictionary *)mouseGestureSlugs;
+ (NSDictionary *)trackpadGestureSlugs;

// Canonicalizes a reordered area-click name (edge regions, corners, and the
// bare edge-click and corner-click forms) to the slug `slugs` documents.
// Ambiguous orderings and non-area-click names return nil.
+ (NSString *)canonicalAreaClickSlug:(NSString *)slug inSlugs:(NSDictionary *)slugs;

// Canonicalizes a reordered gesture name from any family to the slug `slugs`
// documents, trying the area-click rule first and a unique bag-of-words match
// otherwise. Ambiguous orderings and unknown word sets return nil.
+ (NSString *)canonicalSlug:(NSString *)slug inSlugs:(NSDictionary *)slugs;

// Returns the first engine name for the public slug containing raw, so aliases
// can be presented as one configured gesture.
+ (NSString *)canonicalGestureName:(NSString *)raw inSlugs:(NSDictionary *)slugs;

// The directionless family name a directional swipe falls back to at dispatch
// when no binding names its own direction. Returns nil for any other gesture.
+ (NSString *)directionlessGestureName:(NSString *)engineName;

// The double-tap name a repeat of this tap reaches at dispatch. Returns nil for
// any gesture that does not pair with a double tap.
+ (NSString *)doubleTapGestureName:(NSString *)engineName;

// Every action slug the configuration accepts, mapped to the engine command
// string it dispatches.
+ (NSDictionary *)actionNames;

// An engine gesture name phrased as a motion, for display.
+ (NSString *)humanNameForGesture:(NSString *)raw;

// A configured keystroke phrased for the Current Gestures menu. Explicit left
// or right modifier choices are named; unsided modifiers use macOS glyphs.
+ (NSString *)keystrokeDisplayNameForBinding:(NSDictionary *)binding;

@end
