#import "XTSettings.h"

static NSString* const kCameraControlEnabled = @"camera_control_enabled";
static NSString* const kCameraControlReversed = @"camera_control_reversed";

@implementation XTSettings

+ (void)registerDefaults
{
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        kCameraControlEnabled : @YES,
        kCameraControlReversed : @NO,
    }];
}

+ (BOOL)cameraControlEnabled
{
    return [NSUserDefaults.standardUserDefaults boolForKey:kCameraControlEnabled];
}

+ (BOOL)cameraControlReversed
{
    return [NSUserDefaults.standardUserDefaults boolForKey:kCameraControlReversed];
}

@end
