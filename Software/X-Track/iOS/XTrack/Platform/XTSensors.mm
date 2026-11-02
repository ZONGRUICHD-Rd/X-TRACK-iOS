#import "XTSensors.h"
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>
#include "XTCore.h"

/* A fix older than this is reported as "no signal" */
static const NSTimeInterval kFixTimeout = 10.0;

@interface XTSensors () <CLLocationManagerDelegate>
@end

@implementation XTSensors
{
    CLLocationManager* _locationManager;
    CLLocation* _lastLocation;
    CMMotionManager* _motionManager;
    CMPedometer* _pedometer;
    NSTimer* _pollTimer;
    BOOL _background;
}

- (void)start
{
    /* Battery */
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateBattery)
                                               name:UIDeviceBatteryLevelDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateBattery)
                                               name:UIDeviceBatteryStateDidChangeNotification
                                             object:nil];
    [self updateBattery];

    /* GPS */
    _locationManager = [CLLocationManager new];
    _locationManager.delegate = self;
    _locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    _locationManager.distanceFilter = kCLDistanceFilterNone;
    _locationManager.activityType = CLActivityTypeFitness;
    _locationManager.pausesLocationUpdatesAutomatically = NO;
    [self handleAuthorization];

    /* IMU / MAG */
    _motionManager = [CMMotionManager new];
    _motionManager.accelerometerUpdateInterval = 0.2;
    _motionManager.gyroUpdateInterval = 0.2;
    _motionManager.magnetometerUpdateInterval = 0.2;
    if (_motionManager.isAccelerometerAvailable)
    {
        [_motionManager startAccelerometerUpdates];
    }
    if (_motionManager.isGyroAvailable)
    {
        [_motionManager startGyroUpdates];
    }
    if (_motionManager.isMagnetometerAvailable)
    {
        [_motionManager startMagnetometerUpdates];
    }

    /* Steps since midnight */
    if (CMPedometer.isStepCountingAvailable)
    {
        _pedometer = [CMPedometer new];
        NSDate* midnight = [NSCalendar.currentCalendar startOfDayForDate:NSDate.date];
        [_pedometer startPedometerUpdatesFromDate:midnight
                                      withHandler:^(CMPedometerData* data, NSError* error) {
                                          if (!data)
                                          {
                                              return;
                                          }
                                          int32_t steps = data.numberOfSteps.intValue;
                                          dispatch_async(dispatch_get_main_queue(), ^{
                                              XTCore_SetSteps(steps);
                                          });
                                      }];
    }

    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                  target:self
                                                selector:@selector(poll)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)setBackground:(BOOL)background
{
    _background = background;
    if (background)
    {
        [_motionManager stopAccelerometerUpdates];
        [_motionManager stopGyroUpdates];
        [_motionManager stopMagnetometerUpdates];
    }
    else
    {
        if (_motionManager.isAccelerometerAvailable)
        {
            [_motionManager startAccelerometerUpdates];
        }
        if (_motionManager.isGyroAvailable)
        {
            [_motionManager startGyroUpdates];
        }
        if (_motionManager.isMagnetometerAvailable)
        {
            [_motionManager startMagnetometerUpdates];
        }
        [self updateBattery];
    }
}

- (void)updateStorageForPath:(NSString*)path
{
    NSDictionary* attrs = [NSFileManager.defaultManager attributesOfFileSystemForPath:path error:nil];
    NSNumber* size = attrs[NSFileSystemSize];
    if (size)
    {
        XTCore_SetStorageSizeMB((float)(size.doubleValue / (1024.0 * 1024.0)));
    }
}

#pragma mark - Battery

- (void)updateBattery
{
    UIDevice* device = UIDevice.currentDevice;
    float level = device.batteryLevel;
    uint8_t usage = level < 0 ? 100 : (uint8_t)lroundf(level * 100.0f);
    BOOL charging = device.batteryState == UIDeviceBatteryStateCharging || device.batteryState == UIDeviceBatteryStateFull;
    XTCore_SetPower(usage, charging);
}

