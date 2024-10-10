#import "ViewController.h"
#import <BNBSdkCore/BNBOffscreenEffectPlayer.h>
#import <BNBSdkCore/BNBUtilityManager.h>

static const CGSize EffectPlayerSize = {720, 1280};
static NSString* const BANUBA_SDK_KEY = @<#place your token here#>;

@interface ViewController ()

@property(nonatomic, strong) RTCCameraVideoCapturer* cameraVideoCapturer;
@property(nonatomic, strong) RTCVideoTrack* rtcTrack;
@property(nonatomic, strong) UIView<RTCVideoRenderer>* rtcEAGLVideoView;
@property(nonatomic, assign) AVCaptureDevicePosition devicePosition;
@property(nonatomic, strong) RTCPeerConnectionFactory* factory;
@property(nonatomic, strong) RTCVideoSource* videoSource;
@property UIInterfaceOrientation orientation;
@property(nonatomic, strong) BNBOffscreenEffectPlayer* effectPlayer;
@property BOOL effectLoaded;

- (void)statusBarOrientationDidChange:(NSNotification*)notification;

@end

@implementation ViewController

#pragma mark - configuration/setup/deinitialization

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    _orientation = UIInterfaceOrientationPortrait;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(statusBarOrientationDidChange:)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:nil];
    [self setUpView];
    [self setUpData];
}

- (void)setUpView
{
    [self.view addSubview:self.rtcEAGLVideoView];
    self.rtcEAGLVideoView.frame = self.view.bounds;
}

- (void)setUpData
{
    [self.rtcTrack addRenderer:self.rtcEAGLVideoView];

    self.devicePosition = AVCaptureDevicePositionFront;
    AVCaptureDevice* device = [self findDeviceForPosition:self.devicePosition];

    AVCaptureDeviceFormat* format = [self selectFormatForDevice:device];
    int fps = [self selectFpsForFormat:format];
    [self.cameraVideoCapturer startCaptureWithDevice:device
                                              format:format
                                                 fps:fps
                                   completionHandler:^(NSError* _Nonnull error) {
                                     NSLog(@"Capture initialization completed: %@", [error description]);
                                   }];

    [self setUpBNBOffscreenEffectPlayer];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    UIInterfaceOrientation orientation = UIApplication.sharedApplication.statusBarOrientation;
    BOOL isLandscape = orientation != UIDeviceOrientationPortrait;
    CGSize size = CGSizeMake(self.view.bounds.size.width, self.view.bounds.size.width * 16 / 9);
    if (isLandscape) {
        size = CGSizeMake(self.view.bounds.size.height * 16 / 9, self.view.bounds.size.height);
    }
    CGFloat left = isLandscape ? self.view.safeAreaInsets.left : 0;
    // TODO:
    self.rtcEAGLVideoView.frame = CGRectMake(left, 0, size.width, size.height);
    // Flip horizontaly, mirror
    // self.rtcEAGLVideoView.transform = CGAffineTransformMakeScale(-1, 1);
}

- (void)setUpBNBOffscreenEffectPlayer
{
    // Path to effects, see copy section of project
    NSString* effectsPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/effects"];
    // Path to BNB resources (NN models)
    NSString* bundleRoot = [NSBundle mainBundle].bundlePath;
    NSArray<NSString*>* dir = @[[NSString stringWithFormat:@"%@/bnb-resources", bundleRoot], effectsPath];

    // Initialize Banuba SDK
    [BNBUtilityManager initialize:dir clientToken:BANUBA_SDK_KEY];

    // Create Offscreen Effect Player
    self.effectPlayer = [[BNBOffscreenEffectPlayer alloc] initWithEffectWidth:EffectPlayerSize.width andHeight:EffectPlayerSize.height manualAudio:false];

    // Load effect
    self.effectLoaded = NO;
    [self.effectPlayer loadEffect:@"Afro"
                       completion:^{
                         self.effectLoaded = YES;
                       }];
}

- (AVCaptureDevice*)findDeviceForPosition:(AVCaptureDevicePosition)position
{
    NSArray<AVCaptureDevice*>* captureDevices = [RTCCameraVideoCapturer captureDevices];
    if (captureDevices.count == 0){
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                        reason:@"Cannot find device that supports video capture. Take into the attention, that webRTC doesn't support such devices for simulator. That is why this sample cannot be run in Xcode Simulator."
                        userInfo:nil];
    }
    for (AVCaptureDevice* device in captureDevices) {
        if (device.position == position) {
            return device;
        }
    }
    return captureDevices[0];
}

