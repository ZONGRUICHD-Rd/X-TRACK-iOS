#import "XTCameraControl.h"
#import "XTSettings.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#include "XTCore.h"

/* Index picker used as an "endless" detent wheel: every detent = one encoder step.
 * The selection is re-centered whenever it gets close to an end. */
static const NSInteger kPickerCount = 101;
static const NSInteger kPickerCenter = kPickerCount / 2;
static const NSInteger kPickerMargin = 5;

@interface XTCameraControl () <AVCaptureSessionControlsDelegate>
@end

@implementation XTCameraControl
{
    __weak UIView* _view;
    dispatch_queue_t _sessionQueue;
    AVCaptureSession* _session;
    AVCaptureIndexPicker* _picker;
    AVCaptureEventInteraction* _eventInteraction;
    NSInteger _lastIndex;
    BOOL _configured;
    BOOL _wantRunning;
}

- (instancetype)initWithView:(UIView*)view
{
    if (self = [super init])
    {
        _view = view;
        _sessionQueue = dispatch_queue_create("xtrack.camera-control", DISPATCH_QUEUE_SERIAL);
        _lastIndex = kPickerCenter;
    }
    return self;
}

#pragma mark - Lifecycle

- (void)start
{
    _wantRunning = YES;

    if (![XTSettings cameraControlEnabled])
    {
        [self stop];
        _wantRunning = NO;
        return;
    }

    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo])
    {
    case AVAuthorizationStatusAuthorized:
        [self configureAndRun];
        break;

    case AVAuthorizationStatusNotDetermined:
    {
        __weak XTCameraControl* weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:^(BOOL granted) {
                                     dispatch_async(dispatch_get_main_queue(), ^{
                                         XTCameraControl* strongSelf = weakSelf;
                                         if (granted && strongSelf && strongSelf->_wantRunning)
                                         {
                                             [strongSelf configureAndRun];
                                         }
                                     });
                                 }];
        break;
    }

    default:
        NSLog(@"[CameraControl] camera access denied, Camera Control disabled");
        break;
    }
}

- (void)stop
{
    _wantRunning = NO;
    _eventInteraction.enabled = NO;
    XTCore_EncoderSetPressed(false);

    AVCaptureSession* session = _session;
    if (session)
    {
        dispatch_async(_sessionQueue, ^{
            if (session.isRunning)
            {
                [session stopRunning];
            }
        });
    }
}

- (void)configureAndRun
{
    [self installEventInteraction];

    AVCaptureSession* session = _session;
    BOOL needsConfig = !_configured;
    if (needsConfig)
    {
        session = [AVCaptureSession new];
        _session = session;
        _configured = YES;
    }

    dispatch_async(_sessionQueue, ^{
        if (needsConfig && ![self configureSession:session])
        {
            return;
        }
        if (!session.isRunning)
        {
            [session startRunning];
        }
    });
}

#pragma mark - Capture session (session queue)

- (BOOL)configureSession:(AVCaptureSession*)session
{
    AVCaptureDevice* device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                 mediaType:AVMediaTypeVideo
                                                                  position:AVCaptureDevicePositionBack];
    if (!device)
    {
        NSLog(@"[CameraControl] no camera");
        return NO;
    }

    NSError* error = nil;
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input)
    {
        NSLog(@"[CameraControl] camera input error: %@", error);
        return NO;
    }

    [session beginConfiguration];

    if ([session canSetSessionPreset:AVCaptureSessionPresetLow])
    {
        session.sessionPreset = AVCaptureSessionPresetLow;
    }

    if ([session canAddInput:input])
    {
        [session addInput:input];
    }

    /* Frames are discarded: no delegate is set */
    AVCaptureVideoDataOutput* output = [AVCaptureVideoDataOutput new];
    output.alwaysDiscardsLateVideoFrames = YES;
    if ([session canAddOutput:output])
    {
        [session addOutput:output];
    }

    if (session.supportsControls)
    {
        [session setControlsDelegate:self queue:dispatch_get_main_queue()];

        AVCaptureIndexPicker* picker =
            [[AVCaptureIndexPicker alloc] initWithLocalizedTitle:NSLocalizedString(@"X-TRACK 滑动", nil)
                                                      symbolName:@"arrow.up.arrow.down"
                                                 numberOfIndexes:kPickerCount];
        picker.selectedIndex = kPickerCenter;

        __weak XTCameraControl* weakSelf = self;
        [picker setActionQueue:dispatch_get_main_queue()
                        action:^(NSInteger selectedIndex) {
                            [weakSelf pickerDidChange:selectedIndex];
                        }];

        if ([session canAddControl:picker])
        {
            [session addControl:picker];
            _picker = picker;
        }
        else
        {
            NSLog(@"[CameraControl] cannot add control");
        }
    }
    else
    {
        NSLog(@"[CameraControl] this device has no Camera Control (slide disabled, press still works)");
    }

    [session commitConfiguration];
    return YES;
}

#pragma mark - Slide => encoder rotation (main queue)

- (void)pickerDidChange:(NSInteger)index
{
    NSInteger delta = index - _lastIndex;
    _lastIndex = index;

    if (delta != 0)
    {
        if ([XTSettings cameraControlReversed])
        {
            delta = -delta;
        }
        XTCore_EncoderAddDiff((int32_t)delta);
    }

    if (index <= kPickerMargin || index >= kPickerCount - 1 - kPickerMargin)
    {
        [self recenterPicker];
    }
}

- (void)recenterPicker
{
    /* Must be called on the picker's action queue (main) */
    if (_picker && _picker.selectedIndex != kPickerCenter)
    {
        _picker.selectedIndex = kPickerCenter;
    }
    _lastIndex = kPickerCenter;
}

#pragma mark - Press => encoder push

- (void)installEventInteraction
{
    UIView* view = _view;
    if (_eventInteraction)
    {
        _eventInteraction.enabled = YES;
        return;
    }
    if (!view)
    {
        return;
    }

    void (^handler)(AVCaptureEvent*) = ^(AVCaptureEvent* event) {
        switch (event.phase)
        {
        case AVCaptureEventPhaseBegan:
            XTCore_EncoderSetPressed(true);
            break;
        case AVCaptureEventPhaseEnded:
        case AVCaptureEventPhaseCancelled:
        default:
            XTCore_EncoderSetPressed(false);
            break;
        }
    };

    _eventInteraction = [[AVCaptureEventInteraction alloc] initWithPrimaryEventHandler:handler
                                                                 secondaryEventHandler:handler];
    _eventInteraction.enabled = YES;
    [view addInteraction:_eventInteraction];
}

#pragma mark - AVCaptureSessionControlsDelegate (main queue)

- (void)sessionControlsDidBecomeActive:(AVCaptureSession*)session
{
    [self recenterPicker];
}

- (void)sessionControlsWillEnterFullscreenAppearance:(AVCaptureSession*)session
{
}

- (void)sessionControlsWillExitFullscreenAppearance:(AVCaptureSession*)session
{
}

- (void)sessionControlsDidBecomeInactive:(AVCaptureSession*)session
{
    [self recenterPicker];
}

@end
