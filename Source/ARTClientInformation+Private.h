#import <Ably/ARTClientInformation.h>

extern NSString *const ARTClientInformation_libraryVersion;

@interface ARTClientInformation (Private)

+ (NSString *)libraryAgentIdentifier;
+ (NSString *)platformAgentIdentifier;

@end
