// Parses the menu-path grammar of a menu: binding and normalizes menu titles
// for matching. Pure Foundation, with no Accessibility access.

#import <Foundation/Foundation.h>

// The largest number of components a path may name.
extern const NSUInteger MGMenuPathMaximumComponents;

// Splits a menu: payload into its literal title components. Components are
// separated by > or ›, with spaces and tabs around a separator ignored. \>, \›,
// and \\ write those characters inside a title. One component names a title to
// find anywhere in the menu bar; two or more name a root-to-leaf path. Returns
// nil and sets outProblem when the payload is invalid.
NSArray<NSString *> *MGMenuPathComponents(NSString *payload, NSString **outProblem);

// Returns the form of a title used for matching: a terminal run of exactly
// three periods reads as a Unicode ellipsis. Nothing else is folded.
NSString *MGMenuTitleForMatching(NSString *title);

// Joins components for display, as in "File › Save".
NSString *MGMenuPathDisplay(NSArray<NSString *> *components);
