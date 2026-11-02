#import <Foundation/Foundation.h>

/* Values editable in the iOS Settings app (Settings.bundle) */
@interface XTSettings : NSObject
+ (void)registerDefaults;
+ (BOOL)cameraControlEnabled;
+ (BOOL)cameraControlReversed;
@end
