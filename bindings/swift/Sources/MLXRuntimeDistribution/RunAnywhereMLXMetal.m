#import <Foundation/Foundation.h>

#import "RunAnywhereMLXMetal.h"

// A class-backed NSBundle lookup makes the anchor verify the selected dynamic
// framework really contains its Metal library, rather than reporting support
// merely because the binary linked.
@interface RunAnywhereMLXMetalBundleMarker : NSObject
@end

@implementation RunAnywhereMLXMetalBundleMarker
@end

int32_t ra_mlx_metal_resource_anchor(void) {
    NSBundle *bundle = [NSBundle bundleForClass:RunAnywhereMLXMetalBundleMarker.class];
    NSURL *metalLibrary = [bundle URLForResource:@"default" withExtension:@"metallib"];
    return metalLibrary != nil ? 1 : 0;
}
