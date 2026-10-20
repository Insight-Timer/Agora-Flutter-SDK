#import "./include/agora_rtc_engine/SampleBufferPIPController.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <AgoraRtcKit/AgoraMediaBase.h>
#import <AgoraRtcWrapper/iris_rtc_rendering_cxx.h>
#import <UIKit/UIKit.h>

#include <memory>
#include <string.h>

@interface SampleBufferPIPController () <AVPictureInPictureControllerDelegate,
                                         AVPictureInPictureSampleBufferPlaybackDelegate>

@property(nonatomic, weak) id<AgoraPIPStateChangedDelegate> stateDelegate;
@property(nonatomic) UIView *sourceView;
@property(atomic) AVSampleBufferDisplayLayer *displayLayer;
@property(nonatomic) AVPictureInPictureController *pipController;
@property(nonatomic) BOOL isPIPActivated;
@property(nonatomic) dispatch_queue_t enqueueQueue;

- (void)enqueuePixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

namespace {

class FrameDelegate : public agora::iris::VideoFrameObserverDelegate {
 public:
  explicit FrameDelegate(SampleBufferPIPController *controller) : controller_(controller) {}

  void OnVideoFrameReceived(const void *videoFrame, const IrisRtcVideoFrameConfig &config, bool resize) override {
    SampleBufferPIPController *controller = controller_;
    const agora::media::base::VideoFrame *frame = (const agora::media::base::VideoFrame *)videoFrame;
    if (!controller || frame->width == 0 || frame->height == 0 || !frame->pixelBuffer) {
      return;
    }
    [controller enqueuePixelBuffer:(CVPixelBufferRef)frame->pixelBuffer];
  }

 private:
  __weak SampleBufferPIPController *controller_;
};

}  // namespace

@implementation SampleBufferPIPController {
  IrisRtcRenderingHandle _rendering;
  int _delegateId;
  std::unique_ptr<FrameDelegate> _frameDelegate;
  unsigned int _uid;
  NSString *_channelId;
}

