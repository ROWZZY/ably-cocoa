import Ably
import Aspects
import Nimble
import XCTest

private let attachResumeExpectedValues: [ARTRealtimeChannelState: Bool] = [
    .initialized: false,
    .attached: true,
    .detaching: false,
    .failed: false,
]
private var rtl6c2TestsClient: ARTRealtime!
private var rtl6c2TestsChannel: ARTRealtimeChannel!

private func rtl16c2TestsPublish(_ done: @escaping () -> Void) {
    rtl6c2TestsChannel.publish(nil, data: "message") { error in
        expect(error).to(beNil())
        expect(rtl6c2TestsClient.connection.state).to(equal(ARTRealtimeConnectionState.connected))
        done()
    }
}

private var options: ARTClientOptions!
private var rtl6c4TestsClient: ARTRealtime!
private var rtl6c4TestsChannel: ARTRealtimeChannel!

private let previousConnectionStateTtl = ARTDefault.connectionStateTtl()

private func setupDependencies() {
    if options == nil {
        options = AblyTests.commonAppSetup()
        options.suspendedRetryTimeout = 0.3
        options.autoConnect = false
    }
}

private func rtl6c4TestsPublish(_ done: @escaping () -> Void) {
    rtl6c4TestsChannel.publish(nil, data: "message") { error in
        expect(error).toNot(beNil())
        done()
    }
}

/*
 This test makes a deep assumption about the content of these two files,
 specifically the format of the first message in the items array.
 */
private func testHandlesDecodingErrorInFixture(_ cryptoFixtureFileName: String, channelName: String) {
    let options = AblyTests.commonAppSetup()
    options.autoConnect = false
    options.logHandler = ARTLog(capturingOutput: true)
    let client = ARTRealtime(options: options)
    client.internal.setTransport(TestProxyTransport.self)
    client.connect()
    defer { client.dispose(); client.close() }

    let (keyData, ivData, messages) = AblyTests.loadCryptoTestData(cryptoFixtureFileName)
    let testMessage = messages[0]

    let cipherParams = ARTCipherParams(algorithm: "aes", key: keyData as ARTCipherKeyCompatible, iv: ivData)
    let channelOptions = ARTRealtimeChannelOptions(cipher: cipherParams)
    let channel = client.channels.get(channelName, options: channelOptions)

    let transport = client.internal.transport as! TestProxyTransport

    transport.setListenerBeforeProcessingOutgoingMessage { protocolMessage in
        if protocolMessage.action == .message {
            expect(protocolMessage.messages![0].data as? String).to(equal(testMessage.encrypted.data))
            expect(protocolMessage.messages![0].encoding).to(equal(testMessage.encrypted.encoding))
        }
    }

    transport.setBeforeIncomingMessageModifier { protocolMessage in
        if protocolMessage.action == .message {
            expect(protocolMessage.messages![0].data as? NSObject).to(equal(AblyTests.base64ToData(testMessage.encrypted.data) as NSObject?))
            expect(protocolMessage.messages![0].encoding).to(equal("utf-8/cipher+aes-\(cryptoFixtureFileName.suffix(3))-cbc"))

            // Force an error decoding a message
            protocolMessage.messages![0].encoding = "bad_encoding_type"
        }
        return protocolMessage
    }

    waitUntil(timeout: testTimeout) { done in
        let partlyDone = AblyTests.splitDone(2, done: done)

        channel.subscribe(testMessage.encoded.name) { message in
            expect(message.data as? NSObject).to(equal(AblyTests.base64ToData(testMessage.encrypted.data) as NSObject?))

            let logs = options.logHandler.captured
            let line = logs.reduce("") { $0 + "; " + $1.toString() } // Reduce in one line

            expect(line).to(contain("Failed to decode data: unknown encoding: 'bad_encoding_type'"))

            partlyDone()
        }

        channel.on(.update) { stateChange in
            guard let error = stateChange.reason else {
                return
            }
            expect(error.message).to(contain("Failed to decode data: unknown encoding: 'bad_encoding_type'"))
            expect(error).to(beIdenticalTo(channel.errorReason))
            partlyDone()
        }

        channel.publish(testMessage.encoded.name, data: testMessage.encoded.data)
    }
}

