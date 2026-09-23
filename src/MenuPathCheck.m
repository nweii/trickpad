// Checks the menu-path grammar: separators, spacing, escapes, component
// limits, single titles, and the ellipsis equivalence used in matching.

#import <Foundation/Foundation.h>
#import "MenuPath.h"

static int failures = 0;

static void expectComponents(NSString *payload, NSArray *expected, const char *message) {
    NSString *problem = nil;
    NSArray *components = MGMenuPathComponents(payload, &problem);
    if ([components isEqual:expected] && problem == nil)
        return;
    fprintf(stderr, "FAIL  %s: got %s (%s)\n", message,
            [[components description] UTF8String], [problem UTF8String]);
    failures++;
}

static void expectProblem(NSString *payload, const char *message) {
    NSString *problem = nil;
    if (MGMenuPathComponents(payload, &problem) == nil && [problem length] > 0)
        return;
    fprintf(stderr, "FAIL  %s\n", message);
    failures++;
}

static void require(BOOL condition, const char *message) {
    if (condition)
        return;
    fprintf(stderr, "FAIL  %s\n", message);
    failures++;
}

int main(void) {
    @autoreleasepool {
        NSArray *path = @[@"File", @"Open Recent", @"Clear Menu"];
        expectComponents(@"File > Open Recent > Clear Menu", path, "spaced > separates components");
        expectComponents(@"File>Open Recent>Clear Menu", path, "unspaced > separates components");
        expectComponents(@"File >Open Recent>  Clear Menu", path, "uneven spacing is ignored");
        expectComponents(@"\tFile › Open Recent › Clear Menu ", path, "› separates components");
        expectComponents(@"File > Open Recent › Clear Menu", path, "separators may be mixed");
        expectComponents(@"Save", @[@"Save"], "one component names a title");
        expectComponents(@"View > Show/Hide Sidebar", @[@"View", @"Show/Hide Sidebar"],
                         "a slash is part of a title");
        expectComponents(@"View / Sidebar", @[@"View / Sidebar"],
                         "slashes do not separate components");
        expectComponents(@"Go > A \\> B", @[@"Go", @"A > B"], "\\> writes a literal >");
        expectComponents(@"Go > A \\› B", @[@"Go", @"A › B"], "\\› writes a literal ›");
        expectComponents(@"Go > C:\\\\Temp", @[@"Go", @"C:\\Temp"], "\\\\ writes a literal backslash");
        expectComponents(@"Édition > Rétablir…", @[@"Édition", @"Rétablir…"],
                         "Unicode titles are kept literally");
        expectComponents(@"Edit >   Find  Next ", @[@"Edit", @"Find  Next"],
                         "interior spacing inside a title is kept");

        expectProblem(@"", "an empty path is rejected");
        expectProblem(@"   ", "a blank path is rejected");
        expectProblem(@"File > > Save", "an empty middle component is rejected");
        expectProblem(@"File >", "an empty last component is rejected");
        expectProblem(@"File > Sa\\ve", "an unknown escape is rejected");
        expectProblem(@"File > Save\\", "a trailing backslash is rejected");
        NSMutableArray *seventeen = [NSMutableArray array];
        for (int index = 0; index < 17; index++)
            [seventeen addObject:@"Menu"];
        expectProblem([seventeen componentsJoinedByString:@" > "], "seventeen components are rejected");
        [seventeen removeLastObject];
        expectComponents([seventeen componentsJoinedByString:@" > "], seventeen,
                         "sixteen components are accepted");

        require([MGMenuTitleForMatching(@"Settings...") isEqualToString:MGMenuTitleForMatching(@"Settings…")],
                "three terminal periods match an ellipsis");
        require(![MGMenuTitleForMatching(@"Wait....") isEqualToString:MGMenuTitleForMatching(@"Wait.…")],
                "four terminal periods are not an ellipsis");
        require(![MGMenuTitleForMatching(@"a...b") isEqualToString:MGMenuTitleForMatching(@"a…b")],
                "interior periods are not an ellipsis");
        require([MGMenuTitleForMatching(@"save as...") isEqualToString:MGMenuTitleForMatching(@"Save As…")],
                "matching ignores capitalization");
        require([MGMenuTitleForMatching(@"Resume") isEqualToString:MGMenuTitleForMatching(@"Résumé")],
                "matching ignores accents");
        require(![MGMenuTitleForMatching(@"Find Next") isEqualToString:MGMenuTitleForMatching(@"Find  Next")],
                "matching keeps interior spacing");
        require([MGMenuPathDisplay(path) isEqualToString:@"File › Open Recent › Clear Menu"],
                "display joins components with ›");
    }
    if (failures > 0)
        return 1;
    printf("menu path: ok\n");
    return 0;
}