- (instancetype)initWith:(id<AgoraPIPStateChangedDelegate>)delegate {
  self = [super init];
  if (self) {
    _stateDelegate = delegate;
    _delegateId = agora::iris::INVALID_DELEGATE_ID;
    _enqueueQueue = dispatch_queue_create("io.agora.flutter.pip_enqueue", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (BOOL)isSupported {
  return [AVPictureInPictureController isPictureInPictureSupported];
}

- (BOOL)isAutoEnterSupported {
  return [self isSupported];
}

- (BOOL)isActivated {
  return self.isPIPActivated;
}

- (BOOL)setup:(AgoraPIPOptions *)options {
  if (![self isSupported] || !options.apiEngine || options.videoStreamArray.count == 0) {
    return NO;
  }
  AgoraPIPVideoStream *stream = options.videoStreamArray.firstObject;
  [self observeStream:stream apiEngine:options.apiEngine];

  if (!self.pipController) {
    UIWindow *window = [self hostWindow];
    if (!window) {
      return NO;
    }
    self.displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;

    // Behind the Flutter view: AVKit needs the layer in a window, the user never needs to see it.
    self.sourceView = [[UIView alloc] initWithFrame:window.bounds];
    self.sourceView.userInteractionEnabled = NO;
    self.sourceView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.displayLayer.frame = self.sourceView.bounds;
    [self.sourceView.layer addSublayer:self.displayLayer];
    [window insertSubview:self.sourceView atIndex:0];

    AVPictureInPictureControllerContentSource *source =
        [[AVPictureInPictureControllerContentSource alloc] initWithSampleBufferDisplayLayer:self.displayLayer
                                                                           playbackDelegate:self];
    self.pipController = [[AVPictureInPictureController alloc] initWithContentSource:source];
    self.pipController.delegate = self;
    self.pipController.requiresLinearPlayback = YES;
  }
  self.pipController.canStartPictureInPictureAutomaticallyFromInline = options.autoEnterEnabled;
  return YES;
}

- (BOOL)start {
  if (!self.pipController.isPictureInPicturePossible) {
    return NO;
  }
  [self.pipController startPictureInPicture];
  return YES;
}

- (void)stop {
  [self.pipController stopPictureInPicture];
}

- (void)dispose {
  [self removeFrameDelegate];
  [self.pipController stopPictureInPicture];
  self.pipController.delegate = nil;
  self.pipController = nil;
  [self.sourceView removeFromSuperview];
  self.sourceView = nil;
  AVSampleBufferDisplayLayer *displayLayer = self.displayLayer;
  self.displayLayer = nil;
  dispatch_async(self.enqueueQueue, ^{
    [displayLayer flushAndRemoveImage];
  });
  self.isPIPActivated = NO;
}

- (void)dealloc {
  [self removeFrameDelegate];
}

#pragma mark - Frames

- (void)observeStream:(AgoraPIPVideoStream *)stream apiEngine:(void *)apiEngine {
  NSString *channelId = stream.channelId ?: @"";
  if (_frameDelegate && _uid == stream.uid && [_channelId isEqualToString:channelId]) {
    return;
  }
  [self removeFrameDelegate];

  _rendering = CreateIrisRtcRendering(apiEngine);
  if (!_rendering) {
    return;
  }
  _uid = stream.uid;
  _channelId = channelId;
  _frameDelegate = std::make_unique<FrameDelegate>(self);

  IrisRtcVideoFrameConfig config = EmptyIrisRtcVideoFrameConfig;
  config.video_frame_format = agora::media::base::VIDEO_PIXEL_FORMAT::VIDEO_CVPIXEL_NV12;
  config.uid = stream.uid;
  config.video_source_type = stream.sourceType;
  config.video_view_setup_mode = stream.setupMode;
  strlcpy(config.channelId, channelId.UTF8String, sizeof(config.channelId));
  config.observed_frame_position = agora::media::base::VIDEO_MODULE_POSITION::POSITION_PRE_RENDERER;

  agora::iris::IrisRtcRendering *rendering = (agora::iris::IrisRtcRendering *)_rendering;
  _delegateId = rendering->AddVideoFrameObserverDelegate(config, _frameDelegate.get());
}

- (void)removeFrameDelegate {
  if (!_rendering) {
    return;
  }
  agora::iris::IrisRtcRendering *rendering = (agora::iris::IrisRtcRendering *)_rendering;
  if (_delegateId != agora::iris::INVALID_DELEGATE_ID) {
    rendering->RemoveVideoFrameObserverDelegate(_delegateId);
  }
  FreeIrisRtcRendering(_rendering);
  _rendering = nullptr;
  _delegateId = agora::iris::INVALID_DELEGATE_ID;
  _frameDelegate.reset();
  _channelId = nil;
}

- (void)enqueuePixelBuffer:(CVPixelBufferRef)pixelBuffer {
  CMVideoFormatDescriptionRef format = NULL;
  if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &format) != noErr) {
    return;
  }
  CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeInvalid, kCMTimeInvalid};
  CMSampleBufferRef sampleBuffer = NULL;
  OSStatus status =
      CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixelBuffer, format, &timing, &sampleBuffer);
  CFRelease(format);
  if (status != noErr || !sampleBuffer) {
    return;
  }
  CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
  if (attachments && CFArrayGetCount(attachments) > 0) {
    CFMutableDictionaryRef attachment = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFDictionarySetValue(attachment, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
  }

  AVSampleBufferDisplayLayer *displayLayer = self.displayLayer;
  dispatch_async(self.enqueueQueue, ^{
    if (displayLayer) {
      if (displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        [displayLayer flush];
      }
      [displayLayer enqueueSampleBuffer:sampleBuffer];
    }
    CFRelease(sampleBuffer);
  });
}

#pragma mark - Window

- (UIWindow *)hostWindow {
  UIWindow *fallback = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
      if (window.isKeyWindow) {
        return window;
      }
      if (!fallback && scene.activationState == UISceneActivationStateForegroundActive) {
        fallback = window;
      }
    }
  }
  return fallback;
}

#pragma mark - AVPictureInPictureControllerDelegate

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)controller {
  self.isPIPActivated = YES;
  [self.stateDelegate pipStateChanged:AgoraPIPStateStarted error:nil];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
    failedToStartPictureInPictureWithError:(NSError *)error {
  self.isPIPActivated = NO;
  [self.stateDelegate pipStateChanged:AgoraPIPStateFailed error:error.localizedDescription];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller {
  self.isPIPActivated = NO;
  [self.stateDelegate pipStateChanged:AgoraPIPStateStopped error:nil];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completionHandler {
  completionHandler(YES);
}

#pragma mark - AVPictureInPictureSampleBufferPlaybackDelegate

- (void)pictureInPictureController:(AVPictureInPictureController *)controller setPlaying:(BOOL)playing {
}

- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)controller {
  // An infinite range is how AVKit recognises live content: no scrubber, no skip buttons.
  return CMTimeRangeMake(kCMTimeNegativeInfinity, kCMTimePositiveInfinity);
}

- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)controller {
  return NO;
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
         didTransitionToRenderSize:(CMVideoDimensions)newRenderSize {
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
                    skipByInterval:(CMTime)skipInterval
                 completionHandler:(void (^)(void))completionHandler {
  completionHandler();
}

@end
