#import <UIKit/UIKit.h>
#import "XTAppDelegate.h"

int main(int argc, char* argv[])
{
    NSString* appDelegateClassName;
    @autoreleasepool
    {
        appDelegateClassName = NSStringFromClass([XTAppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
