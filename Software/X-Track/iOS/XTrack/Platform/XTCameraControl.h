#import <UIKit/UIKit.h>

/*
 * Maps the iPhone Camera Control button onto X-TRACK's rotary encoder:
 *
 *   Camera Control light-press + slide  ->  encoder rotate (scroll up / down,
 *                                           switch focus, zoom the map)
 *   Camera Control full press           ->  encoder push (select / back,
 *                                           long press = long press)
 *
 * Third-party apps only receive Camera Control input while they run an
 * AVCaptureSession with a camera input, so a minimal, low-resolution session is
 * kept running while the app is in the foreground (nothing is recorded or
 * displayed). Requires an iPhone with Camera Control (iPhone 16 and later).
 */
@interface XTCameraControl : NSObject
- (instancetype)initWithView:(UIView*)view;
- (void)start;
- (void)stop;
@end
