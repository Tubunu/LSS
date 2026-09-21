#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreGraphics/CoreGraphics.h>

@interface SCContentFilter : NSObject
@property (nonatomic, readonly) CGRect contentRect;
@property (nonatomic, readonly) float pointPixelScale;
@end
@implementation SCContentFilter
@end

@interface SCStreamConfiguration : NSObject
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) BOOL capturesAudio;
@end
@implementation SCStreamConfiguration
@end

@interface SCStream : NSObject
@end
@implementation SCStream
- (instancetype)initWithFilter:(id)filter configuration:(id)config delegate:(id)del { return [super init]; }
- (BOOL)addStreamOutput:(id)output type:(NSInteger)type sampleHandlerQueue:(id)queue error:(NSError **)err { return YES; }
- (void)startCaptureWithCompletionHandler:(void (^)(NSError *))handler { if (handler) handler(nil); }
- (void)stopCaptureWithCompletionHandler:(void (^)(NSError *))handler { if (handler) handler(nil); }
@end

@interface SCContentSharingPickerConfiguration : NSObject
@property (nonatomic) BOOL showsMicrophoneControl;
@property (nonatomic) BOOL showsCameraControl;
@end
@implementation SCContentSharingPickerConfiguration
@end

@interface SCContentSharingPicker : NSObject
@property (class, nonatomic, readonly) SCContentSharingPicker *sharedPicker;
@property (nonatomic, getter=isActive) BOOL active;
@property (nonatomic, readonly) BOOL isAvailable;
@property (nonatomic, copy) SCContentSharingPickerConfiguration *defaultConfiguration;
@end
@implementation SCContentSharingPicker
+ (instancetype)sharedPicker { return [SCContentSharingPicker new]; }
- (void)addObserver:(id)observer {}
- (void)removeObserver:(id)observer {}
- (void)presentUsing:(NSInteger)mode {}
@end
