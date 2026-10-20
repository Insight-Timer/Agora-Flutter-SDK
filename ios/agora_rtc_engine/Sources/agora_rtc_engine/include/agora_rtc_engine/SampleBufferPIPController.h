#import <Foundation/Foundation.h>

#import <AgoraRtcWrapper/AgoraPIPController.h>

/// Stands in for AgoraPIPController, which moves its video view into `UIApplication.windows.firstObject` and so
/// covers the app instead of filling PiP whenever that isn't the PiP window. This one renders the first remote
/// stream's frames straight into the PiP sample buffer layer.
@interface SampleBufferPIPController : NSObject

- (instancetype _Nonnull)initWith:(id<AgoraPIPStateChangedDelegate> _Nonnull)delegate;

- (BOOL)isSupported;

- (BOOL)isAutoEnterSupported;

- (BOOL)isActivated;

- (BOOL)setup:(AgoraPIPOptions *_Nonnull)options;

- (BOOL)start;

- (void)stop;

- (void)dispose;

@end
