import Ably
import Nimble
import Quick
import Aspects

// Swift isn't yet smart enough to do this automatically when bridging Objective-C APIs
extension ARTRestChannels: Sequence {
    public func makeIterator() -> NSFastEnumerationIterator {
        return NSFastEnumerationIterator(self.iterate())
    }
}

private func beAChannel(named expectedValue: String) -> Predicate<ARTChannel> {
    return Predicate.define("be a channel with name \"\(expectedValue)\"") { actualExpression, msg -> PredicateResult in
        let actualValue = try! actualExpression.evaluate()
        let m = msg.appended(details: "\"\(actualValue?.name ?? "nil")\" instead")
        return PredicateResult(status: PredicateStatus(bool: actualValue?.name == expectedValue), message: m)
    }
}
        private var client: ARTRest!
        private var channelName: String!

        private let cipherParams: ARTCipherParams? = nil

class RestClientChannels: QuickSpec {

override class var defaultTestSuite : XCTestSuite {
    let _ = client
    let _ = channelName
    let _ = cipherParams

    return super.defaultTestSuite
}

    override func spec() {

        beforeEach {
print("START HOOK: RestClientChannels.beforeEach")

            client = ARTRest(key: "fake:key")
            channelName = ProcessInfo.processInfo.globallyUniqueString
print("END HOOK: RestClientChannels.beforeEach")

        }

        describe("RestClient") {
            context("channels") {
                // RSN1
                it("should return collection of channels") {
                    let _: ARTRestChannels = client.channels
                }

                // RSN3
                context("get") {
                    // RSN3a
                    it("should return a channel") {
                        let channel = client.channels.get(channelName).internal
                        expect(channel).to(beAChannel(named: channelName))

                        let sameChannel = client.channels.get(channelName).internal
                        expect(sameChannel).to(beIdenticalTo(channel))
                    }

                    // RSN3b
                    it("should return a channel with the provided options") {
                        let options = ARTChannelOptions(cipher: cipherParams)
                        let channel = client.channels.get(channelName, options: options)

                        expect(channel.internal).to(beAChannel(named: channelName))
                        expect(channel.internal.options).to(beIdenticalTo(options))
                    }

                    // RSN3b
                    it("should not replace the options on an existing channel when none are provided") {
                        let options = ARTChannelOptions(cipher: cipherParams)
                        let channel = client.channels.get(channelName, options: options).internal

                        let newButSameChannel = client.channels.get(channelName).internal

                        expect(newButSameChannel).to(beIdenticalTo(channel))
                        expect(newButSameChannel.options).to(beIdenticalTo(options))
                    }

                    // RSN3c
                    it("should replace the options on an existing channel when new ones are provided") {
                        let channel = client.channels.get(channelName).internal
                        let oldOptions = channel.options

                        let newOptions = ARTChannelOptions(cipher: cipherParams)
                        let newButSameChannel = client.channels.get(channelName, options: newOptions).internal

                        expect(newButSameChannel).to(beIdenticalTo(channel))
                        expect(newButSameChannel.options).to(beIdenticalTo(newOptions))
                        expect(newButSameChannel.options).notTo(beIdenticalTo(oldOptions))
                    }
                }

                // RSN2
                context("channelExists") {
                    it("should check if a channel exists") {
                        expect(client.channels.exists(channelName)).to(beFalse())

                        client.channels.get(channelName)

                        expect(client.channels.exists(channelName)).to(beTrue())
                    }
                }

                // RSN4
                context("releaseChannel") {
                    it("should release a channel") {
                        weak var channel: ARTRestChannelInternal!

                        autoreleasepool {
                            channel = client.channels.get(channelName).internal

                            expect(channel).to(beAChannel(named: channelName))
                            client.channels.release(channel.name)
                        }

                        expect(channel).to(beNil())
                    }
                }

                // RSN2
                it("should be enumerable") {
                    let channels = [
                        client.channels.get(channelName).internal,
                        client.channels.get(String(channelName.reversed())).internal
                    ]

                    for channel in client.channels {
                        expect(channels).to(contain((channel as! ARTRestChannel).internal))
                    }
                }
            }
        }
    }
}
