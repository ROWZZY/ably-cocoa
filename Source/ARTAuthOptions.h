#import <Foundation/Foundation.h>

#import <Ably/ARTTypes.h>

@class ARTAuth;
@class ARTTokenDetails;

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
@protocol ARTTokenDetailsCompatible <NSObject>
- (void)toTokenDetails:(ARTAuth *)auth callback:(ARTTokenDetailsCallback)callback;
@end

@interface NSString (ARTTokenDetailsCompatible) <ARTTokenDetailsCompatible>
@end

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * Passes authentication-specific properties in authentication requests to Ably. Properties set using `ARTAuthOptions` are used instead of the default values set when the client library is instantiated, as opposed to being merged with them.
 * END CANONICAL PROCESSED DOCSTRING
 */
@interface ARTAuthOptions : NSObject<NSCopying>

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * The full API key string, as obtained from the [Ably dashboard](https://ably.com/dashboard). Use this option if you wish to use Basic authentication, or wish to be able to issue Ably Tokens without needing to defer to a separate entity to sign Ably `ARTTokenRequest`s. Read more about [Basic authentication](https://ably.com/docs/core-features/authentication#basic-authentication).
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nonatomic, copy, nullable) NSString *key;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * An authenticated token. This is a token string obtained from the `-[ARTTokenDetails token]` property of a `ARTTokenDetails` component of an Ably `ARTTokenRequest` response, or a JSON Web Token satisfying [the Ably requirements for JWTs](https://ably.com/docs/core-features/authentication#ably-jwt).
 * This option is mostly useful for testing: since tokens are short-lived, in production you almost always want to use an authentication method that enables the client library to renew the token automatically when the previous one expires, such as `authUrl` or `authCallback`. Read more about [Token authentication](https://ably.com/docs/core-features/authentication#token-authentication).
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nonatomic, copy, nullable) NSString *token;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * An authenticated `ARTTokenDetails` object (most commonly obtained from an Ably Token Request response). This option is mostly useful for testing: since tokens are short-lived, in production you almost always want to use an authentication method that enables the client library to renew the token automatically when the previous one expires, such as `authUrl` or `authCallback`. Use this option if you wish to use Token authentication. Read more about [Token authentication](https://ably.com/docs/core-features/authentication#token-authentication).
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nonatomic, strong, nullable) ARTTokenDetails *tokenDetails;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * Called when a new token is required. The role of the callback is to obtain a fresh token, one of: an Ably Token string (in plain text format); a signed `ARTTokenRequest`; a `ARTTokenDetails` (in JSON format); an [Ably JWT](https://ably.com/docs/core-features/authentication#ably-jwt). See [the authentication documentation](https://ably.com/docs/realtime/authentication) for details of the Ably `ARTTokenRequest` format and associated API calls.
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nonatomic, copy, nullable) ARTAuthCallback authCallback;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * A URL that the library may use to obtain a token string (in plain text format), or a signed `ARTTokenRequest` or `ARTTokenDetails` (in JSON format) from.
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nonatomic, strong, nullable) NSURL *authUrl;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * The HTTP verb to use for any request made to the `authUrl`, either `GET` or `POST`. The default value is `GET`.
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nonatomic, copy, null_resettable) NSString *authMethod;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * A set of key-value pair headers to be added to any request made to the `authUrl`. Useful when an application requires these to be added to validate the request or implement the response. If the `authHeaders` object contains an `authorization` key, then `withCredentials` is set on the XHR request.
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nonatomic, copy, nullable) NSStringDictionary *authHeaders;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * A set of key-value pair params to be added to any request made to the `authUrl`. When the `authMethod` is `GET`, query params are added to the URL, whereas when `authMethod` is `POST`, the params are sent as URL encoded form data. Useful when an application requires these to be added to validate the request or implement the response.
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nonatomic, copy, nullable) NSArray<NSURLQueryItem *> *authParams;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * If `true`, the library queries the Ably servers for the current time when issuing `ARTTokenRequest`s instead of relying on a locally-available time of day. Knowing the time accurately is needed to create valid signed Ably `ARTTokenRequest`s, so this option is useful for library instances on auth servers where for some reason the server clock cannot be kept synchronized through normal means, such as an [NTP daemon](https://en.wikipedia.org/wiki/Ntpd). The server is queried for the current time once per client library instance (which stores the offset from the local clock), so if using this option you should avoid instancing a new version of the library for each request. The default is `false`.
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (nonatomic, assign, nonatomic) BOOL queryTime;

/**
 * BEGIN CANONICAL PROCESSED DOCSTRING
 * When `true`, forces token authentication to be used by the library. If a `clientId` is not specified in the `ARTClientOptions` or `ARTTokenParams`, then the Ably Token issued is [anonymous](https://ably.com/docs/core-features/authentication#identified-clients).
 * END CANONICAL PROCESSED DOCSTRING
 */
@property (readwrite, assign, nonatomic) BOOL useTokenAuth;

/// :nodoc:
- (instancetype)init;

/// :nodoc:
- (instancetype)initWithKey:(NSString *)key;

/// :nodoc:
- (instancetype)initWithToken:(NSString *)token;

/// :nodoc:
- (instancetype)initWithTokenDetails:(ARTTokenDetails *)tokenDetails;

/// :nodoc:
- (NSString *)description;

/// :nodoc:
- (ARTAuthOptions *)mergeWith:(ARTAuthOptions *)precedenceOptions;

/// :nodoc:
- (BOOL)isMethodGET;

/// :nodoc:
- (BOOL)isMethodPOST;

@end

NS_ASSUME_NONNULL_END
