#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCStreamOutputType) {
    SCStreamOutputTypeScreen = 0,
    SCStreamOutputTypeAudio = 1,
    SCStreamOutputTypeMic = 2
};

typedef NS_ENUM(NSInteger, SCContentSharingPickerMode) {
    SCContentSharingPickerModeDisplay = 0,
    SCContentSharingPickerModeWindow = 1,
    SCContentSharingPickerModeApplication = 2
};

@class SCStream;
@class SCContentFilter;

@interface SCContentFilter : NSObject
@property (nonatomic, readonly) CGRect contentRect;
@property (nonatomic, readonly) float pointPixelScale;
@end

@interface SCStreamConfiguration : NSObject
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) BOOL capturesAudio;
@end

@protocol SCStreamDelegate <NSObject>
@optional
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error NS_SWIFT_NAME(stream(_:didStopWithError:));
@end

@protocol SCStreamOutput <NSObject>
@optional
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type NS_SWIFT_NAME(stream(_:didOutputSampleBuffer:of:));
@end

@interface SCStream : NSObject
- (instancetype)initWithFilter:(SCContentFilter *)filter configuration:(SCStreamConfiguration *)configuration delegate:(nullable id<SCStreamDelegate>)delegate;
- (BOOL)addStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type sampleHandlerQueue:(nullable dispatch_queue_t)sampleHandlerQueue error:(NSError **)error NS_SWIFT_NAME(addStreamOutput(_:type:sampleHandlerQueue:));
- (void)startCaptureWithCompletionHandler:(nullable void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(startCapture(completionHandler:));
- (void)stopCaptureWithCompletionHandler:(nullable void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(stopCapture(completionHandler:));
@end

@interface SCContentSharingPickerConfiguration : NSObject
@property (nonatomic) BOOL showsMicrophoneControl;
@property (nonatomic) BOOL showsCameraControl;
@end

@class SCContentSharingPicker;

@protocol SCContentSharingPickerObserver <NSObject>
@optional
- (void)contentSharingPicker:(SCContentSharingPicker *)picker didCancelForStream:(nullable SCStream *)stream NS_SWIFT_NAME(contentSharingPicker(_:didCancelFor:));
- (void)contentSharingPicker:(SCContentSharingPicker *)picker didUpdateWithFilter:(SCContentFilter *)filter forStream:(nullable SCStream *)stream NS_SWIFT_NAME(contentSharingPicker(_:didUpdateWith:for:));
- (void)contentSharingPickerStartDidFailWithError:(NSError *)error NS_SWIFT_NAME(contentSharingPickerStartDidFailWithError(_:));
@end

@interface SCContentSharingPicker : NSObject
@property (class, nonatomic, readonly) SCContentSharingPicker *sharedPicker NS_SWIFT_NAME(shared);
@property (nonatomic, getter=isActive) BOOL active;
@property (nonatomic, readonly) BOOL isAvailable;
@property (nonatomic, copy) SCContentSharingPickerConfiguration *defaultConfiguration;

- (void)addObserver:(id<SCContentSharingPickerObserver>)observer NS_SWIFT_NAME(add(_:));
- (void)removeObserver:(id<SCContentSharingPickerObserver>)observer NS_SWIFT_NAME(remove(_:));
- (void)presentUsing:(SCContentSharingPickerMode)mode NS_SWIFT_NAME(present(using:));
@end

NS_ASSUME_NONNULL_END
