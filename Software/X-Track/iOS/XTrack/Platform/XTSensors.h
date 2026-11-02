#import <Foundation/Foundation.h>

/* Feeds iOS sensors into the X-TRACK HAL:
 *   CoreLocation  -> GPS
 *   CoreMotion    -> IMU (accelerometer, gyro, pedometer steps) and magnetometer
 *   UIDevice      -> battery level / charging state
 */
@interface XTSensors : NSObject
- (void)start;
- (void)setBackground:(BOOL)background;
- (void)updateStorageForPath:(NSString*)path;
@end
