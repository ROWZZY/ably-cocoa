# [Ably](https://www.ably.com) iOS, tvOS and macOS Objective-C and Swift client library SDK

[![Check Pod](https://github.com/ably/ably-cocoa/actions/workflows/check-pod.yaml/badge.svg)](https://github.com/ably/ably-cocoa/actions/workflows/check-pod.yaml)
[![Integration Test: iOS 14.4](https://github.com/ably/ably-cocoa/actions/workflows/integration-test-iOS14_4.yaml/badge.svg)](https://github.com/ably/ably-cocoa/actions/workflows/integration-test-iOS14_4.yaml)
[![Integration Test: macOS 10.15](https://github.com/ably/ably-cocoa/actions/workflows/integration-test-macOS10_15.yaml/badge.svg)](https://github.com/ably/ably-cocoa/actions/workflows/integration-test-macOS10_15.yaml)
[![Integration Test: tvOS 14.3](https://github.com/ably/ably-cocoa/actions/workflows/integration-test-tvOS14_3.yaml/badge.svg)](https://github.com/ably/ably-cocoa/actions/workflows/integration-test-tvOS14_3.yaml)

[![CocoaPods](https://img.shields.io/cocoapods/v/Ably.svg)](https://cocoapods.org/pods/Ably)
[![SPM Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fably%2Fably-cocoa%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ably/ably-cocoa)
[![SPM Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fably%2Fably-cocoa%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ably/ably-cocoa)

_[Ably](https://ably.com) is the platform that powers synchronized digital experiences in realtime. Whether attending an event in a virtual venue, receiving realtime financial information, or monitoring live car performance data – consumers simply expect realtime digital experiences as standard. Ably provides a suite of APIs to build, extend, and deliver powerful digital experiences in realtime for more than 250 million devices across 80 countries each month. Organizations like Bloomberg, HubSpot, Verizon, and Hopin depend on Ably’s platform to offload the growing complexity of business-critical realtime data synchronization at global scale. For more information, see the [Ably documentation](https://ably.com/docs)._

This is an iOS, tvOS and macOS Objective-C and Swift client library SDK for Ably, written in Objective-C. The library currently targets the [Ably client library features spec](https://www.ably.com/docs/client-lib-development-guide/features/) Version 1.2. You can jump to the '[Known Limitations](#known-limitations)' section to see the features this client library does not yet support or [view our client library SDKs feature support matrix](https://www.ably.com/download/sdk-feature-support-matrix) to see the list of all the available features.

## Supported platforms

This SDK is compatible with projects that target:

- iOS 10.0+
- tvOS 10.0+
- macOS 10.12+

We maintain compatibility and explicitly support these platform versions.

We do not explicitly maintain compatibility with older platform versions. Any known incompatibilities with older versions can be found [here](https://github.com/ably/ably-cocoa/issues?q=is%3Aissue+is%3Aopen+label%3A%22compatibility%22).

If you find any issues with unsupported platform versions, please [raise an issue](https://github.com/ably/ably-cocoa/issues) in this repository or [contact Ably customer support](https://support.ably.com) for advice.

### Continuous Integration Testing

We perform CI testing on the following operating systems:

- iOS 16.0
- tvOS 16.1
- The version of macOS specified by [GitHub Actions’ `macos-latest` runner image](https://github.com/actions/runner-images#available-images).

## Known Limitations

This client library is currently *not compatible* with some of the Ably features:

| Feature |
| :--- |
| [Custom transportParams](https://ably.com/docs/realtime/usage#client-options) |
| [Remember fallback host during failures](https://ably.com/docs/realtime/usage#client-options) | 
| [ErrorInfo URLs to help debug issues](https://ably.com/docs/realtime/types#error-info) |

## Documentation

Visit [ably.com/docs](https://www.ably.com/docs) for a complete API reference and more examples.

## Installation Guide

You can install Ably for iOS and macOS through Package Manager, CocoaPods, Carthage or manually.

### Installing through [Swift Package Manager](https://swift.org/package-manager/)
- To install the `ably-cocoa` package in your **Xcode Project**: 
    - Paste `https://github.com/ably/ably-cocoa` in the *Swift Packages* search box. ( *Xcode project*  &rarr;  *Swift Packages..* . &rarr; `+` button)
    - Select the `Ably` SDK for your target.
    - [This apple guide](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app) explains the steps in more detail.
- To install the `ably-cocoa` package in another **Swift Package**, then add the following to your `Package.Swift`:
```swift
 .package(url: "https://github.com/ably/ably-cocoa", from: "1.2.18"),
```
### Installing through [CocoaPods](https://cocoapods.org/)

If you intend to use Swift, using `use_frameworks!` in your Podfile is recommended (this will create a Framework that can be used in Swift natively).

Add this line to your application's Podfile:

    # For Xcode 7.3 and newer
    pod 'Ably', '>= 1.2'

And then install the dependency:

    $ pod install

### Installing through [Carthage](https://github.com/Carthage/Carthage/)

Add this line to your application's Cartfile:

    # For Xcode 7.3 and newer
    github "ably/ably-cocoa" >= 1.2

And then run  

- for **iOS**: `carthage update --use-xcframeworks --platform iOS --no-use-binaries`
- for **macOS**: `carthage update --use-xcframeworks --platform macOS --no-use-binaries`
- for **tvOS**: `carthage update --use-xcframeworks --platform tvOS --no-use-binaries`

to build the framework and drag the built (in `[PROJECT_ROOT]/Carthage/Build`)

- `Ably.xcframework` 
- `AblyDeltaCodec.xcframework`
- `msgpack.xcframework`

into your Xcode project.

If you see, for example, a `dyld: Library not loaded: @rpath/AblyDeltaCodec.framework/AblyDeltaCodec` error, then most likely you forgot to add all the dependencies to your project. You have more detailed information [here](https://github.com/Carthage/Carthage#adding-frameworks-to-an-application).

*NOTE:*
*For **macOS** target you have to select `Do Not Embed` for `Ably.xcframework` in `General` tab for your target, and make sure the `Ably.xcframework` is on the `Link Binary With Libraries` list in `Build Phases` tab.*

### Manual installation 

1. Get the code from GitHub [from the release page](https://github.com/ably/ably-cocoa/releases/tag/1.2.18), or clone it to get the latest, unstable and possibly underdocumented version: `git clone git@github.com:ably/ably-cocoa.git`
2. Drag the directory `ably-cocoa/ably-cocoa` into your project as a group.
3. Ably depends on our [MessagePack Fork](https://github.com/ably-forks/msgpack-objective-C) 0.2.0; get it [from the releases page](https://github.com/ably-forks/msgpack-objective-C/releases/tag/0.2.0-ably-1) and link it into your project.

## Thread-safety

The library makes the following thread-safety guarantees:

* The whole public interface can be safely accessed, both for read and writing, from any thread.
* "Value" objects (e. g. `ARTTokenDetails`, data from messages) returned by the library can be safely read from and written to.
* Objects passed to the library must not be mutated afterwards. They can be safely passed again, or read from; they won't be written to by the library.

All internal operations are dispatched to a single serial GCD queue. You can specify a custom queue for this, which must be serial, with `ARTClientOptions.internalDispatchQueue`.

All calls to callbacks provided by the user are dispatched to the main queue by default.
This allows you to react to Ably's output by doing UI operations directly. You can specify a different queue with `ARTClientOptions.dispatchQueue`. It shouldn't be the same queue as the `ARTClientOptions.internalDispatchQueue`, since that can lead to deadlocks.

## Push Notifications

If you haven’t yet, you should first check the detailed [documentation](https://www.ably.com/docs/general/push). An [example app for push notifications](https://github.com/ably/push-example-ios) is also available.

### Activation and device registration

For more information, see [Push Notifications - Device activation and subscription](https://ably.com/docs/general/push/activate-subscribe).

**`ARTPushRegistererDelegate`** defines 3 delegate methods to handle the outcome of push activation, deactivation and update events. By default, the Ably SDK will check if `UIApplication.sharedApplication.delegate` conforms to `ARTPushRegistererDelegate`, and call the delegate methods when appropriate. Therefore, specifying the `ARTPushRegistererDelegate` is optional. To use a different class implementing `ARTPushRegistererDelegate`, you must provide this class to Ably, by setting the `ARTClientOptions#pushRegistererDelegate` delegate. In SwiftUI applications, you must set the `ARTClientOptions#pushRegistererDelegate` delegate property.

Do not forget that `ARTPush` has two corresponding methods that you should call from yours [application(_:didRegisterForRemoteNotificationsWithDeviceToken:)](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622958-application) and [application(_:didFailToRegisterForRemoteNotificationsWithError:)](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622962-application), passing to them also an `ARTRest` or `ARTRealtime` instance, configured with the authentication setup and other options you need:

```
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    ARTPush.didRegisterForRemoteNotifications(withDeviceToken: deviceToken, rest: rest)
}

func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    ARTPush.didFailToRegisterForRemoteNotificationsWithError(error, rest: rest)
}
```

Only one instance of `ARTRest` or `ARTRealtime` at a time must be [activated for receiving push notifications](https://www.ably.com/docs/general/push/activate-subscribe). Having more than one activated instance at a time may have unexpected consequences.

### macOS & tvOS

Be aware that Push Notifications are currently unsupported for macOS and tvOS. You can only use the [Push Admin](https://www.ably.com/docs/general/push/admin) functionalities, for example:

```swift
let recipient: [String: Any] = [
    "clientId": "C04BC116-8004-4D78-A71F-8CA3122734DB"
]
let data: [String: Any] = [
    "notification": [
        "title": "Hello from Ably!",
        "body": "Example push notification from Ably."
    ],
    "data": [
        "foo": "bar",
        "baz": "qux"
    ]
]
realtime.push.admin.publish(recipient, data: data) { error in
    print("Push published:", error ?? "nil")
}
```

Available demos: [macOS](https://github.com/ably/demo-macos) and [tvOS](https://github.com/ably/demo-tvos).

## Using the Realtime API

<!--
NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE N
**********************************************
==============================================

(Sorry for the noise.)

Those examples need to be kept in sync with:

Spec/ReadmeExamples.swift

==============================================
**********************************************
OTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NOTE NO
-->

### Introduction

All examples assume a client has been created as follows:

**Swift**

```swift
// basic auth with an API key
let client = ARTRealtime(key: "xxxx:xxxx")

// using token auth
let client = ARTRealtime(token: "xxxx")
```

**Objective-C**

```objective-c
// basic auth with an API key
ARTRealtime* client = [[ARTRealtime alloc] initWithKey:@"xxxx:xxxx"];

// using token auth
ARTRealtime* client = [[ARTRealtime alloc] initWithToken:@"xxxx"];
```

### Connection

Instantiating `ARTRealtime` starts a connection by default. You can catch connection success or error by listening to the connection's state changes:

**Swift**

```swift
client.connection.on { stateChange in
    let stateChange = stateChange!
    switch stateChange.current {
    case .Connected:
        print("connected!")
    case .Failed:
        print("failed! \(stateChange.reason)")
    default:
        break
    }
}
```

**Objective-C**

```objective-c
[client.connection on:^(ARTConnectionStateChange *stateChange) {
    switch (stateChange.current) {
        case ARTRealtimeConnected:
            NSLog(@"connected!");
            break;
        case ARTRealtimeFailed:
            NSLog(@"failed! %@", stateChange.reason);
            break;
        default:
            break;
    }
}];
```

You can also connect manually by setting the appropriate option.

**Swift**

```swift
let options = ARTClientOptions(key: "xxxx:xxxx")
options.autoConnect = false
let client = ARTRealtime(options: options)
client.connection.connect()
```

**Objective-C**

```objective-c
ARTClientOptions *options = [[ARTClientOptions alloc] initWithKey:@"xxxx:xxxx"];
options.autoConnect = false;
ARTRealtime *client = [[ARTRealtime alloc] initWithOptions:options];
[client.connection connect];
```

### Subscribing to a channel

Given:

**Swift**

```swift
let channel = client.channels.get("test")
```

**Objective-C**

```objective-c
ARTRealtimeChannel *channel = [client.channels get:@"test"];
```

Subscribe to all events:

**Swift**

```swift
channel.subscribe { message in
    print(message.name)
    print(message.data)
}
```

**Objective-C**

```objective-c
[channel subscribe:^(ARTMessage *message) {
    NSLog(@"%@", message.name);
    NSLog(@"%@", message.data);
}];
```

Only certain events:

**Swift**

```swift
channel.subscribe("myEvent") { message in
    print(message.name)
    print(message.data)
}
```

**Objective-C**

```objective-c
[channel subscribe:@"myEvent" callback:^(ARTMessage *message) {
    NSLog(@"%@", message.name);
    NSLog(@"%@", message.data);
}];
```

### Subscribing to a channel in delta mode

Subscribing to a channel in delta mode enables [delta compression](https://www.ably.com/docs/realtime/channels/channel-parameters/deltas). This is a way for a client to subscribe to a channel so that message payloads sent contain only the difference (ie the delta) between the present message and the previous message on the channel.

Request a Vcdiff formatted delta stream using channel options when you get the channel:
 
**Swift**

```swift
let channelOptions = ARTRealtimeChannelOptions()
channelOptions.params = [
    "delta": "vcdiff"
]

let channel = client.channels.get("test", options: channelOptions)
```

**Objective-C**

```objective-c
ARTRealtimeChannelOptions *channelOptions = [[ARTRealtimeChannelOptions alloc] init];
channelOptions.params = @{
    @"delta": @"vcdiff"
};

ARTRealtimeChannel *channel = [client.channels get:@"test" options:channelOptions];
```

Beyond specifying channel options, the rest is transparent and requires no further changes to your application. The `message.data` instances that are delivered to your subscription callback continue to contain the values that were originally published.

If you would like to inspect the `ARTMessage` instances in order to identify whether the `data` they present was rendered from a delta message from Ably then you can see if `message.extras["delta"]["format"]` equals `"vcdiff"`.

### Publishing to a channel

**Swift**

```swift
channel.publish("greeting", data: "Hello World!")
```

**Objective-C**

```objective-c
[channel publish:@"greeting" data:@"Hello World!"];
```

### Querying the history

**Swift**

```swift
channel.history { messagesPage, error in
    let messagesPage = messagesPage!
    print(messagesPage.items)
    print(messagesPage.items.first)
    print((messagesPage.items.first as? ARTMessage)?.data) // payload for the message
    print(messagesPage.items.count) // number of messages in the current page of history
    messagesPage.next { nextPage, error in
        // retrieved the next page in nextPage
    }
    print(messagesPage.hasNext) // true, there are more pages
}
```

**Objective-C**

```objective-c
[channel history:^(ARTPaginatedResult<ARTMessage *> *messagesPage, ARTErrorInfo *error) {
    NSLog(@"%@", messagesPage.items);
    NSLog(@"%@", messagesPage.items.firstObject);
    NSLog(@"%@", messagesPage.items.firstObject.data); // payload for the message
    NSLog(@"%lu", (unsigned long)[messagesPage.items count]); // number of messages in the current page of history
    [messagesPage next:^(ARTPaginatedResult<ARTMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
    NSLog(@"%d", messagesPage.hasNext); // true, there are more pages
}];
```

### Presence on a channel

**Swift**

```swift
let channel = client.channels.get("test")

channel.presence.enter("john.doe") { errorInfo in
    channel.presence.get { members, errorInfo in
        // members is the array of members present
    }
}
```

**Objective-C**

```objective-c
[channel.presence enter:@"john.doe" callback:^(ARTErrorInfo *errorInfo) {
    [channel.presence get:^(ARTPaginatedResult<ARTPresenceMessage *> *result, ARTErrorInfo *error) {
        // members is the array of members present
    }];
}];
```

### Querying the presence history

**Swift**

```swift
channel.presence.history { presencePage, error in
    let presencePage = presencePage!
    if let first = presencePage.items.first as? ARTPresenceMessage {
        print(first.action) // Any of .Enter, .Update or .Leave
        print(first.clientId) // client ID of member
        print(first.data) // optional data payload of member
        presencePage.next { nextPage, error in
            // retrieved the next page in nextPage
        }
    }
}
```

**Objective-C**

```objective-c
[channel.presence history:^(ARTPaginatedResult<ARTPresenceMessage *> *presencePage, ARTErrorInfo *error) {
    ARTPresenceMessage *first = (ARTPresenceMessage *)presencePage.items.firstObject;
    NSLog(@"%lu", (unsigned long)first.action); // Any of ARTPresenceEnter, ARTPresenceUpdate or ARTPresenceLeave
    NSLog(@"%@", first.clientId); // client ID of member
    NSLog(@"%@", first.data); // optional data payload of member
    [presencePage next:^(ARTPaginatedResult<ARTPresenceMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
}];
```

### Using the `authCallback`

A callback to call to obtain a signed token request.  
`ARTClientOptions` and `ARTRealtime` objects can be instantiated as follow:

**Swift**

```swift
let clientOptions = ARTClientOptions()
clientOptions.authCallback = { params, callback in
    getTokenRequestJSONFromYourServer(params) { json, error in
        //handle error
        do {
            callback(try ARTTokenRequest.fromJson(json), nil)
        } catch let error as NSError {
            callback(nil, error)
        }
    }
}

let client = ARTRealtime(options:clientOptions)
```

**Objective-C**

```objective-c
ARTClientOptions *clientOptions = [[ARTClientOptions alloc] init];
clientOptions.authCallback = ^(ARTTokenParams *params, void(^callback)(id<ARTTokenDetailsCompatible>, NSError*)) {
    [self getTokenRequestJSONFromYourServer:params completion:^(NSDictionary *json, NSError *error) {
        //handle error
        ARTTokenRequest *tokenRequest = [ARTTokenRequest fromJson:json error:&error];
        callback(tokenRequest, error);
    }];
};

ARTRealtime *client = [[ARTRealtime alloc] initWithOptions:clientOptions];
```

## Using the REST API

### Introduction

All examples assume a client and/or channel has been created as follows:

**Swift**

```swift
let client = ARTRest(key: "xxxx:xxxx")
let channel = client.channels.get("test")
```

**Objective-C**

```objective-c
ARTRest *client = [[ARTRest alloc] initWithKey:@"xxxx:xxxx"];
ARTRestChannel *channel = [client.channels get:@"test"];
```

### Publishing a message to a channel

**Swift**

```swift
channel.publish("myEvent", data: "Hello!")
```

**Objective-C**

```objective-c
[channel publish:@"myEvent" data:@"Hello!"];
```

### Querying the history

**Swift**

```swift
channel.history { messagesPage, error in
    let messagesPage = messagesPage!
    print(messagesPage.items.first)
    print((messagesPage.items.first as? ARTMessage)?.data) // payload for the message
    messagesPage.next { nextPage, error in
        // retrieved the next page in nextPage
    }
    print(messagesPage.hasNext) // true, there are more pages
}
```

**Objective-C**

```objective-c
[channel history:^(ARTPaginatedResult<ARTMessage *> *messagesPage, ARTErrorInfo *error) {
    NSLog(@"%@", messagesPage.items.firstObject);
    NSLog(@"%@", messagesPage.items.firstObject.data); // payload for the message
    NSLog(@"%lu", (unsigned long)[messagesPage.items count]); // number of messages in the current page of history
    [messagesPage next:^(ARTPaginatedResult<ARTMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
    NSLog(@"%d", messagesPage.hasNext); // true, there are more pages
}];
```

### Presence on a channel

**Swift**

```swift
channel.presence.get { membersPage, error in
    let membersPage = membersPage!
    print(membersPage.items.first)
    print((membersPage.items.first as? ARTPresenceMessage)?.data) // payload for the message
    membersPage.next { nextPage, error in
        // retrieved the next page in nextPage
    }
    print(membersPage.hasNext) // true, there are more pages
}
```

**Objective-C**

```objective-c
[channel.presence get:^(ARTPaginatedResult<ARTPresenceMessage *> *membersPage, ARTErrorInfo *error) {
    NSLog(@"%@", membersPage.items.firstObject);
    NSLog(@"%@", membersPage.items.firstObject.data); // payload for the message
    [membersPage next:^(ARTPaginatedResult<ARTMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
    NSLog(@"%d", membersPage.hasNext); // true, there are more pages
}];
```

### Querying the presence history

**Swift**

```swift
channel.presence.history { presencePage, error in
    let presencePage = presencePage!
    if let first = presencePage.items.first as? ARTPresenceMessage {
        print(first.clientId) // client ID of member
        presencePage.next { nextPage, error in
            // retrieved the next page in nextPage
        }
    }
}
```

**Objective-C**

```objective-c
[channel.presence history:^(ARTPaginatedResult<ARTPresenceMessage *> *presencePage, ARTErrorInfo *error) {
    ARTPresenceMessage *first = (ARTPresenceMessage *)presencePage.items.firstObject;
    NSLog(@"%@", first.clientId); // client ID of member
    NSLog(@"%@", first.data); // optional data payload of member
    [presencePage next:^(ARTPaginatedResult<ARTPresenceMessage *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
}];
```

### Generate token

**Swift**

```swift
client.auth.requestToken(nil, withOptions: nil) { tokenDetails, error in
    let tokenDetails = tokenDetails!
    print(tokenDetails.token) // "xVLyHw.CLchevH3hF....MDh9ZC_Q"
    let client = ARTRest(token: tokenDetails.token)
}
```

**Objective-C**

```objective-c
[client.auth requestToken:nil withOptions:nil callback:^(ARTTokenDetails *tokenDetails, NSError *error) {
    NSLog(@"%@", tokenDetails.token); // "xVLyHw.CLchevH3hF....MDh9ZC_Q"
    ARTRest *client = [[ARTRest alloc] initWithToken:tokenDetails.token];
}];
```

### Fetching your application's stats

**Swift**

```swift
client.stats { statsPage, error in
    let statsPage = statsPage!
    print(statsPage.items.first)
    statsPage.next { nextPage, error in
        // retrieved the next page in nextPage
    }
}
```

**Objective-C**

```objective-c
[client stats:^(ARTPaginatedResult<ARTStats *> *statsPage, ARTErrorInfo *error) {
    NSLog(@"%@", statsPage.items.firstObject);
    [statsPage next:^(ARTPaginatedResult<ARTStats *> *nextPage, ARTErrorInfo *error) {
        // retrieved the next page in nextPage
    }];
}];
```

### Fetching the Ably service time

**Swift**

```swift
client.time { time, error in
    print(time) // 2016-02-09 03:59:24 +0000
}
```

**Objective-C**

```objective-c
[client time:^(NSDate *time, NSError *error) {
    NSLog(@"%@", time); // 2016-02-09 03:59:24 +0000
}];
```

## Support, feedback and troubleshooting

Please visit https://support.ably.com/ for access to our knowledgebase and to ask for any assistance.

You can also view the [community reported Github issues](https://github.com/ably/ably-cocoa/issues).

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for details.
