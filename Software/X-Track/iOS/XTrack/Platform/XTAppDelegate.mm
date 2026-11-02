#import "XTAppDelegate.h"
#import "XTViewController.h"
#import "XTSettings.h"
#include "XTCore.h"

@implementation XTAppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    [XTSettings registerDefaults];
    return YES;
}

- (UISceneConfiguration*)application:(UIApplication*)application
    configurationForConnectingSceneSession:(UISceneSession*)connectingSceneSession
                                   options:(UISceneConnectionOptions*)options
{
    UISceneConfiguration* config =
        [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
    config.delegateClass = [XTSceneDelegate class];
    return config;
}

- (void)applicationWillTerminate:(UIApplication*)application
{
    XTCore_Save();
}

@end

@implementation XTSceneDelegate

- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)connectionOptions
{
    if (![scene isKindOfClass:[UIWindowScene class]])
    {
        return;
    }
    UIWindowScene* windowScene = (UIWindowScene*)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.backgroundColor = UIColor.blackColor;
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.rootViewController = [XTViewController new];
    [self.window makeKeyAndVisible];
}

- (void)sceneDidBecomeActive:(UIScene*)scene
{
    /* A bike computer keeps the screen on */
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    [(XTViewController*)self.window.rootViewController appDidBecomeActive];
}

- (void)sceneWillResignActive:(UIScene*)scene
{
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}

- (void)sceneDidEnterBackground:(UIScene*)scene
{
    XTCore_Save();
    [(XTViewController*)self.window.rootViewController appDidEnterBackground];
}

@end