private func testWithUntilAttach(_ untilAttach: Bool, channelName: String) {
    let options = AblyTests.commonAppSetup()
    let client = ARTRealtime(options: options)
    defer { client.dispose(); client.close() }
    let channel = client.channels.get(channelName)

    let testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
    client.internal.rest.httpExecutor = testHTTPExecutor

    let query = ARTRealtimeHistoryQuery()
    query.untilAttach = untilAttach

    channel.attach()
    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

    waitUntil(timeout: testTimeout) { done in
        expect {
            try channel.history(query) { _, errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }.toNot(throwError { err in fail("\(err)"); done() })
    }

    let queryString = testHTTPExecutor.requests.last!.url!.query

    if query.untilAttach {
        expect(queryString).to(contain("fromSerial=\(channel.internal.attachSerial!)"))
    } else {
        expect(queryString).toNot(contain("fromSerial"))
    }
}

class RealtimeClientChannelTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = attachResumeExpectedValues
        _ = rtl6c2TestsClient
        _ = rtl6c2TestsChannel
        _ = options
        _ = rtl6c4TestsClient
        _ = rtl6c4TestsChannel
        _ = previousConnectionStateTtl

        return super.defaultTestSuite
    }

    class TotalMessages {
        static let expected = 50
        static var succeeded = 0
        static var failed = 0
        fileprivate init() {}
    }

    // RTL1
    func skipped__test__001__Channel__should_process_all_incoming_messages_and_presence_messages_as_soon_as_a_Channel_becomes_attached() {
        let options = AblyTests.commonAppSetup()
        let client1 = AblyTests.newRealtime(options)
        defer { client1.dispose(); client1.close() }
        
        let roomName = uniqueChannelName(prefix: "room")
        
        let channel1 = client1.channels.get(roomName)

        waitUntil(timeout: testTimeout) { done in
            channel1.presence.enterClient("Client 1", data: nil) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        options.clientId = "Client 2"
        let client2 = AblyTests.newRealtime(options)
        defer { client2.dispose(); client2.close() }
        let channel2 = client2.channels.get(roomName)

        channel2.subscribe("Client 1") { message in
            expect(message.data as? String).to(equal("message"))
        }

        waitUntil(timeout: testTimeout) { done in
            channel2.on(.attached) { _ in
                expect(channel2.state).to(equal(ARTRealtimeChannelState.attached))
                done()
            }
            channel2.attach()

            expect(channel2.presence.syncComplete).to(beFalse())
            expect(channel1.internal.presenceMap.members).to(haveCount(1))
            expect(channel2.internal.presenceMap.members).to(haveCount(0))
        }

        expect(channel2.presence.syncComplete).toEventually(beTrue(), timeout: testTimeout)

        expect(channel1.internal.presenceMap.members).to(haveCount(1))
        expect(channel2.internal.presenceMap.members).toEventually(haveCount(1), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel1.publish("message", data: nil) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel2.presence.enter(nil) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        expect(channel1.internal.presenceMap.members).toEventually(haveCount(2), timeout: testTimeout)
        expect(channel1.internal.presenceMap.members.keys).to(allPass { $0!.hasPrefix("\(channel1.internal.connectionId):Client") || $0!.hasPrefix("\(channel2.internal.connectionId):Client") })
        expect(channel1.internal.presenceMap.members.values).to(allPass { $0!.action == .present })

        expect(channel2.internal.presenceMap.members).toEventually(haveCount(2), timeout: testTimeout)
        expect(channel2.internal.presenceMap.members.keys).to(allPass { $0!.hasPrefix("\(channel1.internal.connectionId):Client") || $0!.hasPrefix("\(channel2.internal.connectionId):Client") })
        expect(channel2.internal.presenceMap.members["\(channel1.internal.connectionId):Client 1"]!.action).to(equal(ARTPresenceAction.present))
        expect(channel2.internal.presenceMap.members["\(channel2.internal.connectionId):Client 2"]!.action).to(equal(ARTPresenceAction.present))
    }

    // RTL2

    // RTL2a
    func test__003__Channel__EventEmitter__channel_states_and_events__should_implement_the_EventEmitter_and_emit_events_for_state_changes() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        expect(channel.internal.statesEventEmitter).to(beAKindOf(ARTEventEmitter<ARTEvent, ARTChannelStateChange>.self))

        var channelOnMethodCalled = false
        channel.internal.testSuite_injectIntoMethod(after: #selector(ARTEventEmitter<ARTEvent, ARTChannelStateChange>.on(_:))) {
            channelOnMethodCalled = true
        }

        // The `channel.on` should use `statesEventEmitter`
        var statesEventEmitterOnMethodCalled = false
        channel.internal.statesEventEmitter.testSuite_injectIntoMethod(after: #selector(ARTEventEmitter<ARTEvent, ARTChannelStateChange>.on(_:))) {
            statesEventEmitterOnMethodCalled = true
        }

        var emitCounter = 0
        channel.internal.statesEventEmitter.testSuite_injectIntoMethod(after: #selector(ARTEventEmitter<ARTEvent, ARTChannelStateChange>.emit(_:with:))) {
            emitCounter += 1
        }

        var states = [channel.state]
        waitUntil(timeout: testTimeout) { done in
            channel.on { stateChange in
                expect(stateChange.previous).to(equal(states.last))
                expect(channel.state).to(equal(stateChange.current))
                states += [stateChange.current]

                switch stateChange.current {
                case .attached:
                    expect(stateChange.event).to(equal(ARTChannelEvent.attached))
                    expect(stateChange.reason).to(beNil())
                    channel.detach()
                case .detached:
                    expect(stateChange.event).to(equal(ARTChannelEvent.detached))
                    guard let error = stateChange.reason else {
                        fail("Detach state change reason is nil"); done(); return
                    }
                    expect(error.message).to(contain("channel has detached"))
                    done()
                default:
                    break
                }
            }
            channel.attach()
        }

        expect(channelOnMethodCalled).to(beTrue())
        expect(statesEventEmitterOnMethodCalled).to(beTrue())
        expect(emitCounter).to(equal(4))

        if states.count != 5 {
            fail("Expecting 5 states; got \(states)")
            return
        }

        expect(states[0].rawValue).to(equal(ARTRealtimeChannelState.initialized.rawValue), description: "Should be INITIALIZED state")
        expect(states[1].rawValue).to(equal(ARTRealtimeChannelState.attaching.rawValue), description: "Should be ATTACHING state")
        expect(states[2].rawValue).to(equal(ARTRealtimeChannelState.attached.rawValue), description: "Should be ATTACHED state")
        expect(states[3].rawValue).to(equal(ARTRealtimeChannelState.detaching.rawValue), description: "Should be DETACHING state")
        expect(states[4].rawValue).to(equal(ARTRealtimeChannelState.detached.rawValue), description: "Should be DETACHED state")
    }

    // RTL2a
    func test__004__Channel__EventEmitter__channel_states_and_events__should_implement_the_EventEmitter_and_emit_events_for_FAILED_state_changes() {
        let options = AblyTests.clientOptions()
        options.token = getTestToken(capability: "{\"secret\":[\"subscribe\"]}")
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.on { stateChange in
                expect(channel.state).to(equal(stateChange.current))
                switch stateChange.current {
                case .attaching:
                    expect(stateChange.event).to(equal(ARTChannelEvent.attaching))
                    expect(stateChange.reason).to(beNil())
                    expect(stateChange.previous).to(equal(ARTRealtimeChannelState.initialized))
                case .failed:
                    guard let reason = stateChange.reason else {
                        fail("Reason is nil"); done(); return
                    }
                    expect(stateChange.event).to(equal(ARTChannelEvent.failed))
                    expect(reason.code) == ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue
                    expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attaching))
                    done()
                default:
                    break
                }
            }
            channel.attach()
        }
    }

    // RTL2a
    func test__005__Channel__EventEmitter__channel_states_and_events__should_implement_the_EventEmitter_and_emit_events_for_SUSPENDED_state_changes() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        client.simulateSuspended(beforeSuspension: { done in
            channel.once(.suspended) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attached))
                expect(stateChange.event).to(equal(ARTChannelEvent.suspended))
                expect(channel.state).to(equal(stateChange.current))
                done()
            }
        })
    }

    // RTL2g
    func test__006__Channel__EventEmitter__channel_states_and_events__can_emit_an_UPDATE_event() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        channel.on(.attached) { _ in
            fail("Should not emit Attached again")
        }
        defer {
            channel.off()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.on(.update) { stateChange in
                expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                expect(stateChange.previous).to(equal(channel.state))
                expect(stateChange.current).to(equal(channel.state))
                expect(stateChange.event).to(equal(ARTChannelEvent.update))
                expect(stateChange.resumed).to(beFalse())
                expect(stateChange.reason).to(beNil())
                done()
            }

            let attachedMessage = ARTProtocolMessage()
            attachedMessage.action = .attached
            attachedMessage.channel = channel.name
            client.internal.transport?.receive(attachedMessage)
        }
    }

    // RTL2g + https://github.com/ably/ably-cocoa/issues/1088
    func test__007__Channel__EventEmitter__channel_states_and_events__should_not_emit_detached_event_on_an_already_detached_channel() {
        let options = AblyTests.commonAppSetup()
        options.logLevel = .debug
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        channel.on { stateChange in
            expect(stateChange.current).toNot(equal(stateChange.previous))
        }
        defer {
            channel.off()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.detach { error in
                expect(error).to(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.closed) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
            client.close()
        }
    }

    // RTL2b
    func test__008__Channel__EventEmitter__channel_states_and_events__state_attribute_should_be_the_current_state_of_the_channel() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))

        channel.attach()
        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
    }

    // RTL2c
    func test__009__Channel__EventEmitter__channel_states_and_events__should_contain_an_ErrorInfo_object_with_details_when_an_error_occurs() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        let pmError = AblyTests.newErrorProtocolMessage()
        waitUntil(timeout: testTimeout) { done in
            channel.on(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                expect(error).to(equal(pmError.error))
                expect(channel.errorReason).to(equal(pmError.error))
                done()
            }
            AblyTests.queue.async {
                channel.internal.onError(pmError)
            }
        }
    }

    // RTL2d
    func test__010__Channel__EventEmitter__channel_states_and_events__a_ChannelStateChange_is_emitted_as_the_first_argument_for_every_channel_state_change() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.on { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(channel.state))
                expect(stateChange.previous).toNot(equal(channel.state))

                if stateChange.current == .attached {
                    done()
                }
            }
            channel.attach()
        }
        channel.off()

        waitUntil(timeout: testTimeout) { done in
            channel.once(.failed) { stateChange in
                expect(stateChange.reason).toNot(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.failed))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attached))
                done()
            }
            AblyTests.queue.async {
                channel.internal.onError(AblyTests.newErrorProtocolMessage())
            }
        }
    }

    // RTL2f
    func test__011__Channel__EventEmitter__channel_states_and_events__ChannelStateChange_will_contain_a_resumed_boolean_attribute_with_value__true__if_the_bit_flag_RESUMED_was_included() {
        let options = AblyTests.commonAppSetup()
        options.tokenDetails = getTestTokenDetails(ttl: 5.0)
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.on { stateChange in
                switch stateChange.current {
                case .attached:
                    expect(stateChange.resumed).to(beFalse())
                default:
                    expect(stateChange.resumed).to(beFalse())
                }
            }
            client.connection.once(.disconnected) { stateChange in
                channel.off()
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                expect(error.code) == ARTErrorCode.tokenExpired.intValue

                channel.on { stateChange in
                    if stateChange.current == .attached {
                        expect(stateChange.resumed).to(beTrue())
                        expect(stateChange.reason).to(beNil())
                        expect(stateChange.current).to(equal(ARTRealtimeChannelState.attached))
                        expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attached))
                        done()
                    }
                }
            }
            channel.attach()
        }
    }

    // RTL2f, TR4i
    func test__012__Channel__EventEmitter__channel_states_and_events__bit_flag_RESUMED_was_included() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.once(.attached) { stateChange in
                expect(stateChange.resumed).to(beFalse())
                expect(stateChange.reason).to(beNil())
                done()
            }
            channel.attach()
        }

        let attachedMessage = ARTProtocolMessage()
        attachedMessage.action = .attached
        attachedMessage.channel = channel.name
        attachedMessage.flags = 4 // Resumed

        waitUntil(timeout: testTimeout) { done in
            channel.once(.update) { stateChange in
                expect(stateChange.resumed).to(beTrue())
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.attached))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attached))
                done()
            }
            client.internal.transport?.receive(attachedMessage)
        }
    }

    // RTL3

    // RTL3a

    func test__017__Channel__connection_state__changes_to_FAILED__ATTACHING_channel_should_transition_to_FAILED() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]

        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))

        waitUntil(timeout: testTimeout) { done in
            let pmError = AblyTests.newErrorProtocolMessage()
            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error).to(equal(pmError.error))
                expect(channel.errorReason).to(beIdenticalTo(error))
                done()
            }
            client.internal.onError(pmError)
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
    }

    func test__018__Channel__connection_state__changes_to_FAILED__ATTACHED_channel_should_transition_to_FAILED() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let pmError = AblyTests.newErrorProtocolMessage()
            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error).to(equal(pmError.error))
                expect(channel.errorReason).to(equal(error))
                done()
            }
            client.internal.onError(pmError)
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
    }

    func test__019__Channel__connection_state__changes_to_FAILED__channel_being_released_waiting_for_DETACH_shouldn_t_crash__issue__918_() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        // Force the callback on .release below to be triggered by our
        // forced FAILED message, not by a DETACHED.
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.detached]

        var channel0Name = ""
        for i in 0 ..< 100 { // We need a few channels to trigger iterator invalidation.
            let channelName = uniqueChannelName(prefix: "channel\(i)")
            if i == 0 { channel0Name = channelName }
            let channel = client.channels.get(channelName)
            channel.attach() // No need to wait; ATTACHING state is good enough.
            expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attaching), timeout: testTimeout)
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.channels.release(channel0Name) { _ in
                partialDone()
            }

            AblyTests.queue.async {
                let pmError = AblyTests.newErrorProtocolMessage()
                client.internal.onError(pmError)
                partialDone()
            }
        }
    }

    // TO3g
    func test__020__Channel__connection_state__changes_to_FAILED__should_immediately_fail_if_not_in_the_connected_state() {
        let options = AblyTests.commonAppSetup()
        options.queueMessages = false
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            expect(client.connection.state).to(equal(.initialized))
            channel.publish(nil, data: "message") { error in
                expect(error?.code).to(equal(ARTErrorCode.invalidTransportHandle.intValue))
                expect(error?.message).to(contain("Invalid operation"))
                done()
            }
        }
        expect(channel.state).to(equal(.initialized))
        waitUntil(timeout: testTimeout) { done in
            client.connect()
            expect(client.connection.state).to(equal(.connecting))
            channel.publish(nil, data: "message") { error in
                expect(error?.code).to(equal(ARTErrorCode.invalidTransportHandle.intValue))
                expect(error?.message).to(contain("Invalid operation"))
                done()
            }
        }
        expect(channel.state).toEventually(equal(.attached), timeout: testTimeout)
    }

    // TO3g and https://github.com/ably/ably-cocoa/issues/1004
    func test__021__Channel__connection_state__changes_to_FAILED__should_keep_the_channels_attached_when_client_reconnected_successfully_and_queue_messages_is_disabled() {
        let options = AblyTests.commonAppSetup()
        options.queueMessages = false
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        client.internal.setTransport(TestProxyTransport.self)
        client.internal.setReachabilityClass(TestReachability.self)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
            client.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                done()
            }
        }

        expect(channel.state).to(equal(.attached))
        channel.on { stateChange in
            if stateChange.current != .attached {
                fail("Channel state should not change")
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                expect(stateChange.reason?.message).to(satisfyAnyOf(contain("unreachable host"), contain("network is down")))
                done()
            }
            client.simulateNoInternetConnection()
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(stateChange.previous).to(equal(.connecting))
                done()
            }
            client.simulateRestoreInternetConnection()
        }

        channel.off()
        expect(channel.state).to(equal(.attached))
    }

    // RTL3b

    func test__022__Channel__connection_state__changes_to_CLOSED__ATTACHING_channel_should_transition_to_DETACHED() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }
        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]

        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
        client.close()
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closing))
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.detached), timeout: testTimeout)
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closed))
    }

    func test__023__Channel__connection_state__changes_to_CLOSED__ATTACHED_channel_should_transition_to_DETACHED() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()

        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        client.close()
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closing))
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.detached), timeout: testTimeout)
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closed))
    }

    // RTL3c

    func test__024__Channel__connection_state__changes_to_SUSPENDED__ATTACHING_channel_should_transition_to_SUSPENDED() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
        client.internal.onSuspended()
        expect(channel.state).to(equal(ARTRealtimeChannelState.suspended))
    }

    func test__025__Channel__connection_state__changes_to_SUSPENDED__ATTACHED_channel_should_transition_to_SUSPENDED() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        client.internal.onSuspended()
        expect(channel.state).to(equal(ARTRealtimeChannelState.suspended))
    }

    func test__026__Channel__connection_state__changes_to_SUSPENDED__channel_being_released_waiting_for_DETACH_shouldn_t_crash__issue__918_() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        // Force the callback on .release below to be triggered by our
        // forced SUSPENDED message, not by a DETACHED.
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.detached]
        
        var channel0Name = ""
        for i in 0 ..< 100 { // We need a few channels to trigger iterator invalidation.
            let channelName = uniqueChannelName(prefix: "channel\(i)")
            if i == 0 { channel0Name = channelName }
            let channel = client.channels.get(channelName)
            channel.attach() // No need to wait; ATTACHING state is good enough.
            expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attaching), timeout: testTimeout)
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.channels.release(channel0Name) { _ in
                partialDone()
            }

            AblyTests.queue.async {
                client.internal.onSuspended()
                partialDone()
            }
        }
    }

    // RTL3d
    func test__013__Channel__connection_state__if_the_connection_state_enters_the_CONNECTED_state__then_a_SUSPENDED_channel_will_initiate_an_attach_operation() {
        let options = AblyTests.commonAppSetup()
        options.suspendedRetryTimeout = 1.0
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
            delay(0) {
                client.internal.onSuspended()
            }
        }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
    }

    // RTL3d
    func test__014__Channel__connection_state__if_the_attach_operation_for_the_channel_times_out_and_the_channel_returns_to_the_SUSPENDED_state() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        client.simulateSuspended(beforeSuspension: { done in
            channel.once(.suspended) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
        })
    }

    // RTL3d - https://github.com/ably/ably-cocoa/issues/881
    func test__015__Channel__connection_state__should_attach_successfully_and_remain_attached_when_the_connection_state_without_a_successful_recovery_gets_CONNECTED() {
        let options = AblyTests.commonAppSetup()
        options.disconnectedRetryTimeout = 0.5
        options.suspendedRetryTimeout = 3.0
        options.channelRetryTimeout = 0.5
        options.autoConnect = false

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.internal.setReachabilityClass(TestReachability.self)
        defer {
            client.simulateRestoreInternetConnection()
            client.dispose()
            client.close()
        }

        // Move to SUSPENDED
        let ttlHookToken = client.overrideConnectionStateTTL(3.0)
        defer { ttlHookToken.remove() }

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
            client.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                guard let error = stateChange.reason else {
                    fail("SUSPENDED reason should not be nil"); done(); return
                }
                expect(error.message).to(satisfyAnyOf(contain("network is down"), contain("unreachable host")))
                done()
            }
            client.simulateNoInternetConnection()
        }

        AblyTests.queue.async {
            // Do not resume
            client.simulateLostConnectionAndState()
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason?.code).to(equal(ARTErrorCode.unableToRecoverConnectionExpired.intValue)) // didn't resumed
                done()
            }
            client.simulateRestoreInternetConnection(after: 1.0)
        }

        waitUntil(timeout: testTimeout) { done in
            channel.once(.attached) { stateChange in
                expect(stateChange.resumed).to(beFalse())
                expect(stateChange.reason).to(beNil())
                channel.on(.suspended) { _ in
                    fail("Should not reach SUSPENDED state")
                }
                delay(3.0) {
                    // Wait some seconds to see if the channel doesn't change to SUSPENDED again
                    done()
                }
            }
        }
        channel.off()
    }

    // RTL3e
    func test__016__Channel__connection_state__if_the_connection_state_enters_the_DISCONNECTED_state__it_will_have_no_effect_on_the_channel_states() {
        let options = AblyTests.commonAppSetup()
        options.token = getTestToken(ttl: 5.0)
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        channel.once(.detached) { _ in
            fail("Should not reach the DETACHED state")
        }
        defer {
            channel.off()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { _ in
                expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                done()
            }
        }
    }

    // RTL4

    // RTL4a
    func test__027__Channel__attach__if_already_ATTACHED_or_ATTACHING_nothing_is_done() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        channel.attach { errorInfo in
            expect(errorInfo).to(beNil())
        }
        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))

        channel.attach { errorInfo in
            expect(errorInfo).to(beNil())
            expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
        }

        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { errorInfo in
                expect(errorInfo).to(beNil())
                expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                done()
            }
        }
    }

    // RTL4e
    func test__028__Channel__attach__if_the_user_does_not_have_sufficient_permissions_to_attach__then_the_channel_will_transition_to_FAILED_and_set_the_errorReason() {
        let options = AblyTests.commonAppSetup()
        options.token = getTestToken(key: options.key!, capability: "{\"restricted\":[\"*\"]}")
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.failed) { stateChange in
                expect(stateChange.reason?.code) == ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue
                partialDone()
            }
            channel.attach { error in
                guard let error = error else {
                    fail("Error is nil"); partialDone(); return
                }
                expect(error.code) == ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue
                partialDone()
            }
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
        expect(channel.errorReason?.code) == ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue
    }

    // RTL4g
    func test__029__Channel__attach__if_the_channel_is_in_the_FAILED_state__the_attach_request_sets_its_errorReason_to_null__and_proceeds_with_a_channel_attach() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        let errorMsg = AblyTests.newErrorProtocolMessage()
        errorMsg.channel = channel.name
        client.internal.onError(errorMsg)
        expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
        expect(channel.errorReason).toNot(beNil())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
        expect(channel.errorReason).to(beNil())
    }

    // RTL4b

    func test__039__Channel__attach__results_in_an_error_if_the_connection_state_is__CLOSING() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.closed]

        let channel = client.channels.get(uniqueChannelName())

        client.close()
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closing))

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).toNot(beNil())
                done()
            }
        }
    }

    func test__040__Channel__attach__results_in_an_error_if_the_connection_state_is__CLOSED() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        client.close()
        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.closed), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).toNot(beNil())
                done()
            }
        }
    }

    func test__041__Channel__attach__results_in_an_error_if_the_connection_state_is__SUSPENDED() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        client.internal.onSuspended()
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.suspended))
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).toNot(beNil())
                done()
            }
        }
    }

    func test__042__Channel__attach__results_in_an_error_if_the_connection_state_is__FAILED() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        client.internal.onError(AblyTests.newErrorProtocolMessage())
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.failed))
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).toNot(beNil())
                done()
            }
        }
    }

    // RTL4i

    func test__043__Channel__attach__happens_when_connection_is_CONNECTED_if_it_s_currently__INITIALIZED() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        expect(client.connection.state).to(equal(.initialized))
        waitUntil(timeout: testTimeout) { done in
            channel.on(.attached) { stateChange in
                expect(client.connection.state).to(equal(.connected))
                expect(stateChange.reason).to(beNil())
                done()
            }

            client.connect()
        }
        expect(channel.state).to(equal(.attached))
    }

    func test__044__Channel__attach__happens_when_connection_is_CONNECTED_if_it_s_currently__CONNECTING() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connect()
            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connecting))

            channel.attach { error in
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                expect(error).to(beNil())
                done()
            }
        }
    }

    func skipped__test__045__Channel__attach__happens_when_connection_is_CONNECTED_if_it_s_currently__DISCONNECTED() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            client.internal.onDisconnected()
            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.disconnected))

            channel.attach { error in
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                expect(error).to(beNil())
                done()
            }
        }
    }

    // RTL4c
    func test__030__Channel__attach__should_send_an_ATTACH_ProtocolMessage__change_state_to_ATTACHING_and_change_state_to_ATTACHED_after_confirmation() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()

        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
        expect(transport.protocolMessagesSent.filter { $0.action == .attach }).to(haveCount(1))

        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        expect(transport.protocolMessagesReceived.filter { $0.action == .attached }).to(haveCount(1))
    }

    // RTL4e
    func test__031__Channel__attach__should_transition_the_channel_state_to_FAILED_if_the_user_does_not_have_sufficient_permissions() {
        let options = AblyTests.clientOptions()
        options.token = getTestToken(capability: "{ \"main\":[\"subscribe\"] }")
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()

        waitUntil(timeout: testTimeout) { done in
            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error.code).to(equal(ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue))
                done()
            }
        }

        expect(channel.errorReason!.code).to(equal(ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue))
        expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
    }

    // RTL4f
    func test__032__Channel__attach__should_transition_the_channel_state_to_SUSPENDED_if_ATTACHED_ProtocolMessage_is_not_received() {
        let options = AblyTests.commonAppSetup()
        options.channelRetryTimeout = 1.0
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }
        transport.actionsIgnored += [.attached]

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { errorInfo in
                expect(errorInfo).toNot(beNil())
                expect(errorInfo).to(equal(channel.errorReason))
                done()
            }
        }
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.suspended), timeout: testTimeout)
        expect(channel.errorReason).toNot(beNil())

        transport.actionsIgnored = []
        // Automatically re-attached
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attaching) { stateChange in
                expect(stateChange.reason).to(beNil())
                partialDone()
            }
            channel.once(.attached) { stateChange in
                expect(stateChange.reason).to(beNil())
                partialDone()
            }
        }
    }

    func test__033__Channel__attach__if_called_with_a_callback_should_call_it_once_attached() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { errorInfo in
                expect(errorInfo).to(beNil())
                expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                done()
            }
        }
    }

    func test__034__Channel__attach__if_called_with_a_callback_and_already_attaching_should_call_the_callback_once_attached() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach()
            expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
            channel.attach { errorInfo in
                expect(errorInfo).to(beNil())
                expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                done()
            }
        }
    }

    func test__035__Channel__attach__if_called_with_a_callback_and_already_attached_should_call_the_callback_with_nil_error() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }
    }

    // RTL4h
    func test__036__Channel__attach__if_the_channel_is_in_a_pending_state_ATTACHING__do_the_attach_operation_after_the_completion_of_the_pending_request() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        var attachedCount = 0
        channel.on(.attached) { stateChange in
            expect(stateChange.reason).to(beNil())
            attachedCount += 1
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attaching) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.attaching))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.initialized))
                channel.attach()
                partialDone()
            }
            channel.once(.attached) { stateChange in
                expect(stateChange.reason).to(beNil())
                partialDone()
            }
            channel.attach()
        }

        expect(attachedCount).toEventually(equal(1), timeout: testTimeout)
    }

    // RTL4h
    func test__037__Channel__attach__if_the_channel_is_in_a_pending_state_DETACHING__do_the_attach_operation_after_the_completion_of_the_pending_request() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            channel.once(.detaching) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.detaching))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attached))
                channel.attach()
                partialDone()
            }
            channel.once(.detached) { stateChange in
                expect(stateChange.reason?.message).to(contain("channel has detached"))
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.detached))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.detaching))
                partialDone()
            }
            channel.once(.attaching) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.attaching))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.detached))
                partialDone()
            }
            channel.once(.attached) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.attached))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attaching))
                partialDone()
            }
            channel.detach()
        }
    }

    func test__038__Channel__attach__a_channel_in_DETACHING_can_actually_move_back_to_ATTACHED_if_it_fails_to_detach() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        // Force timeout
        transport.actionsIgnored = [.detached]

        waitUntil(timeout: testTimeout) { done in
            channel.detach { error in
                guard let error = error else {
                    fail("Reason error is nil"); return
                }
                expect(error.message).to(contain("timed out"))
                expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                done()
            }
        }
    }

    // RTL4j

    func test__046__Channel__attach__attach_resume__should_pass_attach_resume_flag_in_attach_message() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.publish]

        waitUntil(timeout: testTimeout) { done in
            channel.setOptions(channelOptions) { error in
                expect(error).to(beNil())
                done()
            }
        }

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        expect(attachMessages).to(haveCount(2))

        guard let firstAttach = attachMessages.first else {
            fail("First ATTACH message is missing"); return
        }
        expect(firstAttach.flags).to(equal(0))

        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttach.flags & Int64(ARTProtocolMessageFlag.attachResume.rawValue)).to(beGreaterThan(0)) // true
    }

    // RTL4j1
    func test__047__Channel__attach__attach_resume__should_have_correct_AttachResume_value() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        // Initialized
        expect(channel.internal.attachResume).to(equal(attachResumeExpectedValues[channel.state]))

        waitUntil(timeout: testTimeout) { done in
            channel.once(.failed) { _ in
                done()
            }
            AblyTests.queue.async {
                channel.internal.onError(AblyTests.newErrorProtocolMessage())
            }
        }

        // Failed
        expect(channel.internal.attachResume).to(equal(attachResumeExpectedValues[channel.state]))

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        // Attached
        expect(channel.internal.attachResume).to(equal(attachResumeExpectedValues[channel.state]))

        waitUntil(timeout: testTimeout) { done in
            channel.once(.detaching) { _ in
                // Detaching
                expect(channel.internal.attachResume).to(equal(attachResumeExpectedValues[channel.state]))
                done()
            }
            channel.detach()
        }
    }

    // RTL4j2
    func test__048__Channel__attach__attach_resume__should_encode_correctly_the_AttachResume_flag() {
        let options = AblyTests.commonAppSetup()

        let channelName = uniqueChannelName()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel.publish("test", data: nil) { error in
                expect(error).to(beNil())
                done()
            }
        }

        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.params = ["rewind": "1"]

        let client1 = ARTRealtime(options: options)
        defer { client1.dispose(); client1.close() }
        let channelWithAttachResume = client1.channels.get(channelName, options: channelOptions)
        channelWithAttachResume.internal.attachResume = true
        waitUntil(timeout: testTimeout) { done in
            channelWithAttachResume.subscribe { _ in
                fail("Should not receive the previously-published message")
            }
            channelWithAttachResume.attach { error in
                expect(error).to(beNil())
            }
            delay(2.0) {
                // Wait some seconds to confirm that the message is not received
                done()
            }
        }

        channelOptions.modes = [.subscribe]
        let client2 = ARTRealtime(options: options)
        defer { client2.dispose(); client2.close() }
        let channelWithoutAttachResume = client2.channels.get(channelName, options: channelOptions)
        waitUntil(timeout: testTimeout) { done in
            channelWithoutAttachResume.subscribe { message in
                expect(message.name).to(equal("test"))
                done()
            }
            channelWithoutAttachResume.attach()
        }
    }

    // RTL5a
    func test__049__Channel__detach__if_state_is_INITIALIZED_or_DETACHED_nothing_is_done() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
        channel.detach { errorInfo in
            expect(errorInfo).to(beNil())
        }
        expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))

        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attaching), timeout: testTimeout)

        channel.detach { errorInfo in
            expect(errorInfo).to(beNil())
            expect(channel.state).to(equal(ARTRealtimeChannelState.detached))
        }

        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.detached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.detach { errorInfo in
                expect(errorInfo).to(beNil())
                expect(channel.state).to(equal(ARTRealtimeChannelState.detached))
                done()
            }
        }
    }

    // RTL5i
    func test__050__Channel__detach__if_the_channel_is_in_a_pending_state_DETACHING__do_the_detach_operation_after_the_completion_of_the_pending_request() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        var detachedCount = 0
        channel.on(.detached) { _ in
            detachedCount += 1
        }

        var detachingCount = 0
        channel.on(.detaching) { _ in
            detachingCount += 1
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.detaching) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.detaching))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attached))
                channel.detach()
                partialDone()
            }
            channel.once(.detached) { stateChange in
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.detached))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.detaching))
                partialDone()
            }
            channel.detach()
        }

        waitUntil(timeout: testTimeout) { done in
            delay(1.0) {
                expect(detachedCount) == 1
                expect(detachingCount) == 1
                done()
            }
        }

        channel.off()
    }

    // RTL5i
    func test__051__Channel__detach__if_the_channel_is_in_a_pending_state_ATTACHING__do_the_detach_operation_after_the_completion_of_the_pending_request() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)
            channel.once(.attaching) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.attaching))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.initialized))
                channel.detach()
                partialDone()
            }
            channel.once(.attached) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.attached))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attaching))
                partialDone()
            }
            channel.once(.detaching) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.detaching))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attached))
                partialDone()
            }
            channel.attach()
        }
    }

    // RTL5b
    func test__052__Channel__detach__results_in_an_error_if_the_connection_state_is_FAILED() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        client.internal.onError(AblyTests.newErrorProtocolMessage())
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.failed))

        waitUntil(timeout: testTimeout) { done in
            channel.detach { errorInfo in
                expect(errorInfo!.code).to(equal(ARTErrorCode.channelOperationFailed.intValue))
                done()
            }
        }
    }

    // RTL5d
    func test__053__Channel__detach__should_send_a_DETACH_ProtocolMessage__change_state_to_DETACHING_and_change_state_to_DETACHED_after_confirmation() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        channel.detach()

        expect(channel.state).to(equal(ARTRealtimeChannelState.detaching))
        expect(transport.protocolMessagesSent.filter { $0.action == .detach }).to(haveCount(1))

        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.detached), timeout: testTimeout)
        expect(transport.protocolMessagesReceived.filter { $0.action == .detached }).to(haveCount(1))
    }

    // RTL5e
    func test__054__Channel__detach__if_called_with_a_callback_should_call_it_once_detached() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.detach { errorInfo in
                expect(errorInfo).to(beNil())
                expect(channel.state).to(equal(ARTRealtimeChannelState.detached))
                done()
            }
        }
    }

    // RTL5e
    func test__055__Channel__detach__if_called_with_a_callback_and_already_detaching_should_call_the_callback_once_detached() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.detach()
            expect(channel.state).to(equal(ARTRealtimeChannelState.detaching))
            channel.detach { errorInfo in
                expect(errorInfo).to(beNil())
                expect(channel.state).to(equal(ARTRealtimeChannelState.detached))
                done()
            }
        }
    }

    // RTL5e
    func test__056__Channel__detach__if_called_with_a_callback_and_already_detached_should_should_call_the_callback_with_nil_error() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        channel.detach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.detached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.detach { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }
    }

    // RTL5f
    func test__057__Channel__detach__if_a_DETACHED_is_not_received_within_the_default_realtime_request_timeout__the_detach_request_should_be_treated_as_though_it_has_failed_and_the_channel_will_return_to_its_previous_state() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.detached]

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        var callbackCalled = false
        channel.detach { error in
            guard let error = error else {
                fail("Error is nil"); return
            }
            expect(error.message).to(contain("timed out"))
            expect(error).to(equal(channel.errorReason))
            callbackCalled = true
        }
        let start = NSDate()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        expect(channel.errorReason).toNot(beNil())
        expect(callbackCalled).toEventually(beTrue(), timeout: testTimeout)
        let end = NSDate()
        expect(start.addingTimeInterval(1.0)).to(beCloseTo(end, within: 0.5))
    }

    // RTL5g

    func test__059__Channel__detach__results_in_an_error_if_the_connection_state_is__CLOSING() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.closed]

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        client.close()
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closing))

        waitUntil(timeout: testTimeout) { done in
            channel.detach { error in
                expect(error).toNot(beNil())
                done()
            }
        }
    }

    func test__060__Channel__detach__results_in_an_error_if_the_connection_state_is__FAILED() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        client.internal.onError(AblyTests.newErrorProtocolMessage())
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.failed))
        waitUntil(timeout: testTimeout) { done in
            channel.detach { error in
                expect(error).toNot(beNil())
                done()
            }
        }
    }

    // RTL5h

    func test__061__Channel__detach__happens_when_channel_is_ATTACHED_if_connection_is_currently__INITIALIZED() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach()
            expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.initialized))

            channel.detach { error in
                expect(error).to(beNil())
                done()
            }

            client.connect()
        }
    }

    func test__062__Channel__detach__happens_when_channel_is_ATTACHED_if_connection_is_currently__CONNECTING() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connect()
            channel.attach()
            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connecting))
            expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))

            channel.detach { error in
                expect(error).to(beNil())
                done()
            }
        }
    }

    func test__063__Channel__detach__happens_when_channel_is_ATTACHED_if_connection_is_currently__DISCONNECTED() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            client.internal.onDisconnected()
            channel.attach()
            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.disconnected))
            expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))

            channel.detach { error in
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                expect(error).to(beNil())
                done()
            }
        }
    }

    // RTL5j
    func test__058__Channel__detach__if_the_channel_state_is_SUSPENDED__the__detach__request_transitions_the_channel_immediately_to_the_DETACHED_state() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        channel.internal.setSuspended(ARTStatus.state(.ok))
        expect(channel.state).to(equal(ARTRealtimeChannelState.suspended))

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.detached) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(stateChange.current).to(equal(ARTRealtimeChannelState.detached))
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.suspended))
                partialDone()
            }
            channel.detach { error in
                expect(error).to(beNil())
                partialDone()
            }
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.detached))
    }

    // RTL6

    // RTL6a
    func test__064__Channel__publish__should_encode_messages_in_the_same_way_as_the_RestChannel() {
        let data = ["value": 1]

        let channelName = uniqueChannelName()
        
        let rest = ARTRest(options: AblyTests.commonAppSetup())
        let restChannel = rest.channels.get(channelName)

        var restEncodedMessage: ARTMessage?
        restChannel.internal.testSuite_getReturnValue(from: NSSelectorFromString("encodeMessageIfNeeded:error:")) { value in
            restEncodedMessage = value as? ARTMessage
        }

        waitUntil(timeout: testTimeout) { done in
            restChannel.publish(nil, data: data) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { realtime.close() }
        let realtimeChannel = realtime.channels.get(channelName)
        realtimeChannel.attach()
        expect(realtimeChannel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        var realtimeEncodedMessage: ARTMessage?
        realtimeChannel.internal.testSuite_getReturnValue(from: NSSelectorFromString("encodeMessageIfNeeded:error:")) { value in
            realtimeEncodedMessage = value as? ARTMessage
        }

        waitUntil(timeout: testTimeout) { done in
            realtimeChannel.publish(nil, data: data) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        expect(restEncodedMessage!.data as? NSObject).to(equal(realtimeEncodedMessage!.data as? NSObject))
        expect(restEncodedMessage!.data).toNot(beNil())
        expect(realtimeEncodedMessage!.data).toNot(beNil())
        expect(restEncodedMessage!.encoding).to(equal(realtimeEncodedMessage!.encoding))
        expect(restEncodedMessage!.encoding).toNot(beNil())
        expect(realtimeEncodedMessage!.encoding).toNot(beNil())
    }

    // RTL6b

    func test__067__Channel__publish__should_invoke_callback__when_the_message_is_successfully_delivered() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                if state == .connected {
                    let channel = client.channels.get(uniqueChannelName())
                    channel.on { stateChange in
                        if stateChange.current == .attached {
                            channel.publish(nil, data: "message") { errorInfo in
                                expect(errorInfo).to(beNil())
                                done()
                            }
                        }
                    }
                    channel.attach()
                }
            }
        }
    }

    func test__068__Channel__publish__should_invoke_callback__upon_failure() {
        let options = AblyTests.commonAppSetup()
        let channelname = uniqueChannelName()
        options.token = getTestToken(key: options.key, capability: "{ \"\(options.channelNamePrefix!)-\(channelname)\":[\"subscribe\"] }")
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                if state == .connected {
                    let channel = client.channels.get(channelname)
                    channel.on { stateChange in
                        if stateChange.current == .attached {
                            channel.publish(nil, data: "message") { errorInfo in
                                expect(errorInfo).toNot(beNil())
                                guard let errorInfo = errorInfo else {
                                    XCTFail("ErrorInfo is nil"); done(); return
                                }
                                // Unable to perform channel operation
                                expect(errorInfo.code).to(equal(ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue))
                                done()
                            }
                        }
                    }
                    channel.attach()
                }
            }
        }
    }

    func test__069__Channel__publish__should_invoke_callback__for_all_messages_published() {
        let options = AblyTests.commonAppSetup()
        
        let channelToSucceedName = uniqueChannelName(prefix: "channelToSucceed")
        let channelToFailName = uniqueChannelName(prefix: "channelToFail")
        
        options.token = getTestToken(key: options.key, capability: "{ \"\(options.channelNamePrefix!)-\(channelToSucceedName)\":[\"subscribe\", \"publish\"], \"\(options.channelNamePrefix!)-\(channelToFailName)\":[\"subscribe\"] }")
        
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        TotalMessages.succeeded = 0
        TotalMessages.failed = 0

        let channelToSucceed = client.channels.get(channelToSucceedName)
        channelToSucceed.on { stateChange in
            if stateChange.current == .attached {
                for index in 1 ... TotalMessages.expected {
                    channelToSucceed.publish(nil, data: "message\(index)") { errorInfo in
                        if errorInfo == nil {
                            TotalMessages.succeeded += 1
                            expect(index).to(equal(TotalMessages.succeeded), description: "Callback was invoked with an invalid sequence")
                        }
                    }
                }
            }
        }
        channelToSucceed.attach()

        let channelToFail = client.channels.get(channelToFailName)
        channelToFail.on { stateChange in
            if stateChange.current == .attached {
                for index in 1 ... TotalMessages.expected {
                    channelToFail.publish(nil, data: "message\(index)") { errorInfo in
                        if errorInfo != nil {
                            TotalMessages.failed += 1
                            expect(index).to(equal(TotalMessages.failed), description: "Callback was invoked with an invalid sequence")
                        }
                    }
                }
            }
        }
        channelToFail.attach()

        expect(TotalMessages.succeeded).toEventually(equal(TotalMessages.expected), timeout: testTimeout)
        expect(TotalMessages.failed).toEventually(equal(TotalMessages.expected), timeout: testTimeout)
    }

    // RTL6c

    // RTL6c1

    func test__071__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__ATTACHED_then_the_messages_should_be_published_immediately() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        channel.attach()

        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                done()
            }
            expect((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }).to(haveCount(1))
        }
    }

    func test__072__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__INITIALIZED_then_the_messages_should_be_published_immediately() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }
        let channel = client.channels.get(uniqueChannelName())
        expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                done()
            }
            expect((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }).to(haveCount(1))
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
    }

    func test__073__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__DETACHED_then_the_messages_should_be_published_immediately() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                done()
            }
        }
        waitUntil(timeout: testTimeout) { done in
            channel.detach { _ in
                done()
            }
        }
        expect(channel.state).to(equal(ARTRealtimeChannelState.detached))
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                done()
            }
            expect((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }).to(haveCount(1))
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.detached))
    }

    func test__074__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__ATTACHING_then_the_messages_should_be_published_immediately() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }
        channel.attach()
        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }
        transport.actionsIgnored += [.attached]

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                done()
            }
            expect((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }).to(haveCount(1))
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
    }

    func test__075__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__DETACHING_then_the_messages_should_be_published_immediately() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                done()
            }
        }
        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
        channel.detach()
        expect(channel.state).to(equal(ARTRealtimeChannelState.detaching))
        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }
        transport.actionsIgnored += [.detached]

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                done()
            }
            expect((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }).to(haveCount(1))
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.detaching))
    }

    // RTL6c2

    func beforeEach__Channel__publish__Connection_state_conditions__the_message(channelName: String) {
        let options = AblyTests.commonAppSetup()
        options.useTokenAuth = true
        options.autoConnect = false
        rtl6c2TestsClient = AblyTests.newRealtime(options)
        rtl6c2TestsChannel = rtl6c2TestsClient.channels.get(channelName)
        expect(rtl6c2TestsClient.internal.options.queueMessages).to(beTrue())
    }

    func afterEach__Channel__publish__Connection_state_conditions__the_message() { rtl6c2TestsClient.close() }

    func test__076__Channel__publish__Connection_state_conditions__the_message__should_be_queued_and_delivered_as_soon_as_the_connection_state_returns_to_CONNECTED_if_the_connection_is__INITIALIZED() {
        beforeEach__Channel__publish__Connection_state_conditions__the_message(channelName: uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            expect(rtl6c2TestsClient.connection.state).to(equal(ARTRealtimeConnectionState.initialized))
            rtl16c2TestsPublish(done)
            rtl6c2TestsClient.connect()
            expect(rtl6c2TestsClient.internal.queuedMessages).to(haveCount(1))
        }

        afterEach__Channel__publish__Connection_state_conditions__the_message()
    }

    func test__077__Channel__publish__Connection_state_conditions__the_message__should_be_queued_and_delivered_as_soon_as_the_connection_state_returns_to_CONNECTED_if_the_connection_is__CONNECTING() {
        beforeEach__Channel__publish__Connection_state_conditions__the_message(channelName: uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            rtl6c2TestsClient.connect()
            expect(rtl6c2TestsClient.connection.state).to(equal(ARTRealtimeConnectionState.connecting))
            rtl16c2TestsPublish(done)
            expect(rtl6c2TestsClient.internal.queuedMessages).to(haveCount(1))
        }

        afterEach__Channel__publish__Connection_state_conditions__the_message()
    }

    func test__078__Channel__publish__Connection_state_conditions__the_message__should_be_queued_and_delivered_as_soon_as_the_connection_state_returns_to_CONNECTED_if_the_connection_is__DISCONNECTED() {
        beforeEach__Channel__publish__Connection_state_conditions__the_message(channelName: uniqueChannelName())

        rtl6c2TestsClient.connect()
        expect(rtl6c2TestsClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c2TestsClient.internal.onDisconnected()

        waitUntil(timeout: testTimeout) { done in
            expect(rtl6c2TestsClient.connection.state).to(equal(ARTRealtimeConnectionState.disconnected))
            rtl16c2TestsPublish(done)
            expect(rtl6c2TestsClient.internal.queuedMessages).to(haveCount(1))
        }

        afterEach__Channel__publish__Connection_state_conditions__the_message()
    }

    func test__079__Channel__publish__Connection_state_conditions__the_message__should_NOT_be_queued_instead_it_should_be_published_if_the_channel_is__INITIALIZED() {
        beforeEach__Channel__publish__Connection_state_conditions__the_message(channelName: uniqueChannelName())

        rtl6c2TestsClient.connect()
        expect(rtl6c2TestsChannel.state).to(equal(ARTRealtimeChannelState.initialized))

        expect(rtl6c2TestsClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            rtl16c2TestsPublish(done)
            expect(rtl6c2TestsClient.internal.queuedMessages).to(haveCount(0))
            expect((rtl6c2TestsClient.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }).to(haveCount(1))
        }

        afterEach__Channel__publish__Connection_state_conditions__the_message()
    }

    func test__080__Channel__publish__Connection_state_conditions__the_message__should_NOT_be_queued_instead_it_should_be_published_if_the_channel_is__ATTACHING() {
        beforeEach__Channel__publish__Connection_state_conditions__the_message(channelName: uniqueChannelName())

        rtl6c2TestsClient.connect()
        expect(rtl6c2TestsClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            rtl6c2TestsChannel.attach()
            expect(rtl6c2TestsChannel.state).to(equal(ARTRealtimeChannelState.attaching))
            rtl16c2TestsPublish(done)
            expect(rtl6c2TestsClient.internal.queuedMessages).to(haveCount(0))
            expect((rtl6c2TestsClient.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }).to(haveCount(1))
        }

        afterEach__Channel__publish__Connection_state_conditions__the_message()
    }

    func test__081__Channel__publish__Connection_state_conditions__the_message__should_NOT_be_queued_instead_it_should_be_published_if_the_channel_is__ATTACHED() {
        beforeEach__Channel__publish__Connection_state_conditions__the_message(channelName: uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            rtl6c2TestsChannel.attach { error in
                expect(error).to(beNil())
                done()
            }
            rtl6c2TestsClient.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            let tokenParams = ARTTokenParams()
            tokenParams.ttl = 5.0
            rtl6c2TestsClient.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                expect(error).to(beNil())
                expect(tokenDetails).toNot(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            rtl6c2TestsClient.connection.once(.disconnected) { _ in
                done()
            }
        }

        expect(rtl6c2TestsChannel.state).to(equal(ARTRealtimeChannelState.attached))

        waitUntil(timeout: testTimeout) { done in
            rtl16c2TestsPublish(done)
            expect(rtl6c2TestsClient.internal.queuedMessages).to(haveCount(1))
        }

        afterEach__Channel__publish__Connection_state_conditions__the_message()
    }

    // RTL6c4

    func beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(channelName: String) {
        setupDependencies()
        ARTDefault.setConnectionStateTtl(0.3)
        rtl6c4TestsClient = AblyTests.newRealtime(options)
        rtl6c4TestsChannel = rtl6c4TestsClient.channels.get(channelName)
    }

    func afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the() {
        rtl6c4TestsClient.close()
        ARTDefault.setConnectionStateTtl(previousConnectionStateTtl)
    }

    func test__082__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__connection_is_SUSPENDED() {
        beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(channelName: uniqueChannelName())

        rtl6c4TestsClient.connect()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c4TestsClient.internal.onSuspended()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.suspended), timeout: testTimeout)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__083__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__connection_is_CLOSING() {
        beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(channelName: uniqueChannelName())

        rtl6c4TestsClient.connect()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c4TestsClient.close()
        expect(rtl6c4TestsClient.connection.state).to(equal(ARTRealtimeConnectionState.closing))
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__084__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__connection_is_CLOSED() {
        beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(channelName: uniqueChannelName())

        rtl6c4TestsClient.connect()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c4TestsClient.close()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.closed), timeout: testTimeout)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__085__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__connection_is_FAILED() {
        beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(channelName: uniqueChannelName())

        rtl6c4TestsClient.connect()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c4TestsClient.internal.onError(AblyTests.newErrorProtocolMessage())
        expect(rtl6c4TestsClient.connection.state).to(equal(ARTRealtimeConnectionState.failed))
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__086__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__channel_is_SUSPENDED() {
        beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(channelName: uniqueChannelName())

        rtl6c4TestsClient.connect()
        rtl6c4TestsChannel.attach()
        expect(rtl6c4TestsChannel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        rtl6c4TestsChannel.internal.setSuspended(ARTStatus.state(.ok))
        expect(rtl6c4TestsChannel.state).toEventually(equal(ARTRealtimeChannelState.suspended), timeout: testTimeout)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__087__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__channel_is_FAILED() {
        beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(channelName: uniqueChannelName())

        rtl6c4TestsClient.connect()
        rtl6c4TestsChannel.attach()
        expect(rtl6c4TestsChannel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        let protocolError = AblyTests.newErrorProtocolMessage()
        rtl6c4TestsChannel.internal.onError(protocolError)
        expect(rtl6c4TestsChannel.state).toEventually(equal(ARTRealtimeChannelState.failed), timeout: testTimeout)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    // RTL6c5
    func test__070__Channel__publish__Connection_state_conditions__publish_should_not_trigger_an_implicit_attach() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            let protocolError = AblyTests.newErrorProtocolMessage()
            expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
            channel.publish(nil, data: "message") { error in
                expect(channel.state).to(equal(ARTRealtimeChannelState.failed))

                channel.publish(nil, data: "message") { error in
                    expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
                    expect(error).toNot(beNil())
                    done()
                }
            }
            expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
            AblyTests.queue.async {
                channel.internal.onError(protocolError)
            }
        }
    }

    // RTL6d

    func test__088__Channel__publish__message_bundling__Messages_are_delivered_using_a_single_ProtocolMessage_where_possible_by_bundling_in_all_messages_for_that_channel() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        // Test that the initially queued messages are sent together.

        let messagesSent = 3
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(messagesSent, done: done)
            for i in 1 ... messagesSent {
                channel.publish("initial", data: "message\(i)") { error in
                    expect(error).to(beNil())
                    partialDone()
                }
            }
            client.connect()
        }

        let transport = client.internal.transport as! TestProxyTransport
        let protocolMessages = transport.protocolMessagesSent.filter { $0.action == .message }
        expect(protocolMessages).to(haveCount(1))
        if protocolMessages.count != 1 {
            return
        }
        expect(protocolMessages[0].messages).to(haveCount(messagesSent))

        // Test that publishing an array of messages sends them together.

        // TODO: limit the total number of messages bundled per ProtocolMessage
        let maxMessages = 50

        var messages = [ARTMessage]()
        for i in 1 ... maxMessages {
            messages.append(ARTMessage(name: "total number of messages", data: "message\(i)"))
        }
        waitUntil(timeout: testTimeout) { done in
            channel.publish(messages) { error in
                expect(error).to(beNil())
                let transport = client.internal.transport as! TestProxyTransport
                let protocolMessages = transport.protocolMessagesSent.filter { $0.action == .message }
                expect(protocolMessages).to(haveCount(2))
                if protocolMessages.count != 2 {
                    done(); return
                }
                expect(protocolMessages[1].messages).to(haveCount(maxMessages))
                done()
            }
        }
    }

    // RTL6d1
    func test__089__Channel__publish__message_bundling__The_resulting_ProtocolMessage_must_not_exceed_the_maxMessageSize() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        // This amount of messages would be beyond maxMessageSize, if bundled together
        let messagesToBeSent = 2000

        // Call publish before connecting, so messages are queued
        waitUntil(timeout: testTimeout.multiplied(by: 6)) { done in
            let partialDone = AblyTests.splitDone(messagesToBeSent, done: done)
            for i in 1 ... messagesToBeSent {
                channel.publish("initial initial\(i)", data: "message message\(i)") { error in
                    expect(error).to(beNil())
                    partialDone()
                }
            }
            client.connect()
        }

        let transport = client.internal.transport as! TestProxyTransport
        let protocolMessages = transport.protocolMessagesSent.filter { $0.action == .message }
        // verify that messages are not bundled in a single protocol message
        expect(protocolMessages.count).to(beGreaterThan(1))
        // verify that all the messages have been sent
        let messagesSent = protocolMessages.compactMap { $0.messages?.count }.reduce(0, +)
        expect(messagesSent).to(equal(messagesToBeSent))
    }

    // RTL6d2

    func test__092__Channel__publish__message_bundling__Messages_with_differing_clientId_values_must_not_be_bundled_together__messages_with_different__non_empty__clientIds_are_posted_via_different_protocol_messages() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        let clientIDs = ["client1", "client2", "client3"]

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(clientIDs.count, done: done)
            for (i, el) in clientIDs.enumerated() {
                channel.publish("name\(i)", data: "data\(i)", clientId: el) { error in
                    expect(error).to(beNil())
                    partialDone()
                }
            }
            client.connect()
        }

        let transport = client.internal.transport as! TestProxyTransport
        let protocolMessages = transport.protocolMessagesSent.filter { $0.action == .message }
        expect(protocolMessages.count).to(equal(clientIDs.count))
    }

    func test__093__Channel__publish__message_bundling__Messages_with_differing_clientId_values_must_not_be_bundled_together__messages_with_mixed_empty_non_empty_clientIds_are_posted_via_different_protocol_messages() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.publish("name1", data: "data1", clientId: "clientID1") { error in
                expect(error).to(beNil())
                partialDone()
            }
            channel.publish("name2", data: "data2") { error in
                expect(error).to(beNil())
                partialDone()
            }
            client.connect()
        }

        let transport = client.internal.transport as! TestProxyTransport
        let protocolMessages = transport.protocolMessagesSent.filter { $0.action == .message }
        expect(protocolMessages.count).to(equal(2))
    }

    func test__094__Channel__publish__message_bundling__Messages_with_differing_clientId_values_must_not_be_bundled_together__messages_bundled_by_the_user_are_posted_in_a_single_protocol_message_even_if_they_have_mixed_clientIds() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        var messages = [ARTMessage]()
        for i in 1 ... 3 {
            messages.append(ARTMessage(name: "name\(i)", data: "data\(i)", clientId: "clientId\(i)"))
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(messages) { error in
                expect(error).to(beNil())
                done()
            }
            client.connect()
        }

        let transport = client.internal.transport as! TestProxyTransport
        let protocolMessages = transport.protocolMessagesSent.filter { $0.action == .message }
        expect(protocolMessages.count).to(equal(1))
    }

    // FIXME: Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
    func skipped__test__090__Channel__publish__message_bundling__should_only_bundle_messages_when_it_respects_all_of_the_constraints() {
        let defaultMaxMessageSize = ARTDefault.maxMessageSize()
        ARTDefault.setMaxMessageSize(256)
        defer { ARTDefault.setMaxMessageSize(defaultMaxMessageSize) }

        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channelOne = client.channels.get(uniqueChannelName(prefix: "bundlingOne"))
        let channelTwo = client.channels.get(uniqueChannelName(prefix: "bundlingTwo"))

        channelTwo.publish("2a", data: ["expectedBundle": 0])
        channelOne.publish("a", data: ["expectedBundle": 1])
        channelOne.publish([
            ARTMessage(name: "b", data: ["expectedBundle": 1]),
            ARTMessage(name: "c", data: ["expectedBundle": 1]),
        ])
        channelOne.publish("d", data: ["expectedBundle": 1])
        channelTwo.publish("2b", data: ["expectedBundle": 2])
        channelOne.publish("e", data: ["expectedBundle": 3])
        channelOne.publish([ARTMessage(name: "f", data: ["expectedBundle": 3])])
        // RTL6d2
        channelOne.publish("g", data: ["expectedBundle": 4], clientId: "foo")
        channelOne.publish("h", data: ["expectedBundle": 4], clientId: "foo")
        channelOne.publish("i", data: ["expectedBundle": 5], clientId: "bar")
        channelOne.publish("j", data: ["expectedBundle": 6])
        // RTL6d1
        channelOne.publish("k", data: ["expectedBundle": 7, "moreData": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
        channelOne.publish("l", data: ["expectedBundle": 8])
        // RTL6d7
        channelOne.publish([ARTMessage(id: "bundle_m", name: "m", data: ["expectedBundle": 9])])
        channelOne.publish("z_last", data: ["expectedBundle": 10])

        let expectationMessageBundling = XCTestExpectation(description: "message-bundling")

        AblyTests.queue.async {
            let queue: [ARTQueuedMessage] = client.internal.queuedMessages as! [ARTQueuedMessage]
            for i in 0 ... 10 {
                for message in queue[i].msg.messages! {
                    let decodedMessage = channelOne.internal.dataEncoder.decode(message.data, encoding: message.encoding)

                    guard let data = (decodedMessage.data as? [String: Any]) else {
                        fail("Unexpected data type"); continue
                    }

                    expect(data["expectedBundle"] as? Int).to(equal(i))
                }
            }

            expectationMessageBundling.fulfill()
        }

        AblyTests.wait(for: [expectationMessageBundling], timeout: testTimeout)

        let expectationMessageFinalOrder = XCTestExpectation(description: "final-order")

        // RTL6d6
        var currentName = ""
        channelOne.subscribe { message in
            expect(currentName) < message.name! // Check final ordering preserved
            currentName = message.name!
            if currentName == "z_last" {
                expectationMessageFinalOrder.fulfill()
            }
        }
        client.connect()

        AblyTests.wait(for: [expectationMessageFinalOrder], timeout: testTimeout)
    }

    func test__091__Channel__publish__message_bundling__should_publish_only_once_on_multiple_explicit_publish_requests_for_a_given_message_with_client_supplied_ids() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName(prefix: "idempotentRealtimePublishing"))

        waitUntil(timeout: testTimeout) { done in
            channel.once(.attached) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
        }

        let expectationEvent0 = XCTestExpectation(description: "event0")
        let expectationEnd = XCTestExpectation(description: "end")

        var event0Msgs: [ARTMessage] = []
        channel.subscribe("event0") { message in
            event0Msgs.append(message)
            expectationEvent0.fulfill()
        }

        channel.subscribe("end") { _ in
            expect(event0Msgs).to(haveCount(1))
            expectationEnd.fulfill()
        }

        channel.publish([ARTMessage(id: "some_msg_id", name: "event0", data: "")])
        channel.publish([ARTMessage(id: "some_msg_id", name: "event0", data: "")])
        channel.publish([ARTMessage(id: "some_msg_id", name: "event0", data: "")])
        channel.publish("end", data: nil)

        AblyTests.wait(for: [expectationEvent0, expectationEnd])
    }

    // RTL6e

    // RTL6e1
    func test__095__Channel__publish__Unidentified_clients_using_Basic_Auth__should_have_the_provided_clientId_on_received_message_when_it_was_published_with_clientId() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        expect(client.auth.clientId).to(beNil())

        let channel = client.channels.get(uniqueChannelName())

        var resultClientId: String?

        let message = ARTMessage(name: nil, data: "message")
        message.clientId = "client_string"

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { message in
                resultClientId = message.clientId
                partialDone()
            }
            channel.publish([message]) { errorInfo in
                expect(errorInfo).to(beNil())
                partialDone()
            }
        }

        expect(resultClientId).toEventually(equal(message.clientId), timeout: testTimeout)
    }

    // RTL6f
    func test__065__Channel__publish__Message_connectionId_should_match_the_current_Connection_id_for_all_published_messages() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe { message in
                expect(message.connectionId).to(equal(client.connection.id))
                done()
            }
            channel.publish(nil, data: "message")
        }
    }

    // RTL6i

    func test__096__Channel__publish__expect_either__an_array_of_Message_objects() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        typealias JSONObject = NSDictionary

        var result = [JSONObject]()
        channel.subscribe { message in
            result.append(message.data as! JSONObject)
        }

        let messages = [ARTMessage(name: nil, data: ["key": 1]), ARTMessage(name: nil, data: ["key": 2])]
        channel.publish(messages)

        let transport = client.internal.transport as! TestProxyTransport

        expect(transport.protocolMessagesSent.filter { $0.action == .message }).toEventually(haveCount(1), timeout: testTimeout)
        expect(result).toEventually(equal(messages.map { $0.data as! JSONObject }), timeout: testTimeout)
    }

    func test__097__Channel__publish__expect_either__a_name_string_and_data_payload() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        let expectedResult = "string_data"
        var result: String?

        channel.subscribe("event") { message in
            result = message.data as? String
        }

        channel.publish("event", data: expectedResult, callback: nil)

        expect(result).toEventually(equal(expectedResult), timeout: testTimeout)
    }

    func test__098__Channel__publish__expect_either__allows_name_to_be_null() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let expectedObject = ["data": "message", "connectionId": client.connection.id!]

        var resultMessage: ARTMessage?
        channel.subscribe { message in
            resultMessage = message
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: expectedObject["data"]) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        let rawProtoMsgsSent: [NSDictionary] = transport.rawDataSent.toMsgPackArray()
        let rawMessagesSent = rawProtoMsgsSent.filter { $0["action"] as! UInt == ARTProtocolMessageAction.message.rawValue }
        let messagesList = rawMessagesSent[0]["messages"] as! NSArray
        let resultObject = messagesList[0] as! [String: String]

        expect(resultObject).to(equal(expectedObject))

        expect(resultMessage).toNotEventually(beNil(), timeout: testTimeout)
        expect(resultMessage!.name).to(beNil())
        expect(resultMessage!.data as? String).to(equal(expectedObject["data"]))
    }

    func test__099__Channel__publish__expect_either__allows_data_to_be_null() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let expectedObject = ["name": "click", "connectionId": client.connection.id!]

        var resultMessage: ARTMessage?
        channel.subscribe(expectedObject["name"]!) { message in
            resultMessage = message
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(expectedObject["name"], data: nil) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        let rawProtoMsgsSent: [NSDictionary] = transport.rawDataSent.toMsgPackArray()
        let rawMessagesSent = rawProtoMsgsSent.filter { $0["action"] as! UInt == ARTProtocolMessageAction.message.rawValue }
        let messagesList = rawMessagesSent[0]["messages"] as! NSArray
        let resultObject = messagesList[0] as! NSDictionary

        expect(resultObject).to(equal(expectedObject as NSDictionary))

        expect(resultMessage).toNotEventually(beNil(), timeout: testTimeout)
        expect(resultMessage!.name).to(equal(expectedObject["name"]))
        expect(resultMessage!.data).to(beNil())
    }

    func test__100__Channel__publish__expect_either__allows_name_and_data_to_be_assigned() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let expectedObject = ["name": "click", "data": "message", "connectionId": client.connection.id!]

        waitUntil(timeout: testTimeout) { done in
            channel.publish(expectedObject["name"], data: expectedObject["data"]) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        let rawProtoMsgsSent: [NSDictionary] = transport.rawDataSent.toMsgPackArray()
        let rawMessagesSent = rawProtoMsgsSent.filter { $0["action"] as! UInt == ARTProtocolMessageAction.message.rawValue }
        let messagesList = rawMessagesSent[0]["messages"] as! NSArray
        let resultObject = messagesList[0] as! NSDictionary

        expect(resultObject).to(equal(expectedObject as NSDictionary))
    }

    // RTL6g

    // RTL6g1

    // RTL6g1a & RTL6g1b
    func test__105__Channel__publish__Identified_clients_with_clientId__When_publishing_a_Message_with_clientId_set_to_null__should_be_unnecessary_to_set_clientId_of_the_Message_before_publishing_and_have_clientId_value_set_for_the_Message_when_received() {
        let options = AblyTests.commonAppSetup()
        options.clientId = "client_string"
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        let message = ARTMessage(name: nil, data: "message")
        expect(message.clientId).to(beNil())

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe { message in
                expect(message.clientId).to(equal(options.clientId))
                done()
            }
            channel.publish([message])
        }

        let transport = client.internal.transport as! TestProxyTransport

        let messageSent = transport.protocolMessagesSent.filter { $0.action == .message }[0]
        expect(messageSent.messages![0].clientId).to(beNil())

        let messageReceived = transport.protocolMessagesReceived.filter { $0.action == .message }[0]
        expect(messageReceived.messages![0].clientId).to(equal(options.clientId))
    }

    // RTL6g2
    func test__101__Channel__publish__Identified_clients_with_clientId__when_publishing_a_Message_with_the_clientId_attribute_value_set_to_the_identified_client_s_clientId() {
        let options = AblyTests.commonAppSetup()
        options.clientId = "john"
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        let message = ARTMessage(name: nil, data: "message", clientId: options.clientId!)
        var resultClientId: String?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { message in
                resultClientId = message.clientId
                partialDone()
            }
            channel.publish([message]) { error in
                expect(error).to(beNil())
                partialDone()
            }
        }

        expect(resultClientId).toEventually(equal(message.clientId), timeout: testTimeout)
    }

    // RTL6g3
    func test__102__Channel__publish__Identified_clients_with_clientId__when_publishing_a_Message_with_a_different_clientId_attribute_value_from_the_identified_client_s_clientId__it_should_reject_that_publish_operation_immediately() {
        let options = AblyTests.commonAppSetup()
        options.clientId = "john"
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish([ARTMessage(name: nil, data: "message", clientId: "tester")]) { error in
                expect(error?.code).to(equal(Int(ARTState.mismatchedClientId.rawValue)))
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish([ARTMessage(name: nil, data: "message")]) { error in
                expect(error).to(beNil())
                done()
            }
        }
    }

    // RTL6g4
    func test__103__Channel__publish__Identified_clients_with_clientId__message_should_be_published_following_authentication_and_received_back_with_the_clientId_intact() {
        let options = AblyTests.clientOptions()
        options.authCallback = { _, completion in
            getTestTokenDetails(clientId: "john", completion: completion)
        }
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        let message = ARTMessage(name: nil, data: "message", clientId: "john")
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { received in
                expect(received.clientId).to(equal(message.clientId))
                partialDone()
            }
            channel.publish([message]) { error in
                expect(error).to(beNil())
                partialDone()
            }
        }
    }

    // RTL6g4
    func test__104__Channel__publish__Identified_clients_with_clientId__message_should_be_rejected_by_the_Ably_service_and_the_message_error_should_contain_the_server_error() {
        let options = AblyTests.clientOptions()
        options.authCallback = { _, completion in
            getTestTokenDetails(clientId: "john", completion: completion)
        }
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        let message = ARTMessage(name: nil, data: "message", clientId: "tester")
        waitUntil(timeout: testTimeout) { done in
            channel.publish([message]) { error in
                expect(error!.code).to(equal(ARTErrorCode.invalidClientId.intValue))
                done()
            }
        }
    }

    // RTL6h
    func test__066__Channel__publish__should_provide_an_optional_argument_that_allows_the_clientId_value_to_be_specified() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { message in
                expect(message.name).to(equal("event"))
                expect(message.data as? NSObject).to(equal("data" as NSObject?))
                expect(message.clientId).to(equal("foo"))
                partialDone()
            }
            channel.publish("event", data: "data", clientId: "foo") { errorInfo in
                expect(errorInfo).to(beNil())
                partialDone()
            }
        }
    }

    // RTL7

    // RTL7a
    func test__106__Channel__subscribe__with_no_arguments_subscribes_a_listener_to_all_messages() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        class Test {
            static var counter = 0
            fileprivate init() {}
        }

        channel.subscribe { message in
            expect(message.data as? String).to(equal("message"))
            Test.counter += 1
        }

        channel.publish(nil, data: "message")
        channel.publish("eventA", data: "message")
        channel.publish("eventB", data: "message")

        expect(Test.counter).toEventually(equal(3), timeout: testTimeout)
    }

    // RTL7b
    func test__107__Channel__subscribe__with_a_single_name_argument_subscribes_a_listener_to_only_messages_whose_name_member_matches_the_string_name() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        class Test {
            static var counter = 0
            fileprivate init() {}
        }

        channel.subscribe("eventA") { message in
            expect(message.name).to(equal("eventA"))
            expect(message.data as? String).to(equal("message"))
            Test.counter += 1
        }

        channel.publish(nil, data: "message")
        channel.publish("eventA", data: "message")
        channel.publish("eventB", data: "message")
        channel.publish("eventA", data: "message")

        expect(Test.counter).toEventually(equal(2), timeout: testTimeout)
    }

    func test__108__Channel__subscribe__with_a_attach_callback_should_subscribe_and_call_the_callback_when_attached() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        let publishedMessage = ARTMessage(name: "foo", data: "bar")

        waitUntil(timeout: testTimeout) { done in
            expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))

            channel.subscribe(attachCallback: { errorInfo in
                expect(errorInfo).to(beNil())
                expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                channel.publish([publishedMessage])
            }) { message in
                expect(message.name).to(equal(publishedMessage.name))
                expect(message.data as? NSObject).to(equal(publishedMessage.data as? NSObject))
                done()
            }

            expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
        }
    }

    // RTL7c
    func test__109__Channel__subscribe__should_implicitly_attach_the_channel() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        channel.subscribe { _ in }

        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
    }

    // RTL7c
    func test__110__Channel__subscribe__should_result_in_an_error_if_channel_is_in_the_FAILED_state() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        channel.internal.onError(AblyTests.newErrorProtocolMessage())
        expect(channel.state).to(equal(ARTRealtimeChannelState.failed))

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe(attachCallback: { errorInfo in
                expect(errorInfo).toNot(beNil())

                channel.subscribe("foo", onAttach: { errorInfo in
                    expect(errorInfo).toNot(beNil())
                    done()
                }) { _ in }
            }) { _ in }
        }
    }

    // RTL7d

    func test__112__Channel__subscribe__should_deliver_the_message_even_if_there_is_an_error_while_decoding__using_crypto_data_128() {
        testHandlesDecodingErrorInFixture("crypto-data-128", channelName: uniqueChannelName())
    }

    func test__113__Channel__subscribe__should_deliver_the_message_even_if_there_is_an_error_while_decoding__using_crypto_data_256() {
        testHandlesDecodingErrorInFixture("crypto-data-256", channelName: uniqueChannelName())
    }

    // RTL7e
    func test__114__Channel__subscribe__message_cannot_be_decoded_or_decrypted__should_deliver_with_encoding_attribute_set_indicating_the_residual_encoding_and_error_should_be_emitted() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.logHandler = ARTLog(capturingOutput: true)
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        let channelOptions = ARTRealtimeChannelOptions(cipher: ["key": ARTCrypto.generateRandomKey()] as ARTCipherParamsCompatible)
        let channel = client.channels.get(uniqueChannelName(), options: channelOptions)

        let expectedMessage = ["key": 1]
        let expectedData = try! JSONSerialization.data(withJSONObject: expectedMessage, options: JSONSerialization.WritingOptions(rawValue: 0))

        let transport = client.internal.transport as! TestProxyTransport

        transport.setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .message {
                let messageReceived = protocolMessage.messages![0]
                // Replacement: `json/utf-8/cipher+aes-256-cbc/base64` to `invalid/cipher+aes-256-cbc/base64`
                let newEncoding = "invalid" + messageReceived.encoding!["json/utf-8".endIndex...]
                messageReceived.encoding = newEncoding
            }
            return protocolMessage
        }

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe { message in
                // Last decoding failed: NSData -> JSON object, so...
                expect(message.data as? NSData).to(equal(expectedData as NSData?))
                expect(message.encoding).to(equal("invalid"))

                let logs = options.logHandler.captured
                let line = logs.reduce("") { $0 + "; " + $1.toString() } // Reduce in one line
                expect(line).to(contain("Failed to decode data: unknown encoding: 'invalid'"))

                expect(channel.errorReason!.message).to(contain("Failed to decode data: unknown encoding: 'invalid'"))

                done()
            }

            channel.publish(nil, data: expectedMessage)
        }
    }

    // RTL7f
    func test__111__Channel__subscribe__should_exist_ensuring_published_messages_are_not_echoed_back_to_the_subscriber_when_echoMessages_is_false() {
        let options = AblyTests.commonAppSetup()
        let client1 = ARTRealtime(options: options)
        defer { client1.close() }

        options.echoMessages = false
        let client2 = ARTRealtime(options: options)
        defer { client2.close() }

        let channelName = uniqueChannelName()
        let channel1 = client1.channels.get(channelName)
        let channel2 = client2.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel1.attach { err in
                expect(err).to(beNil())
                channel1.subscribe { message in
                    expect(message.data as? String).to(equal("message"))
                    delay(1.0) { done() }
                }

                channel2.subscribe { _ in
                    fail("Shouldn't receive the message")
                }

                channel2.publish(nil, data: "message")
            }
        }
    }

    // RTL8

    // RTL8a
    func test__115__Channel__unsubscribe__with_no_arguments_unsubscribes_the_provided_listener_to_all_messages_if_subscribed() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let listener = channel.subscribe { _ in
                fail("Listener shouldn't exist")
                done()
            }

            channel.unsubscribe(listener)

            channel.publish(nil, data: "message") { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }
    }

    // RTL8b
    func test__116__Channel__unsubscribe__with_a_single_name_argument_unsubscribes_the_provided_listener_if_previously_subscribed_with_a_name_specific_subscription() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let eventAListener = channel.subscribe("eventA") { _ in
                fail("Listener shouldn't exist")
                done()
            }

            channel.unsubscribe("eventA", listener: eventAListener)

            channel.publish("eventA", data: "message") { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }
    }

    // RTL10

    // RTL10a
    func test__117__Channel__history__should_support_all_the_same_params_as_Rest() {
        let options = AblyTests.commonAppSetup()

        let rest = ARTRest(options: options)

        let realtime = ARTRealtime(options: options)
        defer { realtime.close() }

        let channelRest = rest.channels.get(uniqueChannelName())
        let channelRealtime = realtime.channels.get(uniqueChannelName())

        var restChannelHistoryMethodWasCalled = false

        let hookRest = channelRest.testSuite_injectIntoMethod(after: #selector(ARTRestChannel.history(_:callback:))) {
            restChannelHistoryMethodWasCalled = true
        }
        defer { hookRest.remove() }

        let hookRealtime = channelRealtime.testSuite_injectIntoMethod(after: #selector(ARTRestChannel.history(_:callback:))) {
            restChannelHistoryMethodWasCalled = true
        }
        defer { hookRealtime.remove() }

        let queryRealtime = ARTRealtimeHistoryQuery()
        queryRealtime.start = NSDate() as Date
        queryRealtime.end = NSDate() as Date
        queryRealtime.direction = .forwards
        queryRealtime.limit = 50

        let queryRest = queryRealtime as ARTDataQuery

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channelRest.history(queryRest) { _, _ in
                    done()
                }
            }.toNot(throwError { err in fail("\(err)"); done() })
        }
        expect(restChannelHistoryMethodWasCalled).to(beTrue())
        restChannelHistoryMethodWasCalled = false

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channelRealtime.history(queryRealtime) { _, _ in
                    done()
                }
            }.toNot(throwError { err in fail("\(err)"); done() })
        }
        expect(restChannelHistoryMethodWasCalled).to(beTrue())
    }

    // RTL10b

    func test__123__Channel__history__supports_the_param_untilAttach__should_be_false_as_default() {
        let query = ARTRealtimeHistoryQuery()
        expect(query.untilAttach).to(equal(false))
    }

    func test__124__Channel__history__supports_the_param_untilAttach__should_invoke_an_error_when_the_untilAttach_is_specified_and_the_channel_is_not_attached() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        let query = ARTRealtimeHistoryQuery()
        query.untilAttach = true

        do {
            try channel.history(query, callback: { _, _ in })
        } catch let error as NSError {
            if error.code != ARTRealtimeHistoryError.notAttached.rawValue {
                fail("Shouldn't raise a global error, got \(error)")
            }
            return
        }
        fail("Should raise an error")
    }

    func test__125__Channel__history__supports_the_param_untilAttach__where_value_is_true__should_pass_the_querystring_param_fromSerial_with_the_serial_number_assigned_to_the_channel() {
        testWithUntilAttach(true, channelName: uniqueChannelName())
    }

    func test__126__Channel__history__supports_the_param_untilAttach__where_value_is_false__should_pass_the_querystring_param_fromSerial_with_the_serial_number_assigned_to_the_channel() {
        testWithUntilAttach(true, channelName: uniqueChannelName())
    }

    func test__127__Channel__history__supports_the_param_untilAttach__should_retrieve_messages_prior_to_the_moment_that_the_channel_was_attached() {
        let options = AblyTests.commonAppSetup()
        let client1 = ARTRealtime(options: options)
        defer { client1.close() }

        options.autoConnect = false
        let client2 = ARTRealtime(options: options)
        defer { client2.close() }

        let channelName = uniqueChannelName()
        
        let channel1 = client1.channels.get(channelName)
        channel1.attach()
        expect(channel1.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        var messages = [ARTMessage]()
        for i in 0 ..< 20 {
            messages.append(ARTMessage(name: nil, data: "message \(i)"))
        }
        waitUntil(timeout: testTimeout) { done in
            channel1.publish(messages) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        client2.connect()
        let channel2 = client2.channels.get(channelName)
        channel2.attach()
        expect(channel2.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        var counter = 20
        channel2.subscribe { message in
            expect(message.data as? String).to(equal("message \(counter)"))
            counter += 1
        }

        messages = [ARTMessage]()
        for i in 20 ..< 40 {
            messages.append(ARTMessage(name: nil, data: "message \(i)"))
        }
        waitUntil(timeout: testTimeout) { done in
            channel1.publish(messages) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        let query = ARTRealtimeHistoryQuery()
        query.untilAttach = true

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channel2.history(query) { result, error in
                    expect(error).to(beNil())
                    guard let result = result else {
                        fail("Result is empty"); done(); return
                    }
                    expect(result.items).to(haveCount(20))
                    expect(result.hasNext).to(beFalse())
                    expect(result.items.first?.data as? String).to(equal("message 19"))
                    expect(result.items.last?.data as? String).to(equal("message 0"))
                    done()
                }
            }.toNot(throwError { err in fail("\(err)"); done() })
        }
    }

    // RTL10c
    func test__118__Channel__history__should_return_a_PaginatedResult_page() {
        let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { realtime.close() }
        let channel = realtime.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.history { result, error in
                expect(error).to(beNil())
                expect(result).to(beAKindOf(ARTPaginatedResult<ARTMessage>.self))
                guard let result = result else {
                    fail("Result is empty"); done(); return
                }
                expect(result.items).to(haveCount(1))
                expect(result.hasNext).to(beFalse())
                let messages = result.items
                expect(messages[0].data as? String).to(equal("message"))
                done()
            }
        }
    }

    // RTL10d
    func test__119__Channel__history__should_retrieve_all_available_messages() {
        let options = AblyTests.commonAppSetup()
        let client1 = ARTRealtime(options: options)
        defer { client1.close() }

        let client2 = ARTRealtime(options: options)
        defer { client2.close() }
        
        let channelName = uniqueChannelName()

        let channel1 = client1.channels.get(channelName)
        channel1.attach()
        expect(channel1.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        var messages = [ARTMessage]()
        for i in 0 ..< 20 {
            messages.append(ARTMessage(name: nil, data: "message \(i)"))
        }
        waitUntil(timeout: testTimeout) { done in
            channel1.publish(messages) { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        let channel2 = client2.channels.get(channelName)
        channel2.attach()
        expect(channel2.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        let query = ARTRealtimeHistoryQuery()
        query.limit = 10

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channel2.history(query) { result, _ in
                    expect(result!.items).to(haveCount(10))
                    expect(result!.hasNext).to(beTrue())
                    expect(result!.isLast).to(beFalse())
                    expect((result!.items.first!).data as? String).to(equal("message 19"))
                    expect((result!.items.last!).data as? String).to(equal("message 10"))

                    result!.next { result, _ in
                        expect(result!.items).to(haveCount(10))
                        expect(result!.hasNext).to(beFalse())
                        expect(result!.isLast).to(beTrue())
                        expect((result!.items.first!).data as? String).to(equal("message 9"))
                        expect((result!.items.last!).data as? String).to(equal("message 0"))
                        done()
                    }
                }
            }.toNot(throwError { err in fail("\(err)"); done() })
        }
    }

    // RTL12
    func test__120__Channel__history__attached_channel_may_receive_an_additional_ATTACHED_ProtocolMessage() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        channel.on(.attached) { _ in
            fail("Should not be called")
        }
        defer {
            channel.off()
        }

        var hook: AspectToken?
        waitUntil(timeout: testTimeout) { done in
            let attachedMessage = ARTProtocolMessage()
            attachedMessage.action = .attached
            attachedMessage.channel = channel.name

            /* TODO: ->
             this callback called twice leading to a fail with "waitUntil(..) expects its completion closure to be only called once"
             however sometimes it called once thus succeeding this test!
             https://github.com/ably/ably-cocoa/issues/1281
             */
            hook = channel.internal.testSuite_injectIntoMethod(after: #selector(channel.internal.onChannelMessage(_:))) {
                done()
            }

            // Inject additional ATTACHED action without an error
            client.internal.transport?.receive(attachedMessage)
        }
        hook!.remove()
        expect(channel.errorReason).to(beNil())
        expect(channel.state).to(equal(ARTRealtimeChannelState.attached))

        waitUntil(timeout: testTimeout) { done in
            let attachedMessageWithError = AblyTests.newErrorProtocolMessage()
            attachedMessageWithError.action = .attached
            attachedMessageWithError.channel = channel.name

            channel.once(.update) { stateChange in
                expect(stateChange.event).to(equal(ARTChannelEvent.update))
                expect(stateChange.reason).to(beIdenticalTo(attachedMessageWithError.error))
                expect(channel.errorReason).to(beIdenticalTo(stateChange.reason))
                done()
            }

            // Inject additional ATTACHED action with an error
            client.internal.transport?.receive(attachedMessageWithError)
        }
        expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
    }

    // RTL13

    // RTL13a
    func test__128__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__the_channel_is_in_the_ATTACHED_states__an_attempt_to_reattach_the_channel_should_be_made_immediately_by_sending_a_new_ATTACH_message_and_the_channel_should_transition_to_the_ATTACHING_state_with_the_error_emitted_in_the_ChannelStateChange_event() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.attached))

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        waitUntil(timeout: testTimeout) { done in
            let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
            detachedMessageWithError.action = .detached
            detachedMessageWithError.channel = channel.name

            channel.once(.attaching) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error).to(beIdenticalTo(detachedMessageWithError.error))
                expect(channel.errorReason).to(beNil())
                done()
            }

            transport.receive(detachedMessageWithError)
        }

        expect(transport.protocolMessagesSent.filter { $0.action == .attach }).to(haveCount(2))
    }

    // RTL13a
    func test__129__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__the_channel_is_in_the_SUSPENDED_state__an_attempt_to_reattach_the_channel_should_be_made_immediately_by_sending_a_new_ATTACH_message_and_the_channel_should_transition_to_the_ATTACHING_state_with_the_error_emitted_in_the_ChannelStateChange_event() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        let channel = client.channels.get(uniqueChannelName())

        // Timeout
        transport.actionsIgnored += [.attached]

        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                expect(stateChange.reason?.message).to(contain("timed out"))
                done()
            }
            channel.attach()
        }

        transport.actionsIgnored = []

        waitUntil(timeout: testTimeout) { done in
            let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
            detachedMessageWithError.action = .detached
            detachedMessageWithError.channel = channel.name

            channel.once(.attaching) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error).to(beIdenticalTo(detachedMessageWithError.error))
                expect(channel.errorReason).to(beNil())
                done()
            }

            transport.receive(detachedMessageWithError)
        }

        expect(transport.protocolMessagesSent.filter { $0.action == .attach }).to(haveCount(2))
    }

    // RTL13b
    func test__130__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__if_the_attempt_to_re_attach_fails_the_channel_will_transition_to_the_SUSPENDED_state_and_the_error_will_be_emitted_in_the_ChannelStateChange_event() {
        let options = AblyTests.commonAppSetup()
        options.channelRetryTimeout = 1.0
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)
        transport.actionsIgnored = [.attached]

        let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
        detachedMessageWithError.action = .detached
        detachedMessageWithError.channel = channel.name

        waitUntil(timeout: testTimeout) { done in
            channel.once(.attaching) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error).to(beIdenticalTo(detachedMessageWithError.error))
                expect(channel.errorReason).to(beNil())
                done()
            }

            transport.receive(detachedMessageWithError)
        }

        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error.message).to(contain("timed out"))
                expect(channel.errorReason).to(beIdenticalTo(error))
                done()
            }
        }

        let start = NSDate()
        waitUntil(timeout: testTimeout) { done in
            channel.once(.attaching) { _ in
                let end = NSDate()
                expect(start.addingTimeInterval(options.channelRetryTimeout)).to(beCloseTo(end, within: 0.5))
                done()
            }
        }
    }

    // RTL13b
    func test__131__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__if_the_channel_was_already_in_the_ATTACHING_state__the_channel_will_transition_to_the_SUSPENDED_state_and_the_error_will_be_emitted_in_the_ChannelStateChange_event() {
        let options = AblyTests.commonAppSetup()
        options.channelRetryTimeout = 1.0
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
        detachedMessageWithError.action = .detached
        detachedMessageWithError.channel = channel.name

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attaching) { stateChange in
                expect(stateChange.reason).to(beNil())
                client.internal.transport?.receive(detachedMessageWithError)
                partialDone()
            }
            channel.once(.suspended) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); partialDone(); return
                }
                expect(error).to(beIdenticalTo(detachedMessageWithError.error))
                expect(channel.errorReason).to(beNil())

                // Check retry
                let start = NSDate()
                channel.once(.attached) { stateChange in
                    let end = NSDate()
                    expect(start).to(beCloseTo(end, within: 1.5))
                    expect(stateChange.reason).to(beNil())
                    partialDone()
                }
            }
            channel.attach()
        }
    }
    
    // RTL13b, RTB1
    func test__131b__Channel__if_the_channel_receives_a_server_initiated_DETACHED_message_and_if_the_attempt_to_reattach_fails_then_the_channel_will_transition_to_SUSPENDED_state_with_periodic_reattach_with_channelRetryTimeout() {
        
        let options = AblyTests.commonAppSetup()
        options.channelRetryTimeout = 1.0
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        
        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        ARTDefault.setRealtimeRequestTimeout(1.0)
        client.connect()
        
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout); client.dispose(); client.close() }
        
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()
        
        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))

        let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
        detachedMessageWithError.action = .detached
        detachedMessageWithError.channel = channel.name
        
        ARTUtils.seedRandom(withNumber: 5)
        
        var retryNumber = 1
        let maxRetryCount = 5
        var actualDelays = [TimeInterval]()
        
        waitUntil(timeout: testTimeout) { done in
            var suspendedAt: Date!
            channel.on(.attaching) { stateChange in
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.suspended))
                guard stateChange.previous == .suspended, let suspendedAt = suspendedAt else { return }
                let actualDelay = Date().timeIntervalSince(suspendedAt)
                actualDelays.append(actualDelay)
                retryNumber += 1
            }
            channel.on(.suspended) { stateChange in
                expect(stateChange.previous).to(equal(ARTRealtimeChannelState.attaching))
                suspendedAt = Date()
                expect(stateChange.reason).toNot(beNil())
                if retryNumber > maxRetryCount {
                    done()
                }
            }
            channel.on(.attached) { _ in
                fail("Should not receive attached message")
            }
            client.internal.transport?.receive(detachedMessageWithError) // force to .suspended
        }
        expect(actualDelays).to(beCloseTo(AblyTests.backoffWithJitterDelaysForTimeout(options.channelRetryTimeout), within: 0.18)) // Never hits exact values, less than this fails often
    }

    // RTL13c
    func test__132__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__if_the_connection_is_no_longer_CONNECTED__then_the_automatic_attempts_to_re_attach_the_channel_must_be_cancelled() {
        let options = AblyTests.commonAppSetup()
        options.channelRetryTimeout = 1.0
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }
        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        transport.actionsIgnored = [.attached]
        let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
        detachedMessageWithError.action = .detached
        detachedMessageWithError.channel = channel.name
        waitUntil(timeout: testTimeout) { done in
            channel.once(.attaching) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error).to(beIdenticalTo(detachedMessageWithError.error))
                expect(channel.errorReason).to(beNil())
                done()
            }
            transport.receive(detachedMessageWithError)
        }
        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error.message).to(contain("timed out"))
                expect(channel.errorReason).to(beIdenticalTo(error))
                done()
            }
        }

        channel.once(.attaching) { _ in
            fail("Should cancel the re-attach")
        }

        client.simulateSuspended(beforeSuspension: { done in
            channel.once(.suspended) { _ in
                done()
            }
        })
    }

    // RTL14
    func test__121__Channel__history__If_an_ERROR_ProtocolMessage_is_received_for_this_channel_then_the_channel_should_immediately_transition_to_the_FAILED_state__the_errorReason_should_be_set_and_an_error_should_be_emitted_on_the_channel() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let errorProtocolMessage = AblyTests.newErrorProtocolMessage()
            errorProtocolMessage.action = .error
            errorProtocolMessage.channel = channel.name

            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error).to(beIdenticalTo(errorProtocolMessage.error))
                expect(channel.errorReason).to(beIdenticalTo(error))
                done()
            }

            client.internal.transport?.receive(errorProtocolMessage)
        }

        expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
    }

    // RTL16

    // RTL16a

    func test__133__Channel__history__Channel_options__setOptions__should_send_an_ATTACH_message_with_params___modes_if_the_channel_is_attached() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.subscribe, .publish]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        waitUntil(timeout: testTimeout) { done in
            channel.setOptions(channelOptions) { error in
                expect(error).to(beNil())
                done()
            }
        }

        expect(channel.options?.modes).to(equal(channelOptions.modes))
        expect(channel.options?.params).to(equal(channelOptions.params))

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        expect(attachMessages).to(haveCount(2))
        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttach.flags & Int64(ARTChannelMode.publish.rawValue)).to(beGreaterThan(0)) // true
        expect(lastAttach.flags & Int64(ARTChannelMode.subscribe.rawValue)).to(beGreaterThan(0)) // true
        expect(lastAttach.params).to(equal(channelOptions.params))

        let attachedMessages = transport.protocolMessagesReceived.filter { $0.action == .attached }
        expect(attachMessages).to(haveCount(2))
        guard let lastAttached = attachedMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttached.flags & Int64(ARTChannelMode.publish.rawValue)).to(beGreaterThan(0)) // true
        expect(lastAttached.flags & Int64(ARTChannelMode.subscribe.rawValue)).to(beGreaterThan(0)) // true
        expect(lastAttached.params).to(equal(channelOptions.params))
    }

    func test__134__Channel__history__Channel_options__setOptions__should_send_an_ATTACH_message_with_params___modes_if_the_channel_is_attaching() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.subscribe]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)
            channel.once(.attaching) { _ in
                channel.setOptions(channelOptions) { error in
                    expect(error).to(beNil())
                    partialDone()
                }
            }
            channel.once(.attached) { _ in
                partialDone()
            }
            channel.once(.update) { _ in
                partialDone()
            }
            channel.attach()
        }

        let subscribeFlag = Int64(ARTChannelMode.subscribe.rawValue)

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        expect(attachMessages).to(haveCount(2))
        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttach.flags & subscribeFlag).to(equal(subscribeFlag))
        expect(lastAttach.params).to(equal(channelOptions.params))

        let attachedMessages = transport.protocolMessagesReceived.filter { $0.action == .attached }
        expect(attachedMessages).to(haveCount(2))
        guard let lastAttached = attachedMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttached.flags & subscribeFlag).to(equal(subscribeFlag))
        expect(lastAttached.params).to(equal(channelOptions.params))
    }

    func test__135__Channel__history__Channel_options__setOptions__should_success_immediately_if_channel_is_not_attaching_or_attached() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.subscribe]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        channel.setOptions(channelOptions) { error in
            expect(error).to(beNil())
        }

        expect(channel.state).to(equal(.initialized))
        expect(channel.options?.modes).to(equal(channelOptions.modes))
        expect(channel.options?.params).to(equal(channelOptions.params))
    }

    func test__136__Channel__history__Channel_options__setOptions__should_fail_if_the_attach_moves_to_FAILED() {
        let options = AblyTests.commonAppSetup()
        options.token = getTestToken(capability: "{\"secret\":[\"subscribe\"]}") // access denied
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.subscribe]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.failed) { stateChange in
                expect(stateChange.reason?.code).to(equal(ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue))
                partialDone()
            }
            channel.attach()
            channel.setOptions(channelOptions) { error in
                expect(error?.code).to(equal(ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue))
                partialDone()
            }
        }

        let subscribeFlag = Int64(ARTChannelMode.subscribe.rawValue)

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        expect(attachMessages).to(haveCount(2))
        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttach.flags & subscribeFlag).to(equal(subscribeFlag))
        expect(lastAttach.params).to(equal(channelOptions.params))

        let attachedMessages = transport.protocolMessagesReceived.filter { $0.action == .attached }
        expect(attachedMessages).to(beEmpty())
    }

    func test__137__Channel__history__Channel_options__setOptions__should_fail_if_the_attach_moves_to_DETACHED() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.subscribe]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        // Convert ATTACHED to DETACHED
        transport.setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .attached {
                protocolMessage.action = .detached
                protocolMessage.error = .create(withCode: ARTErrorCode.internalError.intValue, status: 500, message: "internal error")
                transport.setBeforeIncomingMessageModifier(nil)
            }
            return protocolMessage
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.attach { _ in
                partialDone()
            }
            channel.setOptions(channelOptions) { error in
                expect(error?.code).to(equal(ARTErrorCode.internalError.intValue))
                partialDone()
            }
        }

        let subscribeFlag = Int64(ARTChannelMode.subscribe.rawValue)

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        expect(attachMessages).to(haveCount(2))
        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttach.flags & subscribeFlag).to(equal(subscribeFlag))
        expect(lastAttach.params).to(equal(channelOptions.params))
    }
    
    func test__Channel_options__setOptions__shouldUpdateOptionsOfRestChannel() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }
        
        var restChannelSetOptions: ARTChannelOptions?
        let token = channel.internal.restChannel.testSuite_getArgument(from: #selector(ARTRestChannelInternal.setOptions_nosync(_:)), at: 0) { arg in
            guard let optionsArg = arg as? ARTChannelOptions else {
                XCTFail("Expected setOptions: to have been called with an ARTChannelOptions instance")
                return
            }
            restChannelSetOptions = optionsArg
        }
        defer { token.remove() }
        
        let channelOptions = ARTRealtimeChannelOptions(cipherKey: ARTCrypto.generateRandomKey() as NSData)
        
        waitUntil(timeout: testTimeout) { done in
            channel.setOptions(channelOptions) { error in
                XCTAssertNil(error)
                done()
            }
        }
        
        expect(restChannelSetOptions).to(beIdenticalTo(channelOptions))
    }

    // RTL17
    func test__122__Channel__history__should_not_emit_messages_to_subscribers_if_the_channel_is_in_any_state_other_than_ATTACHED() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.close(); client.dispose() }
        let channel = client.channels.get(uniqueChannelName())

        let m1 = ARTMessage(name: "m1", data: "d1")
        let m2 = ARTMessage(name: "m2", data: "d2")

        var subscribeEmittedCount = 0
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attached) { _ in
                channel.subscribe { message in
                    expect(channel.state).to(equal(.attached))
                    expect(message.name).to(equal(m1.name))
                    subscribeEmittedCount += 1
                    partialDone()
                }
                channel.publish([m1]) { error in
                    expect(error).to(beNil())
                    partialDone()
                }
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { _ in
                fail("not supposed to receive messages when channel state is \(channel.state)")
            }
            channel.detach()
            channel.publish([m2]) { error in
                expect(error).to(beNil())
                partialDone()
            }
            delay(3.0) {
                // Wait some seconds to see if the channel doesn't emit a message
                partialDone()
            }
        }

        channel.unsubscribe()
        expect(subscribeEmittedCount) == 1
    }

    func test__138__Channel__crypto__if_configured_for_encryption__channels_encrypt_and_decrypt_messages__data() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false

        let clientSender = ARTRealtime(options: options)
        clientSender.internal.setTransport(TestProxyTransport.self)
        defer { clientSender.close() }
        clientSender.connect()

        let clientReceiver = ARTRealtime(options: options)
        clientReceiver.internal.setTransport(TestProxyTransport.self)
        defer { clientReceiver.close() }
        clientReceiver.connect()

        let key = ARTCrypto.generateRandomKey()
        let channelName = uniqueChannelName()
        let sender = clientSender.channels.get(channelName, options: ARTRealtimeChannelOptions(cipherKey: key as ARTCipherKeyCompatible))
        let receiver = clientReceiver.channels.get(channelName, options: ARTRealtimeChannelOptions(cipherKey: key as ARTCipherKeyCompatible))

        var received = [ARTMessage]()

        waitUntil(timeout: testTimeout) { done in
            receiver.attach { _ in
                receiver.subscribe { message in
                    receiver.unsubscribe()
                    received.append(message)
                    done()
                }

                sender.publish("first", data: "first data")
            }
        }
        if received.count != 1 {
            fail("should have received one message")
            return
        }

        waitUntil(timeout: testTimeout) { done in
            receiver.detach { _ in
                sender.publish("second", data: "second data") { _ in done() }
            }
        }
        if receiver.state != .detached {
            fail("receiver should be detached")
            return
        }

        waitUntil(timeout: testTimeout) { done in
            receiver.attach { _ in
                receiver.subscribe { message in
                    received.append(message)
                    done()
                }
                sender.publish("third", data: "third data")
            }
        }
        if received.count != 2 {
            fail("should've received two messages")
            return
        }

        expect(received[0].name).to(equal("first"))
        expect(received[0].data as? NSString).to(equal("first data"))
        expect(received[1].name).to(equal("third"))
        expect(received[1].data as? NSString).to(equal("third data"))

        let senderTransport = clientSender.internal.transport as! TestProxyTransport
        let senderMessages = senderTransport.protocolMessagesSent.filter { $0.action == .message }
        for protocolMessage in senderMessages {
            for message in protocolMessage.messages! {
                expect(message.data! as? String).toNot(equal("\(message.name!) data"))
                expect(message.encoding).to(equal("utf-8/cipher+aes-256-cbc/base64"))
            }
        }

        let receiverTransport = clientReceiver.internal.transport as! TestProxyTransport
        let receiverMessages = receiverTransport.protocolMessagesReceived.filter { $0.action == .message }
        for protocolMessage in receiverMessages {
            for message in protocolMessage.messages! {
                expect(message.data! as? NSObject).toNot(equal("\(message.name!) data" as NSObject?))
                expect(message.encoding).to(equal("utf-8/cipher+aes-256-cbc"))
            }
        }
    }

    // https://github.com/ably/ably-cocoa/issues/614
    func test__002__Channel__should_not_crash_when_an_ATTACH_request_is_responded_with_a_DETACHED() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        transport.setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .attached {
                protocolMessage.action = .detached
                protocolMessage.error = ARTErrorInfo.create(withCode: ARTErrorCode.internalError.intValue, status: 500, message: "fake error message text")
            }
            return protocolMessage
        }

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                expect(error.statusCode) == 500
                done()
            }
        }
    }

    // TM2a
    func test__139__message_attributes__if_the_message_does_not_contain_an_id__it_should_be_set_to_protocolMsgId_index() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        let p = ARTProtocolMessage()
        p.id = "protocolId"
        let m = ARTMessage(name: nil, data: "message without ID")
        p.messages = [m]
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                done()
            }
        }
        waitUntil(timeout: testTimeout) { done in
            channel.subscribe { message in
                expect(message.id).to(equal("protocolId:0"))
                done()
            }
            AblyTests.queue.async {
                channel.internal.onMessage(p)
            }
        }
    }
}
