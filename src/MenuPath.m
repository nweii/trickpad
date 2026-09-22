// Parses menu: payloads into literal title components and normalizes the
// ellipsis spelling used when comparing a configured title with a menu title.

#import "MenuPath.h"

const NSUInteger MGMenuPathMaximumComponents = 16;

static const unichar kGreaterThan = '>';
static const unichar kMenuSeparator = 0x203A; // ›
static const unichar kBackslash = '\\';

static NSString *trimmedComponent(NSString *component) {
    return [component stringByTrimmingCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@" \t"]];
}

NSArray<NSString *> *MGMenuPathComponents(NSString *payload, NSString **outProblem) {
    NSString *problem = nil;
    NSMutableArray *components = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    NSUInteger length = [payload length];
    for (NSUInteger index = 0; index < length && problem == nil; index++) {
        unichar character = [payload characterAtIndex:index];
        if (character == kBackslash) {
            if (index + 1 >= length) {
                problem = @"menu path ends with a backslash; write \\\\ for a literal backslash";
                break;
            }
            unichar escaped = [payload characterAtIndex:++index];
            if (escaped != kGreaterThan && escaped != kMenuSeparator && escaped != kBackslash) {
                problem = [NSString stringWithFormat:
                           @"menu path has \\%C; only \\>, \\›, and \\\\ are escapes", escaped];
                break;
            }
            [current appendFormat:@"%C", escaped];
        } else if (character == kGreaterThan || character == kMenuSeparator) {
            [components addObject:[[current copy] autorelease]];
            [current setString:@""];
        } else {
            [current appendFormat:@"%C", character];
        }
    }
    if (problem == nil)
        [components addObject:[[current copy] autorelease]];

    NSMutableArray *trimmed = [NSMutableArray arrayWithCapacity:[components count]];
    for (NSUInteger index = 0; problem == nil && index < [components count]; index++) {
        NSString *component = trimmedComponent([components objectAtIndex:index]);
        if ([component length] == 0)
            problem = [components count] == 1
                ? @"menu path is empty"
                : [NSString stringWithFormat:@"menu path component %lu is empty",
                   (unsigned long)index + 1];
        else
            [trimmed addObject:component];
    }
    if (problem == nil && [trimmed count] > MGMenuPathMaximumComponents)
        problem = [NSString stringWithFormat:@"menu path has more than %lu components",
                   (unsigned long)MGMenuPathMaximumComponents];

    if (outProblem != NULL)
        *outProblem = problem;
    return problem == nil ? trimmed : nil;
}

NSString *MGMenuTitleForMatching(NSString *title) {
    if (![title hasSuffix:@"..."] || [title hasSuffix:@"...."])
        return title;
    return [[title substringToIndex:[title length] - 3] stringByAppendingString:@"…"];
}

NSString *MGMenuPathDisplay(NSArray<NSString *> *components) {
    return [components componentsJoinedByString:@" › "];
}
