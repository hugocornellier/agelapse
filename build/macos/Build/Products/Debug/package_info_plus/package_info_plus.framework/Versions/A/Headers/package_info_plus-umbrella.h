#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "FPPPackageInfoPlusPlugin.h"

FOUNDATION_EXPORT double package_info_plusVersionNumber;
FOUNDATION_EXPORT const unsigned char package_info_plusVersionString[];

