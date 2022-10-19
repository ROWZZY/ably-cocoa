#import <Foundation/Foundation.h>
#import <Ably/ARTPush.h>

@class ARTDevicePushDetails;

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains the properties of a device registered for push notifications.
 */
@interface ARTDeviceDetails : NSObject

/**
 * A unique ID generated by the device.
 */
@property (strong, nonatomic) ARTDeviceId *id;

/**
 * The client ID the device is connected to Ably with.
 */
@property (strong, nullable, nonatomic) NSString *clientId;

/**
 * The `ARTDevicePlatform` associated with the device. Describes the platform the device uses, such as `android` or `ios`.
 */
@property (strong, nonatomic) NSString *platform;

/**
 * The `ARTDeviceFormFactor` object associated with the device. Describes the type of the device, such as `phone` or `tablet`.
 */
@property (strong, nonatomic) NSString *formFactor;

/**
 * A JSON object of key-value pairs that contains metadata for the device.
 */
@property (strong, nonatomic) NSDictionary<NSString *, NSString *> *metadata;

/**
 * The `ARTDevicePushDetails` object associated with the device. Describes the details of the push registration of the device.
 */
@property (strong, nonatomic) ARTDevicePushDetails *push;

/**
 * A unique device secret generated by the Ably SDK.
 */
@property (strong, nullable, nonatomic) ARTDeviceSecret *secret;

/// :nodoc:
- (instancetype)init;

/// :nodoc:
- (instancetype)initWithId:(ARTDeviceId *)deviceId;

@end

NS_ASSUME_NONNULL_END
