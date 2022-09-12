#import <Foundation/Foundation.h>
#import <Ably/ARTDeviceDetails.h>

@class ARTDeviceIdentityTokenDetails;

NS_ASSUME_NONNULL_BEGIN

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * Contains the device identity token and secret of a device. `ARTLocalDevice` extends `ARTDeviceDetails`.
 * END CANONICAL PROCESSED DOCSTRING
 */
@interface ARTLocalDevice : ARTDeviceDetails

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * A unique device identity token used to communicate with APNS.
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nullable, nonatomic, readonly) ARTDeviceIdentityTokenDetails *identityTokenDetails;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * A unique device secret generated by the Ably SDK.
 * END CANONICAL PROCESSED DOCSTRING
 *
 * BEGIN LEGACY DOCSTRING # useful?
 * Device secret generated using random data with sufficient entropy. It's a sha256 digest encoded with base64.
 * END LEGACY DOCSTRING
 */
@property (strong, nullable, nonatomic) ARTDeviceSecret *secret;

/// :nodoc:
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
