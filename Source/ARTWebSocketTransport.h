#import <Foundation/Foundation.h>

#import <Ably/ARTRealtimeTransport.h>

@class ARTClientOptions;
@class ARTRest;
@class ARTLog;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWebSocketTransport : NSObject <ARTRealtimeTransport>

- (instancetype)init UNAVAILABLE_ATTRIBUTE;

@property (readonly, strong, nonatomic) NSString *resumeKey;
@property (readonly, strong, nonatomic) NSString *recoveryKey;
@property (readonly, strong, nonatomic) ARTLog *protocolMessagesLogger;

@end

NS_ASSUME_NONNULL_END