#pragma mark - Motion

- (void)poll
{
    CMAccelerometerData* acc = _motionManager.accelerometerData;
    CMGyroData* gyro = _motionManager.gyroData;
    if (acc || gyro)
    {
        /* accelerometer in mg, gyro in 0.1 deg/s */
        XTCore_SetIMU(
            (int16_t)(acc.acceleration.x * 1000.0),
            (int16_t)(acc.acceleration.y * 1000.0),
            (int16_t)(acc.acceleration.z * 1000.0),
            (int16_t)(gyro.rotationRate.x * 572.958),
            (int16_t)(gyro.rotationRate.y * 572.958),
            (int16_t)(gyro.rotationRate.z * 572.958)
        );
    }

    CMMagnetometerData* mag = _motionManager.magnetometerData;
    if (mag)
    {
        /* micro tesla x10 */
        XTCore_SetMAG(
            (int16_t)(mag.magneticField.x * 10.0),
            (int16_t)(mag.magneticField.y * 10.0),
            (int16_t)(mag.magneticField.z * 10.0)
        );
    }

    /* Signal lost? */
    if (_lastLocation && -_lastLocation.timestamp.timeIntervalSinceNow > kFixTimeout)
    {
        XTCore_GPSFix_t fix = {};
        fix.valid = false;
        XTCore_SetGPSFix(&fix);
    }
}

#pragma mark - Location

- (void)handleAuthorization
{
    switch (_locationManager.authorizationStatus)
    {
    case kCLAuthorizationStatusNotDetermined:
        [_locationManager requestWhenInUseAuthorization];
        break;

    case kCLAuthorizationStatusAuthorizedWhenInUse:
    case kCLAuthorizationStatusAuthorizedAlways:
        /* Keep tracking (and recording) while the screen is off / app is in background */
        _locationManager.allowsBackgroundLocationUpdates = YES;
        _locationManager.showsBackgroundLocationIndicator = YES;
        [_locationManager startUpdatingLocation];
        break;

    default:
        NSLog(@"[GPS] location access denied");
        break;
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager*)manager
{
    [self handleAuthorization];
}

static int16_t EstimateSatellites(CLLocationAccuracy accuracy)
{
    /* iOS does not expose satellite counts; derive a value X-TRACK understands
     * (>7 = connected, 3..4 = unstable, 0 = disconnected). */
    if (accuracy < 0) return 0;
    if (accuracy <= 5) return 12;
    if (accuracy <= 10) return 10;
    if (accuracy <= 20) return 8;
    if (accuracy <= 50) return 6;
    if (accuracy <= 100) return 4;
    return 3;
}

- (void)locationManager:(CLLocationManager*)manager didUpdateLocations:(NSArray<CLLocation*>*)locations
{
    for (CLLocation* location in locations)
    {
        if (location.horizontalAccuracy < 0)
        {
            continue;
        }

        _lastLocation = location;

        XTCore_GPSFix_t fix = {};
        fix.valid = true;
        fix.longitude = location.coordinate.longitude;
        fix.latitude = location.coordinate.latitude;
        fix.altitude = (float)location.altitude;
        fix.course = (float)location.course;
        fix.speed = location.speed >= 0 ? (float)(location.speed * 3.6) : 0.0f;
        fix.satellites = EstimateSatellites(location.horizontalAccuracy);
        fix.utcTimestampMs = (int64_t)(location.timestamp.timeIntervalSince1970 * 1000.0);
        XTCore_SetGPSFix(&fix);

        /* The display link is paused in background: keep the X-TRACK data
         * processing (sport statistics, track recording) running on GPS updates. */
        if (_background)
        {
            XTCore_Tick();
        }
    }
}

- (void)locationManager:(CLLocationManager*)manager didFailWithError:(NSError*)error
{
    NSLog(@"[GPS] error: %@", error);
}

@end
