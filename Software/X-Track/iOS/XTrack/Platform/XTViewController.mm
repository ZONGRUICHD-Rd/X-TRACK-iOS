#import "XTViewController.h"
#import "XTCameraControl.h"
#import "XTSensors.h"
#import <QuartzCore/QuartzCore.h>
#include "XTCore.h"

/* ------------------------------------------------------------------ */
/* Screen view: shows the LVGL framebuffer and forwards touches        */
/* ------------------------------------------------------------------ */

@interface XTScreenView : UIView
@end

@implementation XTScreenView
{
    UITouch* _activeTouch;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame])
    {
        self.backgroundColor = UIColor.blackColor;
        self.multipleTouchEnabled = NO;
        self.layer.contentsGravity = kCAGravityResize;
        self.layer.magnificationFilter = kCAFilterNearest;
        self.layer.minificationFilter = kCAFilterLinear;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"X-TRACK";
    }
    return self;
}

- (void)sendTouch:(UITouch*)touch pressed:(BOOL)pressed
{
    CGPoint p = [touch locationInView:self];
    CGSize size = self.bounds.size;
    if (size.width <= 0 || size.height <= 0)
    {
        return;
    }
    int16_t x = (int16_t)floor(p.x / size.width * XT_SCREEN_WIDTH);
    int16_t y = (int16_t)floor(p.y / size.height * XT_SCREEN_HEIGHT);
    XTCore_TouchInput(x, y, pressed);
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    if (_activeTouch)
    {
        return;
    }
    _activeTouch = touches.anyObject;
    [self sendTouch:_activeTouch pressed:YES];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    if (_activeTouch && [touches containsObject:_activeTouch])
    {
        [self sendTouch:_activeTouch pressed:YES];
    }
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    if (_activeTouch && [touches containsObject:_activeTouch])
    {
        [self sendTouch:_activeTouch pressed:NO];
        _activeTouch = nil;
    }
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    [self touchesEnded:touches withEvent:event];
}

@end

/* ------------------------------------------------------------------ */
/* View controller                                                    */
/* ------------------------------------------------------------------ */

@implementation XTViewController
{
    XTScreenView* _screenView;
    CADisplayLink* _displayLink;
    CGColorSpaceRef _colorSpace;
    XTCameraControl* _cameraControl;
    XTSensors* _sensors;
}

- (void)dealloc
{
    [_displayLink invalidate];
    if (_colorSpace)
    {
        CGColorSpaceRelease(_colorSpace);
    }
}

- (void)loadView
{
    UIView* root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    root.backgroundColor = UIColor.blackColor;
    _screenView = [[XTScreenView alloc] initWithFrame:CGRectMake(0, 0, XT_SCREEN_WIDTH, XT_SCREEN_HEIGHT)];
    [root addSubview:_screenView];
    self.view = root;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

    /* Documents folder = virtual SD card (MAP/, Track/, SystemSave.json) */
    NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager* fm = NSFileManager.defaultManager;
    for (NSString* dir in @[ @"MAP", @"Track" ])
    {
        [fm createDirectoryAtPath:[docs stringByAppendingPathComponent:dir]
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:nil];
    }

    _sensors = [XTSensors new];
    [_sensors updateStorageForPath:docs];

    XTCore_Init(docs.fileSystemRepresentation);

    [_sensors start];

    _cameraControl = [[XTCameraControl alloc] initWithView:self.view];

    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame:)];
    _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat side = MIN(safe.size.width, safe.size.height);
    if (side <= 0)
    {
        return;
    }

    /* Prefer an integer pixel scale (crisp pixels) when it uses most of the space */
    CGFloat screenScale = self.view.window.screen.scale ?: UIScreen.mainScreen.scale;
    CGFloat sidePx = side * screenScale;
    CGFloat intScale = floor(sidePx / XT_SCREEN_WIDTH);
    CGFloat intSide = intScale * XT_SCREEN_WIDTH / screenScale;
    if (intScale >= 1 && intSide >= side * 0.85)
    {
        side = intSide;
        _screenView.layer.magnificationFilter = kCAFilterNearest;
    }
    else
    {
        _screenView.layer.magnificationFilter = kCAFilterLinear;
    }

    _screenView.frame = CGRectMake(
        round(CGRectGetMidX(safe) - side / 2),
        round(CGRectGetMidY(safe) - side / 2),
        side,
        side
    );
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
    return YES;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
    return UIRectEdgeBottom;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (void)appDidBecomeActive
{
    _displayLink.paused = NO;
    [_sensors setBackground:NO];
    [_cameraControl start];
}

- (void)appDidEnterBackground
{
    _displayLink.paused = YES;
    [_sensors setBackground:YES];
    [_cameraControl stop];
}

- (void)onFrame:(CADisplayLink*)link
{
    XTCore_Tick();
    [self presentFramebuffer];
}

- (void)presentFramebuffer
{
    const uint32_t* pixels = NULL;
    if (!XTCore_FetchFramebuffer(&pixels))
    {
        return;
    }

    const size_t bytesPerRow = XT_SCREEN_WIDTH * 4;
    CFDataRef data = CFDataCreate(NULL, (const UInt8*)pixels, bytesPerRow * XT_SCREEN_HEIGHT);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGImageRef image = CGImageCreate(
        XT_SCREEN_WIDTH,
        XT_SCREEN_HEIGHT,
        8,
        32,
        bytesPerRow,
        _colorSpace,
        kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst,
        provider,
        NULL,
        false,
        kCGRenderingIntentDefault
    );

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _screenView.layer.contents = (__bridge id)image;
    [CATransaction commit];

    CGImageRelease(image);
    CGDataProviderRelease(provider);
    CFRelease(data);
}

@end
