#import "./include/agora_rtc_engine/AgoraSurfaceViewFactory.h"

@interface AgoraSurfaceView : NSObject <FlutterPlatformView>

@property(nonatomic, strong) VideoViewController *controller;

@property(nonatomic, strong) UIView *surfaceView;

/// Hosts the render view over a backdrop in the host's colour a point past a rounded frame: Flutter paints
/// nothing under a platform view, and the frame's antialiased edge would show the hole beneath.
@property(nonatomic, strong) UIView *containerView;

@property(nonatomic, strong) UIView *backdropView;

@property(nonatomic, strong) FlutterMethodChannel *methodChannel;

@property(nonatomic) NSString *viewType;

@property(nonatomic) int64_t platformViewId;

- (instancetype)initWith:(NSObject<FlutterBinaryMessenger> *)messenger
              controller:(VideoViewController *)controller
                   frame:(CGRect)frame
                  viewId:(int64_t)viewId
                    args:(NSDictionary *)args;

@end

@implementation AgoraSurfaceView

- (instancetype)initWith:(NSObject<FlutterBinaryMessenger> *)messenger
              controller:(VideoViewController *)controller
                   frame:(CGRect)frame
                  viewId:(int64_t)viewId
                    args:(NSDictionary *)args {
  if (self = [super init]) {
    self.controller = controller;
    self.viewType = [args objectForKey:@"viewType"];
    self.surfaceView = (UIView *)[self.controller createPlatformRender:viewId frame:frame];
    self.platformViewId = viewId;
    // Always hosted: a letterboxed frame later asks for square corners and a filling one for round, at runtime.
    self.containerView = [[UIView alloc] initWithFrame:frame];
    self.surfaceView.frame = self.containerView.bounds;
    self.surfaceView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerView addSubview:self.surfaceView];
    NSNumber *argb = [args objectForKey:@"cornerBackgroundColor"];
    if ([argb isKindOfClass:[NSNumber class]]) {
      [self addBackdropWithColor:[argb longLongValue]];
    }
    [self setCornerRadius:[[args objectForKey:@"cornerRadius"] doubleValue]];
    self.methodChannel = [FlutterMethodChannel
        methodChannelWithName:
            [NSString
                stringWithFormat:@"agora_rtc_ng/AgoraSurfaceView_%lld",
              viewId]
              binaryMessenger:messenger];
    
    __weak typeof(self) weakSelf = self;
    [self.methodChannel setMethodCallHandler:^(FlutterMethodCall *_Nonnull call,
                                               FlutterResult _Nonnull result) {
      if (weakSelf != nil) {
        [weakSelf onMethodCall:call result:result];
      }
    }];
//    for (NSString *key in args) {
//        if ([@"viewType" isEqualToString:key]) {
//            continue;;
//        }
//      [self onMethodCall:[FlutterMethodCall
//                             methodCallWithMethodName:key
//                                            arguments:[args objectForKey:key]]
//                  result:nil];
//    }
  }
  return self;
}

- (void)dealloc {
    [self.controller dePlatformRenderRef:self.platformViewId];
    self.surfaceView = NULL;
}

- (nonnull UIView *)view {
  return self.containerView;
}

- (void)setCornerRadius:(double)radius {
  self.surfaceView.layer.cornerRadius = radius;
  self.surfaceView.clipsToBounds = radius > 0;
  // A square frame sits over the host's own artwork, which must show at its edges rather than the page.
  self.backdropView.hidden = radius <= 0;
}

- (void)addBackdropWithColor:(int64_t)argb {
  self.backdropView = [[UIView alloc] initWithFrame:CGRectInset(self.containerView.bounds, -1, -1)];
  self.backdropView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.backdropView.backgroundColor = [UIColor colorWithRed:((argb >> 16) & 0xFF) / 255.0
                                                      green:((argb >> 8) & 0xFF) / 255.0
                                                       blue:(argb & 0xFF) / 255.0
                                                      alpha:((argb >> 24) & 0xFF) / 255.0];
  [self.containerView insertSubview:self.backdropView atIndex:0];
}

- (void)onMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([@"getNativeViewPtr" isEqualToString:call.method]) {
      if (self.surfaceView) {
          // Add ref to ensure the `self.surfaceView` not be released by ARC, which will be
          // de-ref by the `VideoViewController.dePlatformRenderRef`.
          [self.controller addPlatformRenderRef:self.platformViewId];
          uint64_t viewId = (uint64_t)self.surfaceView;
          result(@(viewId));
      } else {
          result(@(0));
      }
      

  } else if ([@"deleteNativeViewPtr" isEqualToString:call.method]) {
      // Do nothing
      result(@(0));
  } else if ([@"setCornerRadius" isEqualToString:call.method]) {
      if ([call.arguments isKindOfClass:[NSNumber class]]) {
        [self setCornerRadius:[call.arguments doubleValue]];
      }
      result(nil);
  }
}

@end

@interface AgoraSurfaceViewFactory ()

@property(nonatomic, strong) NSObject<FlutterBinaryMessenger> *messenger;
@property(nonatomic, strong) VideoViewController *controller;

@end

@implementation AgoraSurfaceViewFactory

- (instancetype)initWith:(NSObject<FlutterBinaryMessenger> *)messenger
              controller:(VideoViewController *)controller {
  if (self = [super init]) {
    self.messenger = messenger;
    self.controller = controller;
  }
  return self;
}

- (nonnull NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                            viewIdentifier:(int64_t)viewId
                                                 arguments:(id _Nullable)args {
  return [[AgoraSurfaceView alloc] initWith:self.messenger
                                 controller:self.controller
                                      frame:frame
                                     viewId:viewId
                                       args:args];
}

- (NSObject<FlutterMessageCodec> *)createArgsCodec {
  return [FlutterStandardMessageCodec sharedInstance];
}

@end