- (AVCaptureDeviceFormat*)selectFormatForDevice:(AVCaptureDevice*)device
{
    NSArray<AVCaptureDeviceFormat*>* formats =
        [RTCCameraVideoCapturer supportedFormatsForDevice:device];
    AVCaptureDeviceFormat* selectedFormat = nil;
    int currentDiff = INT_MAX;

    for (AVCaptureDeviceFormat* format in formats) {
        CMVideoDimensions dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        int diff = fabs(EffectPlayerSize.height - dimension.width) + fabs(EffectPlayerSize.width - dimension.height);
        if (diff < currentDiff) {
            selectedFormat = format;
            currentDiff = diff;
        }
    }

    NSAssert(selectedFormat != nil, @"No suitable capture format found.");
    return selectedFormat;
}

- (int)selectFpsForFormat:(AVCaptureDeviceFormat*)format
{
    Float64 maxFramerate = 0;
    for (AVFrameRateRange* fpsRange in format.videoSupportedFrameRateRanges) {
        if (fpsRange.minFrameRate < 30 && fpsRange.maxFrameRate >= 30) {
            maxFramerate = 30;
        } else {
            maxFramerate = fmax(maxFramerate, fpsRange.maxFrameRate);
        }
    }
    return (int) maxFramerate;
}

- (void)dealloc
{
    [_cameraVideoCapturer stopCapture];
    self.effectPlayer = nil;
}

#pragma mark - setter/getter

- (RTCVideoSource*)videoSource
{
    if (!_videoSource) {
        _videoSource = [self.factory videoSource];
    }
    return _videoSource;
}

- (RTCVideoTrack*)rtcTrack
{
    if (!_rtcTrack) {
        _rtcTrack = [self.factory videoTrackWithSource:self.videoSource trackId:@"com.banuba.sdk.WebRTCViewController"];
    }
    return _rtcTrack;
}

- (RTCPeerConnectionFactory*)factory
{
    if (!_factory) {
        id<RTCVideoEncoderFactory> encoderFactory = [[RTCDefaultVideoEncoderFactory alloc] init];
        id<RTCVideoDecoderFactory> decoderFactory = [[RTCDefaultVideoDecoderFactory alloc] init];
        _factory = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory
                                                             decoderFactory:decoderFactory];
    }
    return _factory;
}

- (RTCCameraVideoCapturer*)cameraVideoCapturer
{
    if (!_cameraVideoCapturer) {
        _cameraVideoCapturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:self];
        [_cameraVideoCapturer captureSession].sessionPreset = AVCaptureSessionPresetiFrame1280x720;
    }
    return _cameraVideoCapturer;
}

- (UIView<RTCVideoRenderer>*)rtcEAGLVideoView
{
    if (!_rtcEAGLVideoView) {
        _rtcEAGLVideoView = [[RTCEAGLVideoView alloc] init];
    }
    return _rtcEAGLVideoView;
}

#pragma mark - Delegate hadlers

- (void)statusBarOrientationDidChange:(NSNotification*)notification
{
    _orientation = UIApplication.sharedApplication.statusBarOrientation;
    [self rotateEffectPlayerSurface:_orientation];
}

