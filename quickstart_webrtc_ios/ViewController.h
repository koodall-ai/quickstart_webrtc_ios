#import <UIKit/UIKit.h>
#import <WebRTC/WebRTC.h>

@interface ViewController : UIViewController <RTCVideoCapturerDelegate>

- (void)statusBarOrientationDidChange:(NSNotification*)notification;

@end
