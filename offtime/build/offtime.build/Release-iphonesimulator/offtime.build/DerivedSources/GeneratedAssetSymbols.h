#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "day" asset catalog image resource.
static NSString * const ACImageNameDay AC_SWIFT_PRIVATE = @"day";

/// The "launchimage" asset catalog image resource.
static NSString * const ACImageNameLaunchimage AC_SWIFT_PRIVATE = @"launchimage";

/// The "night" asset catalog image resource.
static NSString * const ACImageNameNight AC_SWIFT_PRIVATE = @"night";

#undef AC_SWIFT_PRIVATE