- (void)capturer:(RTCVideoCapturer*)capturer didCaptureVideoFrame:(RTCVideoFrame*)frame
{
    RTCVideoFrame* fixedFrame = [[RTCVideoFrame alloc] initWithBuffer:frame.buffer
                                                             rotation:[self fixFrameRotation:_orientation usingFrontCamera:[self isUsingFrontCamera:capturer]]
                                                          timeStampNs:frame.timeStampNs];

    if (self.effectLoaded) {
        CVPixelBufferRef pixelBuffer = nil;
        // Get pixelBuffer.
        if ([fixedFrame.buffer isKindOfClass:RTCCVPixelBuffer.class]) {
            RTCCVPixelBuffer* rtcCVPixelBuffer = (RTCCVPixelBuffer*) fixedFrame.buffer;
            if (rtcCVPixelBuffer != nil) {
                pixelBuffer = rtcCVPixelBuffer.pixelBuffer;
            }
        }

        // Process pixelBuffer.
        if (pixelBuffer != nil) {
            __weak typeof(self) weakSelf = self;

            size_t width = CVPixelBufferGetWidth(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);
            CGSize size = CGSizeMake(width, height);
            EpImageFormat imageFormat;
            memset(&imageFormat, 0, sizeof(EpImageFormat));
            imageFormat.imageSize = size;
            imageFormat.orientation = [self getImageOrientation:self.orientation];
            imageFormat.resultedImageOrientation = [self getResultImageOrientation:self.orientation];
            imageFormat.needAlphaInOutput = NO;
            imageFormat.isMirrored = YES;

            [self.effectPlayer processImage:pixelBuffer
                                 withFormat:&imageFormat
                             frameTimestamp:[NSNumber numberWithLong:fixedFrame.timeStampNs]
                                 completion:^(CVPixelBufferRef _Nullable reusltPixelBuffer, NSNumber* _Nonnull timeStamp) {
                                   if (reusltPixelBuffer == nil) {
                                       // Frame was dropped by OEP, because unable to process (e.g. too many frames in the queue).
                                       return;
                                   }
                                   // Forward frame to RTCVideoSource.
                                   __strong typeof(weakSelf) strongSelf = weakSelf;
                                   if ([strongSelf.videoSource respondsToSelector:@selector(capturer:didCaptureVideoFrame:)] && reusltPixelBuffer != nil) {
                                       RTCCVPixelBuffer* rtcPixelBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:reusltPixelBuffer];
                                       RTCVideoFrame* videoFrame = [[RTCVideoFrame alloc] initWithBuffer:rtcPixelBuffer
                                                                                                rotation:fixedFrame.rotation
                                                                                             timeStampNs:fixedFrame.timeStampNs];
                                       [strongSelf.videoSource capturer:capturer didCaptureVideoFrame:videoFrame];
                                   }
                                 }];
        }
    } else {
        [self.videoSource capturer:capturer didCaptureVideoFrame:fixedFrame];
    }
}

#pragma mark - Frame Orientation helpers

- (BOOL)isUsingFrontCamera:(RTCVideoCapturer*)capture
{
    RTCCameraVideoCapturer* cameraCapture = (RTCCameraVideoCapturer*) capture;
    if (cameraCapture) {
        AVCaptureDeviceInput* deviceInput = (AVCaptureDeviceInput*) cameraCapture.captureSession.inputs.firstObject;
        return AVCaptureDevicePositionFront == deviceInput.device.position;
    }
    return true;
}

- (void)rotateEffectPlayerSurface:(UIInterfaceOrientation)statusBarOrientation
{
    switch (statusBarOrientation) {
        case UIInterfaceOrientationLandscapeLeft:
        case UIInterfaceOrientationLandscapeRight:
            [self.effectPlayer surfaceChanged:EffectPlayerSize.height withHeight:EffectPlayerSize.width];
            break;
        case UIInterfaceOrientationPortrait:
        case UIInterfaceOrientationPortraitUpsideDown:
        default:
            [self.effectPlayer surfaceChanged:EffectPlayerSize.width withHeight:EffectPlayerSize.height];
            break;
    }
}

- (RTCVideoRotation)fixFrameRotation:(UIInterfaceOrientation)statusBarOrientation usingFrontCamera:(BOOL)isFrontCamera
{
    RTCVideoRotation rotation = RTCVideoRotation_90;
    switch (statusBarOrientation) {
        case UIInterfaceOrientationPortrait:
            rotation = RTCVideoRotation_90;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            rotation = RTCVideoRotation_270;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            rotation = isFrontCamera ? RTCVideoRotation_0 : RTCVideoRotation_180;
            break;
        case UIInterfaceOrientationLandscapeRight:
            rotation = isFrontCamera ? RTCVideoRotation_180 : RTCVideoRotation_0;
            break;
        default:
            break;
    }
    return rotation;
}

- (EPOrientation)getImageOrientation:(UIInterfaceOrientation)orientation
{
    EPOrientation resultOrientation = EPOrientationAngles0;
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            resultOrientation = EPOrientationAngles90;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            resultOrientation = EPOrientationAngles0;
            break;
        case UIInterfaceOrientationLandscapeRight:
            resultOrientation = EPOrientationAngles180;
            break;
        default:
            break;
    }
    return resultOrientation;
}

- (EPOrientation)getResultImageOrientation:(UIInterfaceOrientation)orientation
{
    EPOrientation resultOrientation = EPOrientationAngles0;
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            resultOrientation = EPOrientationAngles90;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            resultOrientation = EPOrientationAngles0;
            break;
        case UIInterfaceOrientationLandscapeRight:
            resultOrientation = EPOrientationAngles180;
            break;
        default:
            break;
    }
    return resultOrientation;
}

@end
