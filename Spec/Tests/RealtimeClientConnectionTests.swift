import Ably
import Aspects
import Nimble
import XCTest
import SwiftyJSON

func countChannels(_ channels: ARTRealtimeChannels) -> Int {
    var i = 0
    for _ in channels {
        i += 1
    }
    return i
}

private var ttlAndIdleIntervalPassedTestsClient: ARTRealtime!
private var ttlAndIdleIntervalPassedTestsConnectionId = ""
private let customTtlInterval: TimeInterval = 0.1
private let customIdleInterval: TimeInterval = 0.1
private var ttlAndIdleIntervalNotPassedTestsClient: ARTRealtime!
private var ttlAndIdleIntervalNotPassedTestsConnectionId = ""
private let expectedHostOrder = [3, 4, 0, 2, 1]
private let originalARTFallback_shuffleArray = ARTFallback_shuffleArray
private func testUsesAlternativeHostOnResponse(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ARTClientOptions(key: "xxxx:xxxx")
    options.autoConnect = false
    let client = ARTRealtime(options: options)
    defer { client.dispose(); client.close() }
    client.channels.get(channelName)

    let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
    defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
    ARTDefault.setRealtimeRequestTimeout(1.0)

    client.internal.setTransport(TestProxyTransport.self)
    TestProxyTransport.fakeNetworkResponse = caseTest
    defer { TestProxyTransport.fakeNetworkResponse = nil }

    var urlConnections = [URL]()
    TestProxyTransport.networkConnectEvent = { transport, url in
        if client.internal.transport !== transport {
            return
        }
        urlConnections.append(url)
        if urlConnections.count == 1 {
            TestProxyTransport.fakeNetworkResponse = nil
        }
    }
    defer { TestProxyTransport.networkConnectEvent = nil }

    waitUntil(timeout: testTimeout) { done in
        // wss://[a-e].ably-realtime.com: when a timeout occurs
        client.connection.once(.disconnected) { _ in
            done()
        }
        // wss://[a-e].ably-realtime.com: when a 401 occurs because of the `xxxx:xxxx` key
        client.connection.once(.failed) { _ in
            done()
        }
        client.connect()
    }

    expect(urlConnections).to(haveCount(2))
    expect(NSRegularExpression.match(urlConnections[0].absoluteString, pattern: "//realtime.ably.io")).to(beTrue())
    expect(NSRegularExpression.match(urlConnections[1].absoluteString, pattern: "//[a-e].ably-realtime.com")).to(beTrue())
}

private func testMovesToDisconnectedWithNetworkingError(_ error: Error) {
    let options = AblyTests.commonAppSetup()
    options.autoConnect = false
    let client = AblyTests.newRealtime(options)
    defer {
        client.dispose()
        client.close()
    }
    client.internal.setTransport(TestProxyTransport.self)

    waitUntil(timeout: testTimeout) { done in
        client.connection.once(.connected) { _ in
            done()
        }
        client.connect()
    }

    var _transport: ARTWebSocketTransport?
    AblyTests.queue.sync {
        _transport = client.internal.transport as? ARTWebSocketTransport
    }

    guard let wsTransport = _transport else {
        fail("expected WS transport")
        return
    }

    waitUntil(timeout: testTimeout) { done in
        client.connection.once(.disconnected) { _ in
            done()
        }
        wsTransport.webSocket(wsTransport.websocket!, didFailWithError: error)
    }
}

private var internetConnectionNotAvailableTestsClient: ARTRealtime!
private let fixtures = try! JSON(data: NSData(contentsOfFile: pathForTestResource(testResourcesPath + "messages-encoding.json"))! as Data, options: .mutableContainers)

private func expectDataToMatch(_ message: ARTMessage, _ fixtureMessage: JSON) {
    switch fixtureMessage["expectedType"].string! {
    case "string":
        expect(message.data as? NSString).to(equal(fixtureMessage["expectedValue"].string! as NSString?))
    case "jsonObject":
        if let data = message.data as? NSDictionary {
            expect(JSON(data)).to(equal(fixtureMessage["expectedValue"]))
        } else {
            fail("expected NSDictionary")
        }
    case "jsonArray":
        if let data = message.data as? NSArray {
            expect(JSON(data)).to(equal(fixtureMessage["expectedValue"]))
        } else {
            fail("expected NSArray")
        }
    case "binary":
        expect(message.data as? NSData).to(equal(fixtureMessage["expectedHexValue"].string!.dataFromHexadecimalString()! as NSData?))
    default:
        fail("unhandled: \(fixtureMessage["expectedType"].string!)")
    }
}

private var jsonOptions: ARTClientOptions!
private var msgpackOptions: ARTClientOptions!

private func setupDependencies() {
    if jsonOptions == nil {
        jsonOptions = AblyTests.commonAppSetup()
        jsonOptions.useBinaryProtocol = false
        // Keep the same key and channel prefix
        msgpackOptions = (jsonOptions.copy() as! ARTClientOptions)
        msgpackOptions.useBinaryProtocol = true
    }
}

class RealtimeClientConnectionTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = ttlAndIdleIntervalPassedTestsClient
        _ = ttlAndIdleIntervalPassedTestsConnectionId
        _ = customTtlInterval
        _ = customIdleInterval
        _ = ttlAndIdleIntervalNotPassedTestsClient
        _ = ttlAndIdleIntervalNotPassedTestsConnectionId
        _ = expectedHostOrder
        _ = originalARTFallback_shuffleArray
        _ = internetConnectionNotAvailableTestsClient
        _ = fixtures
        _ = jsonOptions
        _ = msgpackOptions

        return super.defaultTestSuite
    }

    class TotalMessages {
        static var expected: Int32 = 0
        static var succeeded: Int32 = 0
        fileprivate init() {}
    }

    // CD2c

    func test__016__Connection__ConnectionDetails__maxMessageSize_overrides_the_default_maxMessageSize() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        let defaultMaxMessageSize = ARTDefault.maxMessageSize()
        expect(defaultMaxMessageSize).to(equal(65536))
        defer {
            ARTDefault.setMaxMessageSize(defaultMaxMessageSize)
            client.dispose()
            client.close()
        }
        ARTDefault.setMaxMessageSize(1)

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                let transport = client.internal.transport as! TestProxyTransport
                let firstConnectionDetails = transport.protocolMessagesReceived.filter { $0.action == .connected }[0].connectionDetails
                expect(firstConnectionDetails!.maxMessageSize).to(equal(16384)) // Sandbox apps have a 16384 limit
                done()
            }
            client.connect()
        }
    }

    // RTN2

    func test__017__Connection__url__should_connect_to_the_default_host() {
        let options = ARTClientOptions(key: "keytest:secret")
        options.autoConnect = false

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        if let transport = client.internal.transport as? TestProxyTransport, let url = transport.lastUrl {
            expect(url.host).to(equal("realtime.ably.io"))
        } else {
            XCTFail("MockTransport isn't working")
        }
    }

    func test__018__Connection__url__should_connect_with_query_string_params() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    AblyTests.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connected:
                    if let transport = client.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
                        expect(query).to(haveParam("key", withValue: options.key ?? ""))
                        expect(query).to(haveParam("echo", withValue: "true"))
                        expect(query).to(haveParam("format", withValue: "msgpack"))
                    } else {
                        XCTFail("MockTransport isn't working")
                    }
                    done()
                default:
                    break
                }
            }
        }
    }

    func test__019__Connection__url__should_connect_with_query_string_params_including_clientId() {
        let options = AblyTests.commonAppSetup()
        options.clientId = "client_string"
        options.useTokenAuth = true
        options.autoConnect = false
        options.echoMessages = false

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    AblyTests.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connected:
                    if let transport = client.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
                        expect(query).to(haveParam("accessToken", withValue: client.auth.tokenDetails?.token ?? ""))
                        expect(query).to(haveParam("echo", withValue: "false"))
                        expect(query).to(haveParam("format", withValue: "msgpack"))
                        expect(query).to(haveParam("clientId", withValue: "client_string"))
                    } else {
                        XCTFail("MockTransport isn't working")
                    }
                    done()
                default:
                    break
                }
            }
        }
    }

    // RTN3
    func test__001__Connection__should_connect_automatically() {
        let options = AblyTests.commonAppSetup()
        var connected = false

        // Default
        expect(options.autoConnect).to(beTrue(), description: "autoConnect should be true by default")

        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        // The only way to control this functionality is with the options flag
        client.connection.on { stateChange in
            let state = stateChange.current
            let error = stateChange.reason
            expect(error).to(beNil())
            switch state {
            case .connected:
                connected = true
            default:
                break
            }
        }
        expect(connected).toEventually(beTrue(), timeout: DispatchTimeInterval.seconds(10), description: "Can't connect automatically")
    }

    func test__002__Connection__should_connect_manually() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false

        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        var waiting = true

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                switch state {
                case .connected:
                    if waiting {
                        XCTFail("Expected to be disconnected")
                    }
                    done()
                default:
                    break
                }
            }
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(2)) {
                waiting = false
                client.connect()
            }
        }
    }

    // RTN2f
    func test__003__Connection__API_version_param_must_be_included_in_all_connections() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) { _ in
                guard let webSocketTransport = client.internal.transport as? ARTWebSocketTransport else {
                    fail("Transport should be of type ARTWebSocketTransport"); done()
                    return
                }
                expect(webSocketTransport.websocketURL).toNot(beNil())

                // This test should not directly validate version against ARTDefault.version(), as
                // ultimately the version header has been derived from that value.
                expect(webSocketTransport.websocketURL?.query).to(haveParam("v", withValue: "1.2"))

                done()
            }
            client.connect()
        }
    }

    // RTN2g (Deprecated in favor of RCS7d)

    // RSC7d
    func test__004__Connection__Library_and_version_param__agent__should_include_the__Ably_Agent__header_value() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    AblyTests.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connected:
                    if let transport = client.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
                        expect(query).to(haveParam("agent", hasPrefix: "ably-cocoa/1.2.18"))
                    } else {
                        XCTFail("MockTransport isn't working")
                    }
                    done()
                default:
                    break
                }
            }
        }
        client.close()
    }

    // RTN4

    // RTN4a
    func test__020__Connection__event_emitter__should_emit_events_for_state_changes() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false

        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let connection = client.connection
        var events: [ARTRealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            var alreadyDisconnected = false
            var alreadyClosed = false

            connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .connecting:
                    if !alreadyDisconnected {
                        events += [state]
                    }
                case .connected:
                    if alreadyClosed {
                        delay(0) {
                            client.internal.onSuspended()
                        }
                    } else if alreadyDisconnected {
                        client.close()
                    } else {
                        events += [state]
                        delay(0) {
                            client.internal.onDisconnected()
                        }
                    }
                case .disconnected:
                    events += [state]
                    alreadyDisconnected = true
                case .suspended:
                    events += [state]
                    client.internal.onError(AblyTests.newErrorProtocolMessage())
                case .closing:
                    events += [state]
                case .closed:
                    events += [state]
                    alreadyClosed = true
                    client.connect()
                case .failed:
                    events += [state]
                    expect(errorInfo).toNot(beNil(), description: "Error is nil")
                    connection.off()
                    done()
                default:
                    break
                }
            }
            events += [connection.state]
            connection.connect()
        }

        if events.count != 8 {
            fail("Missing some states, got \(events)")
            return
        }

        expect(events[0].rawValue).to(equal(ARTRealtimeConnectionState.initialized.rawValue), description: "Should be INITIALIZED state")
        expect(events[1].rawValue).to(equal(ARTRealtimeConnectionState.connecting.rawValue), description: "Should be CONNECTING state")
        expect(events[2].rawValue).to(equal(ARTRealtimeConnectionState.connected.rawValue), description: "Should be CONNECTED state")
        expect(events[3].rawValue).to(equal(ARTRealtimeConnectionState.disconnected.rawValue), description: "Should be DISCONNECTED state")
        expect(events[4].rawValue).to(equal(ARTRealtimeConnectionState.closing.rawValue), description: "Should be CLOSING state")
        expect(events[5].rawValue).to(equal(ARTRealtimeConnectionState.closed.rawValue), description: "Should be CLOSED state")
        expect(events[6].rawValue).to(equal(ARTRealtimeConnectionState.suspended.rawValue), description: "Should be SUSPENDED state")
        expect(events[7].rawValue).to(equal(ARTRealtimeConnectionState.failed.rawValue), description: "Should be FAILED state")
    }

    // RTN4h
    func test__021__Connection__event_emitter__should_never_emit_a_ConnectionState_event_for_a_state_equal_to_the_previous_state() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
        }

        client.connection.once(.connected) { _ in
            fail("Should not emit a Connected state")
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.update) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                expect(stateChange.current).to(equal(ARTRealtimeConnectionState.connected))
                expect(stateChange.current).to(equal(stateChange.previous))
                done()
            }

            let authMessage = ARTProtocolMessage()
            authMessage.action = .auth
            client.internal.transport?.receive(authMessage)
        }
    }

    // RTN4b
    func test__022__Connection__event_emitter__should_emit_states_on_a_new_connection() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false

        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let connection = client.connection
        var events: [ARTRealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                switch state {
                case .connecting:
                    events += [state]
                case .connected:
                    events += [state]
                    done()
                default:
                    break
                }
            }
            connection.connect()
        }

        expect(events).to(haveCount(2), description: "Missing CONNECTING or CONNECTED state")

        if events.count != 2 {
            return
        }

        expect(events[0].rawValue).to(equal(ARTRealtimeConnectionState.connecting.rawValue), description: "Should be CONNECTING state")
        expect(events[1].rawValue).to(equal(ARTRealtimeConnectionState.connected.rawValue), description: "Should be CONNECTED state")
    }

    // RTN4c
    func test__023__Connection__event_emitter__should_emit_states_when_connection_is_closed() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        let connection = client.connection
        defer { client.dispose(); client.close() }
        var events: [ARTRealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                switch state {
                case .connected:
                    connection.close()
                case .closing:
                    events += [state]
                case .closed:
                    events += [state]
                    done()
                default:
                    break
                }
            }
        }

        expect(events).to(haveCount(2), description: "Missing CLOSING or CLOSED state")

        if events.count != 2 {
            return
        }

        expect(events[0].rawValue).to(equal(ARTRealtimeConnectionState.closing.rawValue), description: "Should be CLOSING state")
        expect(events[1].rawValue).to(equal(ARTRealtimeConnectionState.closed.rawValue), description: "Should be CLOSED state")
    }

    // RTN4d
    func test__024__Connection__event_emitter__should_have_the_current_state() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let connection = client.connection
        expect(connection.state.rawValue).to(equal(ARTRealtimeConnectionState.initialized.rawValue), description: "Missing INITIALIZED state")

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                switch state {
                case .connecting:
                    expect(connection.state.rawValue).to(equal(ARTRealtimeConnectionState.connecting.rawValue), description: "Missing CONNECTING state")
                case .connected:
                    expect(connection.state.rawValue).to(equal(ARTRealtimeConnectionState.connected.rawValue), description: "Missing CONNECTED state")
                    done()
                default:
                    break
                }
            }
            client.connect()
        }
    }

    // RTN4e
    func test__025__Connection__event_emitter__should_have_a_ConnectionStateChange_as_first_argument_for_every_connection_state_change() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(ARTRealtimeConnectionEvent.connected) { stateChange in
                expect(stateChange).to(beAKindOf(ARTConnectionStateChange.self))
                expect(stateChange.current).to(equal(ARTRealtimeConnectionState.connected))
                expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                done()
            }
            client.connect()
        }
    }

    // RTN4f
    func test__026__Connection__event_emitter__should_have_the_reason_which_contains_an_ErrorInfo() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let connection = client.connection

        var errorInfo: ARTErrorInfo?
        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let reason = stateChange.reason
                switch state {
                case .connected:
                    expect(stateChange.event).to(equal(ARTRealtimeConnectionEvent.connected))
                    client.internal.onError(AblyTests.newErrorProtocolMessage())
                case .failed:
                    expect(stateChange.event).to(equal(ARTRealtimeConnectionEvent.failed))
                    errorInfo = reason
                    done()
                default:
                    break
                }
            }
        }

        expect(errorInfo).toNot(beNil())
    }

    // RTN4f
    func test__027__Connection__event_emitter__any_state_change_triggered_by_a_ProtocolMessage_that_contains_an_Error_member_should_populate_the_Reason_property() {
        let options = AblyTests.commonAppSetup()
        options.useTokenAuth = true
        let client = AblyTests.newRealtime(options)
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
        guard let originalConnectedMessage = transport.protocolMessagesReceived.filter({ $0.action == .connected }).first else {
            fail("First CONNECTED message not received"); return
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.update) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error.code) == 1234
                expect(error.message) == "fabricated error"
                expect(stateChange.event).to(equal(ARTRealtimeConnectionEvent.update))
                done()
            }

            let connectedMessageWithError = originalConnectedMessage
            connectedMessageWithError.error = ARTErrorInfo.create(withCode: 1234, message: "fabricated error")
            client.internal.transport?.receive(connectedMessageWithError)
        }
    }

    // RTN5
    func test__005__Connection__basic_operations_should_work_simultaneously() {
        let options = AblyTests.commonAppSetup()
        options.echoMessages = false
        var disposable = [ARTRealtime]()
        let numClients = 50
        let numMessages = 5
        let channelName = "chat"
        let testTimeout = DispatchTimeInterval.seconds(60)

        defer {
            for client in disposable {
                client.dispose()
                client.close()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(numClients, done: done)
            for _ in 1 ... numClients {
                let client = ARTRealtime(options: options)
                disposable.append(client)
                let channel = client.channels.get(channelName)
                channel.attach { error in
                    if let error = error {
                        fail(error.message); done()
                    }
                    partialDone()
                }
            }
        }

        var messagesReceived = 0
        waitUntil(timeout: testTimeout) { done in
            // Sends numMessages messages from different clients to the same channel
            // numMessages messages for numClients clients = numMessages*numClients total messages
            // echo is off, so we need to subtract one message per publish
            let messagesExpected = numMessages * numClients - 1 * numMessages
            var messagesSent = 0
            for client in disposable {
                let channel = client.channels.get(channelName)
                expect(channel.state).to(equal(ARTRealtimeChannelState.attached))

                channel.subscribe { message in
                    expect(message.data as? String).to(equal("message_string"))
                    messagesReceived += 1
                    if messagesReceived == messagesExpected {
                        done()
                    }
                }

                if messagesSent < numMessages {
                    channel.publish(nil, data: "message_string", callback: nil)
                    messagesSent += 1
                }
            }
        }

        expect(disposable.count).to(equal(numClients))
        expect(countChannels(disposable.first!.channels)).to(equal(1))
        expect(countChannels(disposable.last!.channels)).to(equal(1))
    }

    // RTN6
    func test__006__Connection__should_have_an_opened_websocket_connection_and_received_a_CONNECTED_ProtocolMessage() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                if state == .connected, error == nil {
                    done()
                }
            }
        }

        if let webSocketTransport = client.internal.transport as? ARTWebSocketTransport {
            expect(webSocketTransport.state).to(equal(ARTRealtimeTransportState.opened))
        } else {
            XCTFail("WebSocket is not the default transport")
        }

        if let transport = client.internal.transport as? TestProxyTransport {
            // CONNECTED ProtocolMessage
            expect(transport.protocolMessagesReceived.map { $0.action }).to(contain(ARTProtocolMessageAction.connected))
        } else {
            XCTFail("MockTransport is not working")
        }
    }

    // RTN7

    // RTN7a

    func test__028__Connection__ACK_and_NACK__should_expect_either_an_ACK_or_NACK_to_confirm__successful_receipt_and_acceptance_of_message() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.clientId = "client_string"
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            publishFirstTestMessage(client, channelName: uniqueChannelName(), completion: { error in
                expect(error).to(beNil())
                done()
            })
        }

        let transport = client.internal.transport as! TestProxyTransport

        guard let publishedMessage = transport.protocolMessagesSent.filter({ $0.action == .message }).last else {
            XCTFail("No MESSAGE action was sent"); return
        }

        guard let receivedAck = transport.protocolMessagesReceived.filter({ $0.action == .ack }).last else {
            XCTFail("No ACK action was received"); return
        }

        expect(publishedMessage.msgSerial).to(equal(receivedAck.msgSerial))
    }

    func test__029__Connection__ACK_and_NACK__should_expect_either_an_ACK_or_NACK_to_confirm__successful_receipt_and_acceptance_of_presence() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.clientId = "client_string"
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                if state == .connected {
                    let channel = client.channels.get(uniqueChannelName())
                    channel.attach { error in
                        expect(error).to(beNil())
                        channel.presence.enterClient("client_string", data: nil, callback: { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        })
                    }
                }
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        guard let publishedMessage = transport.protocolMessagesSent.filter({ $0.action == .presence }).last else {
            XCTFail("No PRESENCE action was sent"); return
        }

        guard let receivedAck = transport.protocolMessagesReceived.filter({ $0.action == .ack }).last else {
            XCTFail("No ACK action was received"); return
        }

        expect(publishedMessage.msgSerial).to(equal(receivedAck.msgSerial))
    }

    func test__030__Connection__ACK_and_NACK__should_expect_either_an_ACK_or_NACK_to_confirm__message_failure() {
        let options = AblyTests.commonAppSetup()
        
        let channelName = uniqueChannelName()
        options.token = getTestToken(key: options.key, capability: "{ \"\(options.channelNamePrefix!)-\(channelName)\":[\"subscribe\"] }")
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            publishFirstTestMessage(client, channelName: channelName, completion: { error in
                expect(error).toNot(beNil())
                done()
            })
        }

        let transport = client.internal.transport as! TestProxyTransport

        guard let publishedMessage = transport.protocolMessagesSent.filter({ $0.action == .message }).last else {
            XCTFail("No MESSAGE action was sent"); return
        }

        guard let receivedNack = transport.protocolMessagesReceived.filter({ $0.action == .nack }).last else {
            XCTFail("No NACK action was received"); return
        }

        expect(publishedMessage.msgSerial).to(equal(receivedNack.msgSerial))
    }

    func test__031__Connection__ACK_and_NACK__should_expect_either_an_ACK_or_NACK_to_confirm__presence_failure() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.clientId = "client_string"
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                if state == .connected {
                    let channel = client.channels.get(uniqueChannelName())
                    channel.attach { error in
                        expect(error).to(beNil())
                        channel.presence.enterClient("invalid", data: nil, callback: { errorInfo in
                            expect(errorInfo).toNot(beNil())
                            done()
                        })
                    }
                }
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        guard let publishedMessage = transport.protocolMessagesSent.filter({ $0.action == .presence }).last else {
            XCTFail("No PRESENCE action was sent"); return
        }

        guard let receivedNack = transport.protocolMessagesReceived.filter({ $0.action == .nack }).last else {
            XCTFail("No NACK action was received"); return
        }

        expect(publishedMessage.msgSerial).to(equal(receivedNack.msgSerial))
    }

    // RTN7b

    func test__032__Connection__ACK_and_NACK__ProtocolMessage__should_contain_unique_serially_incrementing_msgSerial_along_with_the_count() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.clientId = "client_string"
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        channel.attach()

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }
        }

        TotalMessages.expected = 5
        for index in 1 ... TotalMessages.expected {
            channel.publish(nil, data: "message\(index)") { errorInfo in
                if errorInfo == nil {
                    TotalMessages.succeeded += 1
                }
            }
        }
        expect(TotalMessages.succeeded).toEventually(equal(TotalMessages.expected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.presence.enterClient("invalid", data: nil, callback: { errorInfo in
                expect(errorInfo).toNot(beNil())
                done()
            })
        }

        let transport = client.internal.transport as! TestProxyTransport
        let acks = transport.protocolMessagesReceived.filter { $0.action == .ack }
        let nacks = transport.protocolMessagesReceived.filter { $0.action == .nack }

        if acks.count != 2 {
            fail("Received invalid number of ACK responses: \(acks.count)")
            return
        }

        expect(acks[0].msgSerial).to(equal(0))
        expect(acks[0].count).to(equal(1))

        // Messages covered in a single ACK response
        expect(acks[1].msgSerial).to(equal(1))
        expect(acks[1].count).to(equal(TotalMessages.expected))

        if nacks.count != 1 {
            fail("Received invalid number of NACK responses: \(nacks.count)")
            return
        }

        expect(nacks[0].msgSerial).to(equal(6))
        expect(nacks[0].count).to(equal(1))
    }

    func test__033__Connection__ACK_and_NACK__ProtocolMessage__should_continue_incrementing_msgSerial_serially_if_the_connection_resumes_successfully() {
        let options = AblyTests.commonAppSetup()
        options.clientId = "tester"
        options.tokenDetails = getTestTokenDetails(key: options.key!, clientId: options.clientId, ttl: 5.0)
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                done()
            }
        }

        guard let initialConnectionId = client.connection.id else {
            fail("Connection ID is empty"); return
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            (1 ... 3).forEach { index in
                channel.publish(nil, data: "message\(index)") { error in
                    if error == nil {
                        partialDone()
                    }
                }
            }
            channel.presence.enterClient("invalid", data: nil) { error in
                expect(error).toNot(beNil())
                partialDone()
            }
        }

        expect(client.internal.msgSerial) == 5

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                expect(stateChange.reason).toNot(beNil())
                // Token expired
                done()
            }
        }

        // Reconnected and resumed
        expect(client.connection.id).to(equal(initialConnectionId))
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            (1 ... 3).forEach { index in
                channel.publish(nil, data: "message\(index)") { error in
                    if error == nil {
                        partialDone()
                    }
                }
            }
            channel.presence.enterClient("invalid", data: nil) { error in
                expect(error).toNot(beNil())
                partialDone()
            }
        }

        guard let reconnectedTransport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }
        let acks = reconnectedTransport.protocolMessagesReceived.filter { $0.action == .ack }
        let nacks = reconnectedTransport.protocolMessagesReceived.filter { $0.action == .nack }

        if acks.count != 1 {
            fail("Received invalid number of ACK responses: \(acks.count)")
            return
        }
        // Messages covered in a single ACK response
        expect(acks[0].msgSerial) == 5 // [0] 1st publish + [1.2.4] publish + [4] enter with invalid client + [5] queued messages
        expect(acks[0].count) == 1

        if nacks.count != 1 {
            fail("Received invalid number of NACK responses: \(nacks.count)")
            return
        }
        expect(nacks[0].msgSerial) == 6
        expect(nacks[0].count) == 1

        expect(client.internal.msgSerial) == 7
    }

    func test__034__Connection__ACK_and_NACK__ProtocolMessage__should_reset_msgSerial_serially_if_the_connection_does_not_resume() {
        let options = AblyTests.commonAppSetup()
        options.clientId = "tester"
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                done()
            }
        }

        guard let initialConnectionId = client.connection.id else {
            fail("Connection ID is empty"); return
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            (1 ... 3).forEach { index in
                channel.publish(nil, data: "message\(index)") { error in
                    if error == nil {
                        partialDone()
                    }
                }
            }
            channel.presence.enterClient("invalid", data: nil) { error in
                expect(error?.code).to(equal(ARTErrorCode.invalidClientId.intValue))
                partialDone()
            }
        }

        expect(client.internal.msgSerial) == 5

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once(.disconnected) { _ in
                partialDone()
            }
            client.connection.once(.connected) { _ in
                partialDone()
            }
            client.simulateLostConnectionAndState()
        }

        // Reconnected but not resumed
        expect(client.connection.id).toNot(equal(initialConnectionId))
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            (1 ... 3).forEach { index in
                channel.publish(nil, data: "message\(index)") { error in
                    if error == nil {
                        partialDone()
                    }
                }
            }
            channel.presence.enterClient("invalid", data: nil) { error in
                expect(error?.code).to(equal(ARTErrorCode.invalidClientId.intValue))
                partialDone()
            }
        }

        guard let reconnectedTransport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }
        let acks = reconnectedTransport.protocolMessagesReceived.filter { $0.action == .ack }
        let nacks = reconnectedTransport.protocolMessagesReceived.filter { $0.action == .nack }

        // The server is free to roll up multiple acks into one or not
        if acks.count < 1 {
            fail("Received invalid number of ACK responses: \(acks.count)")
            return
        }
        expect(acks[0].msgSerial) == 0
        expect(acks.reduce(0) { $0 + $1.count }) == 3

        if nacks.count != 1 {
            fail("Received invalid number of NACK responses: \(nacks.count)")
            return
        }
        expect(nacks[0].msgSerial) == 3
        expect(nacks[0].count) == 1

        expect(client.internal.msgSerial) == 4
    }

    // RTN7c

    func test__035__Connection__ACK_and_NACK__should_trigger_the_failure_callback_for_the_remaining_pending_messages_if__connection_is_closed() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.clientId = "client_string"
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.ack, .nack]

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                channel.publish(nil, data: "message", callback: { error in
                    guard let error = error else {
                        fail("Error is nil"); done(); return
                    }
                    expect(error.message).to(contain("connection broken before receiving publishing acknowledgment"))
                    done()
                })
                // Wait until the message is pushed to Ably first
                delay(1.0) {
                    client.close()
                }
            }
        }

        // This verifies that the pending message as been released and the publish callback is called only once!
        waitUntil(timeout: testTimeout) { done in
            delay(1.0) {
                done()
            }
        }
    }

    func test__036__Connection__ACK_and_NACK__should_trigger_the_failure_callback_for_the_remaining_pending_messages_if__connection_state_enters_FAILED() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.clientId = "client_string"
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.ack, .nack]

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                channel.publish(nil, data: "message", callback: { errorInfo in
                    expect(errorInfo).toNot(beNil())
                    done()
                })
                // Wait until the message is pushed to Ably first
                delay(1.0) {
                    transport.simulateIncomingError()
                }
            }
        }
    }

    func test__037__Connection__ACK_and_NACK__should_trigger_the_failure_callback_for_the_remaining_pending_messages_if__lost_connection_state() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer {
            client.dispose()
            client.close()
        }

        let channel = client.channels.get(uniqueChannelName())

        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.ack, .nack]

        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)

            channel.publish(nil, data: "message") { error in
                guard let error = error else {
                    fail("Error is nil"); return
                }
                expect(error.code) == ARTErrorCode.unableToRecoverConnectionExpired.intValue
                expect(error.message).to(contain("Unable to recover connection"))
                partialDone()
            }

            let oldConnectionId = client.connection.id!

            // Wait until the message is pushed to Ably first
            delay(1.0) {
                client.connection.once(.disconnected) { _ in
                    partialDone()
                }
                client.connection.once(.connected) { _ in
                    expect(client.connection.id).toNot(equal(oldConnectionId))
                    partialDone()
                }
                client.simulateLostConnectionAndState()
            }
        }
    }

    // RTN8

    // RTN8a
    func test__038__Connection__connection_id__should_be_null_until_connected() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        let connection = client.connection
        defer {
            client.dispose()
            client.close()
        }

        expect(connection.id).to(beNil())

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                expect(errorInfo).to(beNil())
                if state == .connected {
                    expect(connection.id).toNot(beNil())
                    done()
                } else if state == .connecting {
                    expect(connection.id).to(beNil())
                }
            }
        }
    }

    // RTN8b
    func test__039__Connection__connection_id__should_have_unique_IDs() {
        let options = AblyTests.commonAppSetup()
        var disposable = [ARTRealtime]()
        defer {
            for client in disposable {
                client.dispose()
                client.close()
            }
        }
        var ids = [String]()
        let max = 25
        let sync = NSLock()

        waitUntil(timeout: testTimeout) { done in
            for _ in 1 ... max {
                disposable.append(ARTRealtime(options: options))
                let currentConnection = disposable.last!.connection
                currentConnection.on { stateChange in
                    let state = stateChange.current
                    let error = stateChange.reason
                    expect(error).to(beNil())
                    if state == .connected {
                        guard let connectionId = currentConnection.id else {
                            fail("connectionId is nil on CONNECTED")
                            done()
                            return
                        }
                        expect(ids).toNot(contain(connectionId))

                        sync.lock()
                        ids.append(connectionId)
                        if ids.count == max {
                            done()
                        }
                        sync.unlock()

                        currentConnection.off()
                        currentConnection.close()
                    }
                }
            }
        }

        expect(ids).to(haveCount(max))
    }

    // RTN9

    // RTN9a
    func test__040__Connection__connection_key__should_be_null_until_connected() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer {
            client.dispose()
            client.close()
        }
        let connection = client.connection

        expect(connection.key).to(beNil())

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                expect(errorInfo).to(beNil())
                if state == .connected {
                    expect(connection.id).toNot(beNil())
                    done()
                } else if state == .connecting {
                    expect(connection.key).to(beNil())
                }
            }
        }
    }

    // RTN9b
    func test__041__Connection__connection_key__should_have_unique_connection_keys() {
        let options = AblyTests.commonAppSetup()
        var disposable = [ARTRealtime]()
        defer {
            for client in disposable {
                client.dispose()
                client.close()
            }
        }
        var keys = [String]()
        let max = 25

        waitUntil(timeout: testTimeout) { done in
            for _ in 1 ... max {
                disposable.append(ARTRealtime(options: options))
                let currentConnection = disposable.last!.connection
                currentConnection.on { stateChange in
                    let state = stateChange.current
                    let error = stateChange.reason
                    expect(error).to(beNil())
                    if state == .connected {
                        guard let connectionKey = currentConnection.key else {
                            fail("connectionKey is nil on CONNECTED")
                            done()
                            return
                        }
                        expect(keys).toNot(contain(connectionKey))
                        keys.append(connectionKey)

                        if keys.count == max {
                            done()
                        }

                        currentConnection.off()
                        currentConnection.close()
                    }
                }
            }
        }

        expect(keys).to(haveCount(max))
    }

    // RTN10

    // RTN10a
    func test__042__Connection__serial__should_be_minus_1_once_connected() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer {
            client.dispose()
            client.close()
        }
        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                if state == .connected {
                    expect(client.connection.serial).to(equal(-1))
                    done()
                }
            }
        }
    }

    // RTN10b
    func test__043__Connection__serial__should_not_update_when_a_message_is_sent_but_increments_by_one_when_ACK_is_received() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer {
            client.dispose()
            client.close()
        }
        let channel = client.channels.get(uniqueChannelName())

        expect(client.connection.serial).to(equal(-1))
        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        expect(client.connection.serial).to(equal(-1))

        for index in 0 ... 3 {
            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(2, done: done)
                channel.publish(nil, data: "message", callback: { errorInfo in
                    expect(errorInfo).to(beNil())
                    partialDone()
                })
                channel.subscribe { _ in
                    // Updated
                    expect(client.connection.serial).to(equal(Int64(index)))
                    channel.unsubscribe()
                    partialDone()
                }
                // Not updated
                expect(client.connection.serial).to(equal(Int64(index - 1)))
            }
        }
    }

    func test__044__Connection__serial__should_have_last_known_connection_serial_from_restored_connection() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer {
            client.dispose()
            client.close()
        }
        let channelName = uniqueChannelName()
        let channel = client.channels.get(channelName)

        // Attach first to avoid bundling publishes in the same ProtocolMessage.
        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        for _ in 1 ... 5 {
            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(2, done: done)
                channel.publish(nil, data: "message", callback: { errorInfo in
                    expect(errorInfo).to(beNil())
                    partialDone()
                })
                channel.subscribe { _ in
                    channel.unsubscribe()
                    partialDone()
                }
            }
        }
        let lastSerial = client.connection.serial
        expect(lastSerial).to(equal(4))

        options.recover = client.connection.recoveryKey
        client.internal.onError(AblyTests.newErrorProtocolMessage())

        let recoveredClient = ARTRealtime(options: options)
        defer { recoveredClient.close() }
        expect(recoveredClient.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            expect(recoveredClient.connection.serial).to(equal(lastSerial))
            let recoveredChannel = recoveredClient.channels.get(channelName)
            recoveredChannel.publish(nil, data: "message", callback: { errorInfo in
                expect(errorInfo).to(beNil())
            })
            recoveredChannel.subscribe { _ in
                expect(recoveredClient.connection.serial).to(equal(lastSerial + 1))
                recoveredChannel.unsubscribe()
                done()
            }
        }
    }

    // RTN11b
    func test__007__Connection__should_make_a_new_connection_with_a_new_transport_instance_if_the_state_is_CLOSING() {
        let client = ARTRealtime(options: AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        weak var oldTransport: ARTRealtimeTransport?
        weak var newTransport: ARTRealtimeTransport?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.once(.closing) { _ in
                oldTransport = client.internal.transport
                client.connect()
                newTransport = client.internal.transport
                expect(newTransport).toNot(beIdenticalTo(oldTransport))
                partialDone()
            }

            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(client.connection.errorReason).to(beNil())
                partialDone()
            }

            client.close()
        }

        expect(newTransport).toNot(beNil())
    }

    // RTN11b
    func test__008__Connection__it_should_make_sure_that__when_the_CLOSED_ProtocolMessage_arrives_for_the_old_connection__it_doesn_t_affect_the_new_one() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        var oldTransport: ARTRealtimeTransport? // retain
        weak var newTransport: ARTRealtimeTransport?

        autoreleasepool {
            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(3, done: done)

                client.connection.once(.closing) { _ in
                    client.internalSync { _internal in
                        oldTransport = _internal.transport
                    }
                    // Old connection must complete the close request
                    weak var oldTestProxyTransport = oldTransport as? TestProxyTransport
                    oldTestProxyTransport?.setBeforeIncomingMessageModifier { protocolMessage in
                        if protocolMessage.action == .closed {
                            partialDone()
                        }
                        return protocolMessage
                    }

                    client.connect()

                    client.internalSync { _internal in
                        newTransport = _internal.transport
                    }

                    expect(newTransport).toNot(beIdenticalTo(oldTransport))
                    expect(newTransport).toNot(beNil())
                    expect(oldTransport).toNot(beNil())
                    partialDone()
                }

                client.connection.once(.closed) { _ in
                    fail("New connection should not receive the old connection event")
                }

                client.connection.once(.connected) { _ in
                    partialDone()
                }

                client.close()
            }

            oldTransport = nil
        }

        expect(newTransport).toNot(beNil())
        expect(oldTransport).to(beNil())
    }

    // RTN12

    // RTN12f
    func test__045__Connection__close__if_CONNECTING__do_the_operation_once_CONNECTED() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose() }

        client.connect()
        var lastStateChange: ARTConnectionStateChange?
        client.connection.on { stateChange in
            lastStateChange = stateChange
        }

        client.close()
        expect(lastStateChange).to(beNil())

        expect(lastStateChange).toEventuallyNot(beNil(), timeout: testTimeout)
        expect(lastStateChange!.current).toEventually(equal(ARTRealtimeConnectionState.closed), timeout: testTimeout)
    }

    // RTN12a
    func test__046__Connection__close__if_CONNECTED__should_send_a_CLOSE_action__change_state_to_CLOSING_and_receive_a_CLOSED_action() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer {
            client.dispose()
        }

        let transport = client.internal.transport as! TestProxyTransport
        var states: [ARTRealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                switch state {
                case .connected:
                    client.close()
                case .closing:
                    expect(transport.protocolMessagesSent.filter { $0.action == .close }).to(haveCount(1))
                    states += [state]
                case .closed:
                    expect(transport.protocolMessagesReceived.filter { $0.action == .closed }).to(haveCount(1))
                    states += [state]
                    done()
                default:
                    break
                }
            }
        }

        if states.count != 2 {
            fail("Invalid number of connection states. Expected CLOSING and CLOSE states")
            return
        }
        expect(states[0]).to(equal(ARTRealtimeConnectionState.closing))
        expect(states[1]).to(equal(ARTRealtimeConnectionState.closed))
    }

    // RTN12b
    func test__047__Connection__close__should_transition_to_CLOSED_action_when_the_close_process_timeouts() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer {
            client.dispose()
            client.close()
        }

        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.closed]

        var states: [ARTRealtimeConnectionState] = []
        var start: NSDate?
        var end: NSDate?

        client.connection.on { stateChange in
            let state = stateChange.current
            let error = stateChange.reason
            expect(error).to(beNil())
            switch state {
            case .connected:
                client.close()
            case .closing:
                start = NSDate()
                states += [state]
            case .closed:
                end = NSDate()
                states += [state]
            case .disconnected:
                states += [state]
            default:
                break
            }
        }

        expect(start).toEventuallyNot(beNil(), timeout: testTimeout)
        expect(end).toEventuallyNot(beNil(), timeout: DispatchTimeInterval.milliseconds(Int(1000.0 * ARTDefault.realtimeRequestTimeout())))

        if states.count != 2 {
            fail("Invalid number of connection states. Expected CLOSING and CLOSE states")
            return
        }

        expect(states[0]).to(equal(ARTRealtimeConnectionState.closing))
        expect(states[1]).to(equal(ARTRealtimeConnectionState.closed))
    }

    // RTN12c
    func test__048__Connection__close__transitions_to_the_CLOSING_state_and_then_to_the_CLOSED_state_if_the_transport_is_abruptly_closed() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer {
            client.dispose()
            client.close()
        }

        let transport = client.internal.transport as! TestProxyTransport
        var states: [ARTRealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                expect(error).to(beNil())
                switch state {
                case .connected:
                    states += [state]
                    client.close()
                case .closing:
                    states += [state]
                    transport.simulateIncomingAbruptlyClose()
                case .closed:
                    states += [state]
                    done()
                case .disconnected, .suspended, .failed:
                    states += [state]
                default:
                    break
                }
            }
        }

        if states.count != 3 {
            fail("Invalid number of connection states. Expected CONNECTED, CLOSING and CLOSE states (got \(states.map { $0.rawValue }))")
            return
        }

        expect(states[0]).to(equal(ARTRealtimeConnectionState.connected))
        expect(states[1]).to(equal(ARTRealtimeConnectionState.closing))
        expect(states[2]).to(equal(ARTRealtimeConnectionState.closed))
    }

    // RTN12d
    func test__049__Connection__close__if_DISCONNECTED__aborts_the_retry_and_moves_immediately_to_CLOSED() {
        let options = AblyTests.commonAppSetup()
        options.disconnectedRetryTimeout = 1.0
        let client = ARTRealtime(options: options)
        defer {
            client.close()
            client.dispose()
        }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        client.internal.onDisconnected()
        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.disconnected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once { stateChange in
                expect(stateChange.current).to(equal(ARTRealtimeConnectionState.closed))
                partialDone()
            }

            client.close()

            delay(options.disconnectedRetryTimeout + 0.5) {
                // Make sure the retry doesn't happen.
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closed))
                partialDone()
            }
        }
    }

    // RTN12e
    func test__050__Connection__close__if_SUSPENDED__aborts_the_retry_and_moves_immediately_to_CLOSED() {
        let options = AblyTests.commonAppSetup()
        options.suspendedRetryTimeout = 1.0
        let client = ARTRealtime(options: options)
        defer {
            client.close()
            client.dispose()
        }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        client.internal.onSuspended()
        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.suspended), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once { stateChange in
                expect(stateChange.current).to(equal(ARTRealtimeConnectionState.closed))
                partialDone()
            }

            client.close()

            delay(options.suspendedRetryTimeout + 0.5) {
                // Make sure the retry doesn't happen.
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closed))
                partialDone()
            }
        }
    }

    // RTN13

    // RTN13b
    func test__051__Connection__ping__fails_if_in_the_INITIALIZED__SUSPENDED__CLOSING__CLOSED_or_FAILED_state() {
        let options = AblyTests.commonAppSetup()
        options.suspendedRetryTimeout = 0.1
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer {
            client.close()
            client.dispose()
        }

        var error: ARTErrorInfo?
        func ping() {
            error = nil
            waitUntil(timeout: testTimeout) { done in
                client.ping { e in
                    error = e
                    done()
                }
            }
        }

        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.initialized))
        ping()
        expect(error).toNot(beNil())

        client.connect()
        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        client.internal.onSuspended()

        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.suspended))
        ping()
        expect(error).toNot(beNil())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        client.close()

        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closing))
        ping()
        expect(error).toNot(beNil())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.closed), timeout: testTimeout)
        ping()
        expect(error).toNot(beNil())

        client.internal.onError(AblyTests.newErrorProtocolMessage())

        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.failed))
        ping()
        expect(error).toNot(beNil())
    }

    // RTN13a
    func test__052__Connection__ping__should_send_a_ProtocolMessage_with_action_HEARTBEAT_and_expects_a_HEARTBEAT_message_in_response() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.ping { error in
                expect(error).to(beNil())
                let transport = client.internal.transport as! TestProxyTransport
                expect(transport.protocolMessagesSent.filter { $0.action == .heartbeat }).to(haveCount(1))
                expect(transport.protocolMessagesReceived.filter { $0.action == .heartbeat }).to(haveCount(1))
                done()
            }
        }
    }

    // RTN13c
    func test__053__Connection__ping__should_fail_if_a_HEARTBEAT_ProtocolMessage_is_not_received_within_the_default_realtime_request_timeout() {
        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }
        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(3.0)

        transport.actionsIgnored += [.heartbeat]

        waitUntil(timeout: testTimeout) { done in
            let start = NSDate()
            transport.ignoreSends = true

            client.ping { error in
                guard let error = error else {
                    fail("expected error"); done(); return
                }
                let end = NSDate()
                expect(error.message).to(contain("timed out"))
                expect(end.timeIntervalSince(start as Date)).to(beCloseTo(ARTDefault.realtimeRequestTimeout(), within: 1.5))
                done()
            }
        }
    }

    // RTN14a
    func test__009__Connection__should_enter_FAILED_state_when_API_key_is_invalid() {
        let options = AblyTests.commonAppSetup()
        options.key = String(options.key!.reversed())
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    expect(errorInfo).toNot(beNil())
                    done()
                default:
                    break
                }
            }
            client.connect()
        }
    }

    // RTN14b

    func test__054__Connection__connection_request_fails__on_DISCONNECTED_after_CONNECTED__should_not_emit_error_with_a_renewable_token() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.authCallback = { tokenParams, callback in
            getTestTokenDetails(key: options.key, capability: tokenParams.capability, ttl: tokenParams.ttl as! TimeInterval?, completion: callback)
        }
        let tokenTtl = 3.0
        options.token = getTestToken(key: options.key, ttl: tokenTtl)

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            // Let the token expire
            client.connection.once(.disconnected) { stateChange in
                guard let reason = stateChange.reason else {
                    fail("Token error is missing"); done(); return
                }
                expect(reason.code) == ARTErrorCode.tokenExpired.intValue

                client.connection.on { stateChange in
                    let state = stateChange.current
                    let errorInfo = stateChange.reason
                    switch state {
                    case .connected:
                        expect(errorInfo).to(beNil())
                        // New token
                        expect(client.auth.tokenDetails!.token).toNot(equal(options.token))
                        done()
                    case .failed, .suspended:
                        fail("Should not emit error (\(String(describing: errorInfo)))")
                        done()
                    default:
                        break
                    }
                }
            }
            client.connect()
        }
    }

    func test__055__Connection__connection_request_fails__on_token_error_while_CONNECTING__reissues_token_and_reconnects() {
        var authCallbackCalled = 0

        var tokenTTL = 1.0

        let options = AblyTests.commonAppSetup()
        options.authCallback = { _, callback in
            authCallbackCalled += 1
            getTestTokenDetails(ttl: tokenTTL) { token, err in
                // Let the token expire
                delay(2.0) {
                    callback(token, err)
                }
                // Next time, tokenTTL will be longer so that it doesn't expire right away
                tokenTTL = 60
            }
        }
        options.autoConnect = false

        let realtime = ARTRealtime(options: options)
        defer { realtime.close() }

        var hookToken: AspectToken?
        waitUntil(timeout: testTimeout.multiplied(by: 2)) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            realtime.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                partialDone()
            }
            hookToken = realtime.internal.testSuite_getArgument(from: NSSelectorFromString("onError:"), at: 0) { arg0 in
                guard let message = arg0 as? ARTProtocolMessage, let error = message.error else {
                    fail("Expecting a protocol message with Token error"); partialDone(); return
                }
                expect(error.code).to(equal(ARTErrorCode.tokenExpired.intValue))
                partialDone()
            }
            realtime.connect()
        }
        hookToken?.remove()

        // First token issue, and then reissue on token error.
        expect(authCallbackCalled).to(equal(2))
    }

    func test__056__Connection__connection_request_fails__should_transition_to_disconnected_when_the_token_renewal_fails() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let tokenTtl = 3.0
        let tokenDetails = getTestTokenDetails(key: options.key, capability: nil, ttl: tokenTtl)!
        options.token = tokenDetails.token
        options.authCallback = { _, callback in
            delay(0) {
                callback(tokenDetails, nil) // Return the same expired token again.
            }
        }

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                partialDone()
            }
            client.connection.once(.disconnected) { stateChange in
                guard let reason = stateChange.reason else {
                    fail("Reason is nil"); done(); return
                }
                expect(reason.code).to(equal(ARTErrorCode.tokenExpired.intValue))
                expect(reason.statusCode).to(equal(401))
                expect(reason.message).to(contain("Key/token status changed (expire)"))
                partialDone()
            }
            client.connect()
        }
    }

    func test__057__Connection__connection_request_fails__should_transition_to_Failed_state_because_the_token_is_invalid_and_not_renewable() {
        let options = AblyTests.clientOptions()
        options.autoConnect = false
        let tokenTtl = 1.0
        options.token = getTestToken(ttl: tokenTtl)

        // Let the token expire
        waitUntil(timeout: testTimeout) { done in
            delay(tokenTtl) {
                done()
            }
        }

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        defer {
            client.dispose()
            client.close()
        }

        var transport: TestProxyTransport!

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .connected:
                    fail("Should not be connected")
                    done()
                case .failed, .disconnected, .suspended:
                    guard let errorInfo = errorInfo else {
                        fail("ErrorInfo is nil"); done(); return
                    }
                    expect(errorInfo.code).to(equal(ARTErrorCode.tokenExpired.intValue))
                    done()
                default:
                    break
                }
            }
            client.connect()
            transport = (client.internal.transport as! TestProxyTransport)
        }

        let failures = transport.protocolMessagesReceived.filter { $0.action == .error }

        if failures.count != 1 {
            fail("Should have only one connection request fail")
            return
        }

        expect(failures[0].error!.code).to(equal(ARTErrorCode.tokenExpired.intValue))
    }

    // RTN14c
    func test__058__Connection__connection_request_fails__connection_attempt_should_fail_if_not_connected_within_the_default_realtime_request_timeout() {
        let options = AblyTests.commonAppSetup()
        options.realtimeHost = "10.255.255.1" // non-routable IP address
        options.autoConnect = false
        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(0.5)

        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        var start, end: NSDate?
        waitUntil(timeout: testTimeout) { done in
            client.connection.on(.disconnected) { stateChange in
                end = NSDate()
                expect(stateChange.reason!.message).to(contain("timed out"))
                expect(client.connection.errorReason!).to(beIdenticalTo(stateChange.reason))
                done()
            }
            client.connect()
            start = NSDate()
        }
        if let start = start, let end = end {
            expect(end.timeIntervalSince(start as Date)).to(beCloseTo(ARTDefault.realtimeRequestTimeout(), within: 1.5))
        } else {
            fail("Start date or end date are empty")
        }
    }
    
    // RTN14d, RTB1
    func test__059__Connection__connection_request_fails__if_connection_attempt_fails_connection_state_will_transition_to_DISCONNECTED_with_periodic_connection_attempts_with_incremental_backoff_and_jitter_until_SUSPENDED() {
        let options = AblyTests.commonAppSetup()
        options.realtimeHost = "10.255.255.1" // non-routable IP address
        options.disconnectedRetryTimeout = 0.4 // so expectedTime below would not exceed 3 seconds
        options.autoConnect = false
        
        options.authCallback = { _, _ in
            // Ignore `completion` closure to force a time out
        }
        
        let previousRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRequestTimeout) }
        
        let requestTimeout = 0.1
        ARTDefault.setRealtimeRequestTimeout(requestTimeout)
        
        AblyTests.resetRandomGenerator()
        
        let predefinedDelays = AblyTests.backoffWithJitterDelaysForTimeout(options.disconnectedRetryTimeout)
        let expectedTimeBeforeSuspended = floor(predefinedDelays.reduce(0, { $0 + $1 + requestTimeout }))

        let previousConnectionStateTtl = ARTDefault.connectionStateTtl()
        defer { ARTDefault.setConnectionStateTtl(previousConnectionStateTtl) }
        ARTDefault.setConnectionStateTtl(expectedTimeBeforeSuspended)

        let client = ARTRealtime(options: options)
        client.internal.shouldImmediatelyReconnect = false
        defer {
            client.connection.off()
            client.close()
        }
        
        AblyTests.resetRandomGenerator()
        
        var observedRetryInValues = [TimeInterval]()
        
        waitUntil(timeout: testTimeout) { done in
            var firstDisconnectedAt: Date!
            
            client.connection.once(.disconnected) { stateChange in
                firstDisconnectedAt = Date()
            }
            
            client.connection.on(.disconnected) { stateChange in
                expect(stateChange.reason!.message).to(contain("timed out"))
                expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                observedRetryInValues.append(stateChange.retryIn)
            }
            
            client.connection.on(.suspended) { _ in
                let actualTimeBeforeSuspended = Date().timeIntervalSince(firstDisconnectedAt)
                expect(actualTimeBeforeSuspended).to(beCloseTo(expectedTimeBeforeSuspended, within: 0.9))
                done()
            }

            client.connect()

            client.connection.on(.connecting) { stateChange in
                expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.disconnected))
            }
        }
        expect(observedRetryInValues).to(equal(predefinedDelays))
    }

    // RTN14e, RTN14f
    func test__060__Connection__connection_request_fails__if_connection_state_is_DISCONNECTED_for_more_than_connectionStateTtl_it_will_change_to_SUSPENDED_with_periodic_connection_attemts_within_suspendedRetryTimeout() {
        let options = AblyTests.commonAppSetup()
        options.disconnectedRetryTimeout = 1
        options.suspendedRetryTimeout = 2
        options.autoConnect = false

        options.authCallback = { _, _ in
            // Force a timeout
        }

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(0.1)

        let client = ARTRealtime(options: options)
        client.internal.shouldImmediatelyReconnect = false
        defer { client.dispose(); client.close() }

        let connectionStateTtl = 4.0
        let ttlHookToken = client.overrideConnectionStateTTL(connectionStateTtl)
        defer { ttlHookToken.remove() }
        
        AblyTests.resetRandomGenerator()
        
        var suspendedRetryCount = 0
        let maxSuspendedRetryCount = Int((testTimeout.toTimeInterval() - connectionStateTtl) / options.suspendedRetryTimeout) - 1 // RTN14f, -1 for delays added by realtimeRequestTimeout

        var suspendedAt: Date!
        var firstDisconnectedAt: Date!
        
        waitUntil(timeout: testTimeout) { done in
            
            client.connection.once(.disconnected) { stateChange in
                firstDisconnectedAt = Date()
            }
            
            client.connection.on(.disconnected) { stateChange in
                expect(suspendedAt).to(beNil()) // github.com/ably/ably-cocoa/issues/913
                expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                expect(stateChange.reason?.message).to(contain("timed out"))
            }
            
            client.connection.once(.suspended) { stateChange in
                expect(firstDisconnectedAt).toNot(beNil())
                expect(Date().timeIntervalSince(firstDisconnectedAt)) > connectionStateTtl
            }
            
            client.connection.on(.suspended) { stateChange in
                expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                expect(client.connection.errorReason?.message).to(contain("timed out"))
                suspendedAt = Date()
                suspendedRetryCount += 1
                expect(stateChange.retryIn).to(equal(options.suspendedRetryTimeout))
                
                if suspendedRetryCount == maxSuspendedRetryCount {
                    client.connection.off()
                    done()
                }
            }
            
            client.connect()
        }
    }
    
    func test__062__Connection__connection_request_fails__on_CLOSE_the_connection_should_stop_connection_retries() {
        let options = AblyTests.commonAppSetup()
        // to avoid waiting for the default 15s before trying a reconnection
        options.disconnectedRetryTimeout = 0.1
        options.suspendedRetryTimeout = 0.5
        options.autoConnect = false
        let expectedTime: TimeInterval = 1.0

        options.authCallback = { _, _ in
            // Force a timeout
        }

        let previousConnectionStateTtl = ARTDefault.connectionStateTtl()
        defer { ARTDefault.setConnectionStateTtl(previousConnectionStateTtl) }
        ARTDefault.setConnectionStateTtl(expectedTime)

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(0.1)

        let client = ARTRealtime(options: options)
        client.internal.shouldImmediatelyReconnect = false
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on(.suspended) { _ in
                expect(client.connection.errorReason!.message).to(contain("timed out"))

                let start = NSDate()
                client.connection.once(.connecting) { _ in
                    let end = NSDate()
                    expect(end.timeIntervalSince(start as Date)).to(beCloseTo(options.suspendedRetryTimeout, within: 0.5))
                    done()
                }
            }
            client.connect()
        }

        client.close()

        // Check if the connection gets closed
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) { _ in
                fail("Should be closing the connection"); done()
            }
            delay(2.0) {
                done()
            }
        }
    }

    // RTN15

    // RTN15a
    func test__063__Connection__connection_failures_once_CONNECTED__should_not_receive_published_messages_until_the_connection_reconnects_successfully() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false

        let client1 = ARTRealtime(options: options)
        defer { client1.close() }
        
        let channelName = uniqueChannelName()
        let channel1 = client1.channels.get(channelName)

        var states = [ARTRealtimeConnectionState]()
        client1.connection.on { stateChange in
            states = states + [stateChange.current]
        }
        client1.connect()

        let client2 = ARTRealtime(options: options)
        client2.connect()
        defer { client2.close() }
        let channel2 = client2.channels.get(channelName)

        channel1.subscribe { _ in
            fail("Shouldn't receive the messsage")
        }

        expect(channel1.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        let firstConnection: (id: String, key: String) = (client1.connection.id!, client1.connection.key!)

        // Connection state cannot be resumed
        client1.simulateLostConnectionAndState()

        channel2.publish(nil, data: "message") { errorInfo in
            expect(errorInfo).to(beNil())
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client1.connection.once(.connecting) { _ in
                expect(client1.internal.resuming).to(beTrue())
                partialDone()
            }
            client1.connection.once(.connected) { _ in
                expect(client1.internal.resuming).to(beFalse())
                expect(client1.connection.id).toNot(equal(firstConnection.id))
                expect(client1.connection.key).toNot(equal(firstConnection.key))
                partialDone()
            }
        }

        expect(states).toEventually(equal([.connecting, .connected, .disconnected, .connecting, .connected]), timeout: testTimeout)
    }

    // RTN15a
    func test__064__Connection__connection_failures_once_CONNECTED__if_a_Connection_transport_is_disconnected_unexpectedly_or_if_a_token_expires__then_the_Connection_manager_will_immediately_attempt_to_reconnect() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                // Simulate interruption shortly
                delay(1.0) {
                    client.internal.onDisconnected()
                }
            }
            client.connection.on(.disconnected) { _ in
                let disconnectedTime = Date()
                client.connection.on(.connected) { _ in
                    let reconnectedTime = Date()
                    // test that reconnection happens within 10 seconds,
                    // so that we are sure it doesn't wait for the default 15s
                    expect(reconnectedTime.timeIntervalSince(disconnectedTime)).to(beCloseTo(0, within: 10))
                    done()
                }
            }
            client.connect()
        }
    }

    // RTN15b

    // RTN15b1, RTN15b2
    func test__067__Connection__connection_failures_once_CONNECTED__reconnects_to_the_websocket_endpoint_with_additional_querystring_params__resume_is_the_private_connection_key_and_connection_serial_is_the_most_recent_ProtocolMessage_connectionSerial_received() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let expectedConnectionKey = client.connection.key!
        let expectedConnectionSerial = client.connection.serial
        client.internal.onDisconnected()

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                let transport = client.internal.transport as! TestProxyTransport
                let query = transport.lastUrl!.query
                expect(query).to(haveParam("resume", withValue: expectedConnectionKey))
                expect(query).to(haveParam("connectionSerial", withValue: "\(expectedConnectionSerial)"))
                done()
            }
        }
    }

    // RTN15c

    // RTN15c1
    func test__068__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__CONNECTED_ProtocolMessage_with_the_same_connectionId_as_the_current_client__and_no_error() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let expectedConnectionId = client.connection.id
        client.internal.onDisconnected()

        channel.attach()
        channel.publish(nil, data: "queued message")
        expect(client.internal.queuedMessages).toEventually(haveCount(1), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                let transport = client.internal.transport as! TestProxyTransport
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                expect(connectedPM.connectionId).to(equal(expectedConnectionId))
                expect(stateChange.reason).to(beNil())
                done()
            }
        }
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        expect(client.internal.queuedMessages).toEventually(haveCount(0), timeout: testTimeout)
    }

    // RTN15c2
    func test__069__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__CONNECTED_ProtocolMessage_with_the_same_connectionId_as_the_current_client_and_an_non_fatal_error() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        let expectedConnectionId = client.connection.id
        client.internalAsync { _internal in
            _internal.onDisconnected()
        }

        channel.attach()
        channel.publish(nil, data: "queued message")
        expect(client.internal.queuedMessages).toEventually(haveCount(1), timeout: testTimeout)

        client.connection.once(.connecting) { _ in
            client.internalSync { _internal in
                let transport = _internal.transport as! TestProxyTransport
                transport.setBeforeIncomingMessageModifier { protocolMessage in
                    if protocolMessage.action == .connected {
                        protocolMessage.error = .create(withCode: 0, message: "Injected error")
                    } else if protocolMessage.action == .attached {
                        protocolMessage.error = .create(withCode: 0, message: "Channel injected error")
                    }
                    return protocolMessage
                }
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason?.message).to(equal("Injected error"))
                expect(client.connection.errorReason).to(beIdenticalTo(stateChange.reason))
                let transport = client.internal.transport as! TestProxyTransport
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                expect(connectedPM.connectionId).to(equal(expectedConnectionId))
                expect(client.connection.id).to(equal(expectedConnectionId))
                partialDone()
            }
            channel.once(.attached) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error.message).to(equal("Channel injected error"))
                expect(channel.errorReason).to(beIdenticalTo(error))
                partialDone()
            }
        }

        expect(client.internal.queuedMessages).toEventually(haveCount(0), timeout: testTimeout)
    }

    // RTN15c3
    func test__070__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__CONNECTED_ProtocolMessage_with_a_new_connectionId_and_an_error() {
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

        let oldConnectionId = client.connection.id

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            channel.once(.attaching) { _ in
                expect(channel.errorReason).to(beNil())
                partialDone()
            }

            client.connection.once(.connected) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Connection resume failed and error should be propagated to the channel"); done(); return
                }
                expect(error.code).to(equal(ARTErrorCode.unableToRecoverConnectionExpired.intValue))
                expect(error.message).to(contain("Unable to recover connection"))
                expect(client.connection.errorReason).to(beIdenticalTo(stateChange.reason))
                partialDone()
            }

            client.simulateLostConnectionAndState()
        }

        let transport = client.internal.transport as! TestProxyTransport
        let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
        expect(connectedPM.connectionId).toNot(equal(oldConnectionId))
        expect(client.connection.id).to(equal(connectedPM.connectionId))
        expect(client.internal.msgSerial).to(equal(0))

        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
    }

    // RTN15c4
    func test__071__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__ERROR_ProtocolMessage_indicating_a_fatal_error_in_the_connection() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        client.internal.onDisconnected()

        let protocolError = AblyTests.newErrorProtocolMessage()
        client.connection.once(.connecting) { _ in
            // Resuming
            guard let transport = client.internal.transport as? TestProxyTransport else {
                fail("TestProxyTransport is not set"); return
            }
            transport.actionsIgnored += [.connected]
            client.internal.onError(protocolError)
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.failed) { stateChange in
                expect(stateChange.reason).to(beIdenticalTo(protocolError.error))
                expect(client.connection.errorReason).to(beIdenticalTo(protocolError.error))
                done()
            }
        }
        expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
        expect(channel.errorReason).to(beIdenticalTo(protocolError.error))
    }

    func skipped__test__072__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__should_resume_the_connection_after_an_auth_renewal() {
        let options = AblyTests.commonAppSetup()
        options.tokenDetails = getTestTokenDetails(ttl: 5.0)
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let restOptions = AblyTests.clientOptions(key: options.key!)
        restOptions.channelNamePrefix = options.channelNamePrefix
        let rest = ARTRest(options: restOptions)
        
        let channelName = uniqueChannelName()
        let channel = client.channels.get(channelName)
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        let initialConnectionId = client.connection.id

        guard let _ = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        channel.once(.detached) { _ in
            fail("Should not detach channels")
        }
        defer { channel.off() }

        waitUntil(timeout: testTimeout) { done in
            // Wait for token to expire
            client.connection.once(.disconnected) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                expect(error.code) == ARTErrorCode.tokenExpired.intValue
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            // Wait for connection resume
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
        }

        guard let secondTransport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        let connectedMessages = secondTransport.protocolMessagesReceived.filter { $0.action == .connected }
        expect(connectedMessages).to(haveCount(1)) // New transport connected
        guard let receivedConnectionId = connectedMessages.first?.connectionId else {
            fail("ConnectionID is nil"); return
        }
        expect(client.connection.id).to(equal(receivedConnectionId))
        expect(client.connection.id).to(equal(initialConnectionId))

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            let expectedMessage = ARTMessage(name: "ios", data: "message1")

            channel.subscribe { message in
                expect(message.name).to(equal(expectedMessage.name))
                expect(message.data as? String).to(equal(expectedMessage.data as? String))
                partialDone()
            }

            rest.channels.get(channelName).publish([expectedMessage]) { error in
                expect(error).to(beNil())
                partialDone()
            }
        }
    }

    // FIXME: Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1.2.182436085700
    // RTN15d
    func skipped__test__065__Connection__connection_failures_once_CONNECTED__should_recover_from_disconnection_and_messages_should_be_delivered_once_the_connection_is_resumed() {
        let options = AblyTests.commonAppSetup()

        let client1 = ARTRealtime(options: options)
        defer { client1.close() }
        
        let channelName = uniqueChannelName()
        let channel1 = client1.channels.get(channelName)

        let client2 = ARTRealtime(options: options)
        defer { client2.close() }
        let channel2 = client2.channels.get(channelName)

        let expectedMessages = ["message X", "message Y"]
        var receivedMessages = [String]()

        waitUntil(timeout: testTimeout) { done in
            channel1.subscribe(attachCallback: { errorInfo in
                expect(errorInfo).to(beNil())
                done()
            }, callback: { message in
                receivedMessages.append(message.data as! String)
            })
        }

        client1.internal.onDisconnected()

        channel2.publish(expectedMessages.map { ARTMessage(name: nil, data: $0) }) { errorInfo in
            expect(errorInfo).to(beNil())
        }

        waitUntil(timeout: testTimeout) { done in
            client1.connection.once(.connecting) { _ in
                expect(receivedMessages).to(beEmpty())
                done()
            }
        }

        expect(client1.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        expect(receivedMessages).toEventually(equal(expectedMessages), timeout: testTimeout)
    }

    // RTN15e

    func test__073__Connection__connection_failures_once_CONNECTED__when_a_connection_is_resumed__the_connection_key_may_change_and_will_be_provided_in_the_first_CONNECTED_ProtocolMessage_connectionDetails() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

        client.internal.onDisconnected()

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) { _ in
                client.connection.internal.setKey("key_to_be_replaced")
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                let transport = client.internal.transport as! TestProxyTransport
                let firstConnectionDetails = transport.protocolMessagesReceived.filter { $0.action == .connected }[0].connectionDetails
                expect(firstConnectionDetails!.connectionKey).toNot(beNil())
                expect(client.connection.key).to(equal(firstConnectionDetails!.connectionKey))
                done()
            }
        }
    }

    // RTN15f
    func test__066__Connection__connection_failures_once_CONNECTED__ACK_and_NACK_responses_for_published_messages_can_only_ever_be_received_on_the_transport_connection_on_which_those_messages_were_sent() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        var resumed = false
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            guard let transport1 = client.internal.transport as? TestProxyTransport else {
                fail("TestProxyTransport not setup"); done(); return
            }

            var sentPendingMessage: ARTMessage?
            channel.publish(nil, data: "message") { _ in
                if resumed {
                    guard let transport2 = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport not setup"); done(); return
                    }
                    expect(transport2.protocolMessagesReceived.filter { $0.action == .ack }).to(haveCount(1))

                    guard let _ = transport1.protocolMessagesSent.filter({ $0.action == .message }).first?.messages?.first else {
                        fail("Message that has been re-sent isn't available"); done(); return
                    }
                    guard let sentTransportMessage2 = transport2.protocolMessagesSent.filter({ $0.action == .message }).first?.messages?.first else {
                        fail("Message that has been re-sent isn't available"); done(); return
                    }

                    expect(transport1).toNot(beIdenticalTo(transport2))
                    expect(sentPendingMessage).to(beIdenticalTo(sentTransportMessage2))

                    partialDone()
                } else {
                    fail("Shouldn't be called")
                }
            }
            AblyTests.queue.async {
                client.internal.onDisconnected()
            }
            client.connection.once(.connected) { _ in
                resumed = true
            }
            client.internal.testSuite_injectIntoMethod(before: Selector(("resendPendingMessages"))) {
                expect(client.internal.pendingMessages.count).to(equal(1))
                let pm: ARTProtocolMessage? = (client.internal.pendingMessages.firstObject as? ARTPendingMessage)?.msg
                sentPendingMessage = pm?.messages?[0]
            }
            client.internal.testSuite_injectIntoMethod(after: Selector(("resendPendingMessages"))) {
                partialDone()
            }
        }
    }

    // RTN15g RTN15g1

    func skipped__test__074__Connection__connection_failures_once_CONNECTED__when_connection__ttl_plus_idle_interval__period_has_passed_since_last_activity__uses_a_new_connection() {
        let options = AblyTests.commonAppSetup()
        // We want this to be > than the sum of customTtlInterval and customIdleInterval
        options.disconnectedRetryTimeout = 5.0 + customTtlInterval + customIdleInterval
        ttlAndIdleIntervalPassedTestsClient = AblyTests.newRealtime(options)
        ttlAndIdleIntervalPassedTestsClient.internal.shouldImmediatelyReconnect = false
        ttlAndIdleIntervalPassedTestsClient.connect()
        defer { ttlAndIdleIntervalPassedTestsClient.close() }

        waitUntil(timeout: testTimeout) { done in
            ttlAndIdleIntervalPassedTestsClient.connection.once(.connected) { _ in
                expect(ttlAndIdleIntervalPassedTestsClient.connection.id).toNot(beNil())
                ttlAndIdleIntervalPassedTestsConnectionId = ttlAndIdleIntervalPassedTestsClient.connection.id!
                ttlAndIdleIntervalPassedTestsClient.internal.connectionStateTtl = customTtlInterval
                ttlAndIdleIntervalPassedTestsClient.internal.maxIdleInterval = customIdleInterval
                ttlAndIdleIntervalPassedTestsClient.connection.once(.disconnected) { _ in
                    let disconnectedAt = Date()
                    expect(ttlAndIdleIntervalPassedTestsClient.internal.connectionStateTtl).to(equal(customTtlInterval))
                    expect(ttlAndIdleIntervalPassedTestsClient.internal.maxIdleInterval).to(equal(customIdleInterval))
                    ttlAndIdleIntervalPassedTestsClient.connection.once(.connecting) { _ in
                        let reconnectionInterval = Date().timeIntervalSince(disconnectedAt)
                        expect(reconnectionInterval).to(beGreaterThan(ttlAndIdleIntervalPassedTestsClient.internal.connectionStateTtl + ttlAndIdleIntervalPassedTestsClient.internal.maxIdleInterval))
                        ttlAndIdleIntervalPassedTestsClient.connection.once(.connected) { _ in
                            expect(ttlAndIdleIntervalPassedTestsClient.connection.id).toNot(equal(ttlAndIdleIntervalPassedTestsConnectionId))
                            done()
                        }
                    }
                }
                ttlAndIdleIntervalPassedTestsClient.internal.onDisconnected()
            }
        }
    }

    // RTN15g3
    func test__075__Connection__connection_failures_once_CONNECTED__when_connection__ttl_plus_idle_interval__period_has_passed_since_last_activity__reattaches_to_the_same_channels_after_a_new_connection_has_been_established() {
        let options = AblyTests.commonAppSetup()
        // We want this to be > than the sum of customTtlInterval and customIdleInterval
        options.disconnectedRetryTimeout = 5.0
        ttlAndIdleIntervalPassedTestsClient = AblyTests.newRealtime(options)
        ttlAndIdleIntervalPassedTestsClient.internal.shouldImmediatelyReconnect = false
        defer { ttlAndIdleIntervalPassedTestsClient.close() }
        let channelName = uniqueChannelName()
        let channel = ttlAndIdleIntervalPassedTestsClient.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            ttlAndIdleIntervalPassedTestsClient.connection.once(.connected) { _ in
                ttlAndIdleIntervalPassedTestsConnectionId = ttlAndIdleIntervalPassedTestsClient.connection.id!
                ttlAndIdleIntervalPassedTestsClient.internal.connectionStateTtl = customTtlInterval
                ttlAndIdleIntervalPassedTestsClient.internal.maxIdleInterval = customIdleInterval
                channel.attach { error in
                    if let error = error {
                        fail(error.message)
                    }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                    ttlAndIdleIntervalPassedTestsClient.internal.onDisconnected()
                }
                ttlAndIdleIntervalPassedTestsClient.connection.once(.disconnected) { _ in
                    ttlAndIdleIntervalPassedTestsClient.connection.once(.connecting) { _ in
                        ttlAndIdleIntervalPassedTestsClient.connection.once(.connected) { _ in
                            expect(ttlAndIdleIntervalPassedTestsClient.connection.id).toNot(equal(ttlAndIdleIntervalPassedTestsConnectionId))
                            channel.once(.attached) { stateChange in
                                expect(stateChange.resumed).to(beFalse())
                                done()
                            }
                        }
                    }
                }
            }
            ttlAndIdleIntervalPassedTestsClient.connect()
        }
    }

    // RTN15g2

    func test__076__Connection__connection_failures_once_CONNECTED__when_connection__ttl_plus_idle_interval__period_has_NOT_passed_since_last_activity__uses_the_same_connection() {
        let options = AblyTests.commonAppSetup()
        ttlAndIdleIntervalNotPassedTestsClient = AblyTests.newRealtime(options)
        ttlAndIdleIntervalNotPassedTestsClient.connect()
        defer { ttlAndIdleIntervalNotPassedTestsClient.close() }

        waitUntil(timeout: testTimeout) { done in
            ttlAndIdleIntervalNotPassedTestsClient.connection.once(.connected) { _ in
                expect(ttlAndIdleIntervalNotPassedTestsClient.connection.id).toNot(beNil())
                ttlAndIdleIntervalNotPassedTestsConnectionId = ttlAndIdleIntervalNotPassedTestsClient.connection.id!
                ttlAndIdleIntervalNotPassedTestsClient.connection.once(.disconnected) { _ in
                    let disconnectedAt = Date()
                    ttlAndIdleIntervalNotPassedTestsClient.connection.once(.connecting) { _ in
                        let reconnectionInterval = Date().timeIntervalSince(disconnectedAt)
                        expect(reconnectionInterval).to(beLessThan(ttlAndIdleIntervalNotPassedTestsClient.internal.connectionStateTtl + ttlAndIdleIntervalNotPassedTestsClient.internal.maxIdleInterval))
                        ttlAndIdleIntervalNotPassedTestsClient.connection.once(.connected) { _ in
                            expect(ttlAndIdleIntervalNotPassedTestsClient.connection.id).to(equal(ttlAndIdleIntervalNotPassedTestsConnectionId))
                            done()
                        }
                    }
                }
                ttlAndIdleIntervalNotPassedTestsClient.internal.onDisconnected()
            }
        }
    }

    // RTN15h

    func skipped__test__077__Connection__connection_failures_once_CONNECTED__DISCONNECTED_message_contains_a_token_error__if_the_token_is_renewable_then_error_should_not_be_emitted() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.authCallback = { tokenParams, callback in
            getTestTokenDetails(key: options.key, capability: tokenParams.capability, ttl: TimeInterval(60 * 60), completion: callback)
        }
        let tokenTtl = 2.0
        options.token = getTestToken(key: options.key, ttl: tokenTtl)

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        defer {
            client.dispose()
            client.close()
        }

        client.connect()
        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        let firstTransport = client.internal.transport as? TestProxyTransport

        waitUntil(timeout: testTimeout) { done in
            // Wait for token to expire
            client.connection.once(.disconnected) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                expect(error.code) == ARTErrorCode.tokenExpired.intValue
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
        }
        expect(client.connection.errorReason).to(beNil())

        // New connection
        expect(client.internal.transport).toNot(beNil())
        expect(client.internal.transport).toNot(beIdenticalTo(firstTransport))

        waitUntil(timeout: testTimeout) { done in
            client.ping { error in
                expect(error).to(beNil())
                expect((client.internal.transport as! TestProxyTransport).protocolMessagesReceived.filter { $0.action == .connected }).to(haveCount(1))
                done()
            }
        }
    }

    // RTN15h1
    func test__078__Connection__connection_failures_once_CONNECTED__DISCONNECTED_message_contains_a_token_error__and_the_library_does_not_have_a_means_to_renew_the_token__the_connection_will_transition_to_the_FAILED_state() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let key = options.key
        // set the key to nil so that the client can't sign further token requests
        options.key = nil
        let tokenTtl = 3.0
        let tokenDetails = getTestTokenDetails(key: key, ttl: tokenTtl)!
        options.token = tokenDetails.token
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.failed) { stateChange in
                expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connected))
                expect(stateChange.reason?.code).to(equal(ARTErrorCode.tokenExpired.intValue))
                done()
            }
            client.connect()
        }
    }

    // RTN15h2
    func skipped__test__079__Connection__connection_failures_once_CONNECTED__DISCONNECTED_message_contains_a_token_error__should_transition_to_disconnected_when_the_token_renewal_fails_and_the_error_should_be_emitted() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let tokenTtl = 3.0
        let tokenDetails = getTestTokenDetails(key: options.key, capability: nil, ttl: tokenTtl)!
        options.token = tokenDetails.token
        options.authCallback = { _, callback in
            delay(0.1) {
                callback(tokenDetails, nil) // Return the same expired token again.
            }
        }

        let client = ARTRealtime(options: options)
        client.internal.setTransport(TestProxyTransport.self)
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            // Wait for token to expire
            client.connection.once(.disconnected) { stateChange in
                expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connected))
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                expect(error.code) == ARTErrorCode.tokenExpired.intValue

                // Renewal will lead to another disconnection
                client.connection.once(.disconnected) { stateChange in
                    guard let error = stateChange.reason else {
                        fail("Error is nil"); done(); return
                    }
                    expect(error.code) == ARTErrorCode.tokenExpired.intValue
                    expect(client.connection.errorReason).to(beIdenticalTo(error))
                    done()
                }
            }

            client.connect()
        }
    }

    // RTN16

    // RTN16a
    func test__080__Connection__Connection_recovery__connection_state_should_recover_explicitly_with_a_recover_key() {
        let options = AblyTests.commonAppSetup()

        let clientSend = ARTRealtime(options: options)
        defer { clientSend.close() }
        
        let channelName = uniqueChannelName()
        let channelSend = clientSend.channels.get(channelName)

        let clientReceive = ARTRealtime(options: options)
        defer { clientReceive.close() }
        let channelReceive = clientReceive.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channelReceive.subscribe(attachCallback: { error in
                expect(error).to(beNil())
                channelSend.publish(nil, data: "message") { error in
                    expect(error).to(beNil())
                }
            }, callback: { message in
                expect(message.data as? String).to(equal("message"))
                done()
            })
        }

        options.recover = clientReceive.connection.recoveryKey
        clientReceive.internal.onError(AblyTests.newErrorProtocolMessage())

        waitUntil(timeout: testTimeout) { done in
            channelSend.publish(nil, data: "queue a message") { error in
                expect(error).to(beNil())
                done()
            }
        }

        let clientRecover = ARTRealtime(options: options)
        defer { clientRecover.close() }
        let channelRecover = clientRecover.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channelRecover.subscribe { message in
                expect(message.data as? String).to(equal("queue a message"))
                done()
            }
        }
    }

    // RTN16b
    func test__081__Connection__Connection_recovery__Connection_recoveryKey_should_be_composed_with_the_connection_key_and_latest_serial_received_and_msgSerial() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)
            client.connection.once(.connected) { _ in
                expect(client.connection.serial).to(equal(-1))
                expect(client.connection.recoveryKey).to(equal("\(client.connection.key!):\(client.connection.serial):\(client.internal.msgSerial)"))
                partialDone()
            }
            channel.subscribe(attachCallback: { error in
                expect(error).to(beNil())
                
                channel.publish(nil, data: "message") { error in
                    expect(error).to(beNil())
                    partialDone()
                }
            }, callback: { message in
                expect(message.data as? String).to(equal("message"))
                expect(client.connection.serial).to(equal(0))
                channel.unsubscribe()
                partialDone()
            })
        }
        expect(client.internal.msgSerial) == 1
        expect(client.connection.recoveryKey).to(equal("\(client.connection.key!):\(client.connection.serial):\(client.internal.msgSerial)"))
    }

    // RTN16d
    func test__082__Connection__Connection_recovery__when_a_connection_is_successfully_recovered__Connection_id_will_be_identical_to_the_id_of_the_connection_that_was_recovered_and_Connection_key_will_always_be_updated_to_the_ConnectionDetails_connectionKey_provided_in_the_first_CONNECTED_ProtocolMessage() {
        let options = AblyTests.commonAppSetup()
        let clientOriginal = ARTRealtime(options: options)
        defer { clientOriginal.close() }

        expect(clientOriginal.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        let expectedConnectionId = clientOriginal.connection.id

        options.recover = clientOriginal.connection.recoveryKey
        clientOriginal.internal.onError(AblyTests.newErrorProtocolMessage())

        let clientRecover = AblyTests.newRealtime(options)
        defer { clientRecover.close() }

        waitUntil(timeout: testTimeout) { done in
            clientRecover.connection.once(.connected) { _ in
                let transport = clientRecover.internal.transport as! TestProxyTransport
                let firstConnectionDetails = transport.protocolMessagesReceived.filter { $0.action == .connected }.first!.connectionDetails
                expect(firstConnectionDetails!.connectionKey).toNot(beNil())
                expect(clientRecover.connection.id).to(equal(expectedConnectionId))
                expect(clientRecover.connection.key).to(equal(firstConnectionDetails!.connectionKey))
                done()
            }
        }
    }

    // RTN16c
    func skipped__test__083__Connection__Connection_recovery__Connection_recoveryKey_should_become_becomes_null_when_a_connection_is_explicitly_CLOSED_or_CLOSED() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                client.connection.once(.closed) { _ in
                    expect(client.connection.recoveryKey).to(beNil())
                    expect(client.connection.key).to(beNil())
                    expect(client.connection.id).to(beNil())
                    done()
                }
                client.close()
            }
        }
    }

    // RTN16e
    func test__084__Connection__Connection_recovery__should_connect_anyway_if_the_recoverKey_is_no_longer_valid() {
        let options = AblyTests.commonAppSetup()
        options.recover = "99999!xxxxxx-xxxxxxxxx-xxxxxxxxx:-1"
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                guard let reason = stateChange.reason else {
                    fail("Reason is empty"); done(); return
                }
                expect(reason.message).to(contain("Unable to recover connection"))
                expect(client.connection.errorReason).to(beIdenticalTo(reason))
                done()
            }
        }
    }

    // RTN16f
    func test__085__Connection__Connection_recovery__should_use_msgSerial_from_recoveryKey_to_set_the_client_internal_msgSerial_but_is_not_sent_to_Ably() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.recover = "99999!xxxxxx-xxxxxxxxx-xxxxxxxxx:-1:7"

        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }

        var urlConnections = [URL]()
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
            if urlConnections.count == 1 {
                TestProxyTransport.networkConnectEvent = nil
            }
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                guard let reason = stateChange.reason else {
                    fail("Reason is empty"); done(); return
                }

                expect(urlConnections.count) == 1
                guard let urlConnectionQuery = urlConnections.first?.query else {
                    fail("Missing URL Connection query"); done(); return
                }

                expect(urlConnectionQuery).to(haveParam("recover", withValue: "99999!xxxxxx-xxxxxxxxx-xxxxxxxxx"))
                expect(urlConnectionQuery).to(haveParam("connectionSerial", withValue: "-1"))
                expect(urlConnectionQuery).toNot(haveParam("msgSerial"))

                // recover fails, the counter should be reset to 0
                expect(client.internal.msgSerial) == 0

                expect(reason.message).to(contain("Unable to recover connection"))
                expect(client.connection.errorReason).to(beIdenticalTo(reason))
                done()
            }
            client.connect()
            expect(client.internal.msgSerial) == 7
        }
    }

    // RTN17

    func beforeEach__Connection__Host_Fallback() {
        ARTFallback_shuffleArray = { array in
            let arranged = expectedHostOrder.reversed().map { array[$0] }
            for (i, element) in arranged.enumerated() {
                array[i] = element
            }
        }
    }

    func afterEach__Connection__Host_Fallback() {
        ARTFallback_shuffleArray = originalARTFallback_shuffleArray
    }

    // RTN17b
    @available(*, deprecated, message: "This test is marked as deprecated so as to not trigger a compiler warning for using the -ARTClientOptions.fallbackHostsUseDefault property. Remove this deprecation when removing the property.")
    func test__086__Connection__Host_Fallback__failing_connections_with_custom_endpoint_should_result_in_an_error_immediately() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.environment = "test" // do not use the default endpoint
        expect(options.fallbackHostsUseDefault).to(beFalse())
        expect(options.fallbackHosts).to(beNil())
        options.autoConnect = false
        options.queueMessages = false

        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())

        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        var urlConnections = [URL]()
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                expect(stateChange.previous) == ARTRealtimeConnectionState.connecting
                expect(stateChange.current) == ARTRealtimeConnectionState.disconnected
                guard let reason = stateChange.reason else {
                    fail("Reason is empty"); done(); return
                }
                expect(reason.message).to(contain("host unreachable"))
                done()
            }
            client.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error?.code).to(equal(2))
                expect(error?.message).to(contain("host unreachable"))
                expect(error?.reason).to(contain(".FakeNetworkResponse"))
                done()
            }
        }

        expect(urlConnections).to(haveCount(1))

        afterEach__Connection__Host_Fallback()
    }

    // RTN17b
    @available(*, deprecated, message: "This test is marked as deprecated so as to not trigger a compiler warning for using the -ARTClientOptions.fallbackHostsUseDefault property. Remove this deprecation when removing the property.")
    func test__087__Connection__Host_Fallback__failing_connections_with_custom_endpoint_should_result_in_time_outs() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.environment = "test" // do not use the default endpoint
        expect(options.fallbackHostsUseDefault).to(beFalse())
        expect(options.fallbackHosts).to(beNil())
        options.autoConnect = false

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        client.channels.get(uniqueChannelName())

        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        var urlConnections = [URL]()
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on(.disconnected) { stateChange in
                expect(stateChange.previous) == ARTRealtimeConnectionState.connecting
                expect(stateChange.current) == ARTRealtimeConnectionState.disconnected
                guard let reason = stateChange.reason else {
                    fail("Reason is empty"); done(); return
                }
                expect(reason.message).to(contain("host unreachable"))
                done()
            }
            client.connect()
        }

        expect(urlConnections).to(haveCount(1))

        afterEach__Connection__Host_Fallback()
    }

    // RTN17b
    func test__088__Connection__Host_Fallback__applies_when_the_default_realtime_ably_io_endpoint_is_being_used() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(uniqueChannelName())

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        client.internal.setTransport(TestProxyTransport.self)
        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        var urlConnections = [URL]()
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
            if urlConnections.count == 1 {
                TestProxyTransport.fakeNetworkResponse = nil
            }
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        waitUntil(timeout: testTimeout) { done in
            // wss://[a-e].ably-realtime.com: when a timeout occurs
            client.connection.once(.disconnected) { _ in
                done()
            }
            // wss://[a-e].ably-realtime.com: when a 401 occurs because of the `xxxx:xxxx` key
            client.connection.once(.failed) { _ in
                done()
            }
            client.connect()
        }

        expect(urlConnections).to(haveCount(2))
        if urlConnections.count != 2 {
            return
        }
        expect(NSRegularExpression.match(urlConnections[0].absoluteString, pattern: "//realtime.ably.io")).to(beTrue())
        expect(NSRegularExpression.match(urlConnections[1].absoluteString, pattern: "//[a-e].ably-realtime.com")).to(beTrue())

        afterEach__Connection__Host_Fallback()
    }

    func test__089__Connection__Host_Fallback__applies_when_an_array_of_ClientOptions_fallbackHosts_is_provided() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        options.fallbackHosts = ["f.ably-realtime.com", "g.ably-realtime.com", "h.ably-realtime.com", "i.ably-realtime.com", "j.ably-realtime.com"]
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(uniqueChannelName())

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        client.internal.setTransport(TestProxyTransport.self)
        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        var urlConnections = [URL]()
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
            if urlConnections.count == 1 {
                TestProxyTransport.fakeNetworkResponse = nil
            }
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        waitUntil(timeout: testTimeout) { done in
            // wss://[a-e].ably-realtime.com: when a timeout occurs
            client.connection.once(.disconnected) { _ in
                done()
            }
            // wss://[a-e].ably-realtime.com: when a 401 occurs because of the `xxxx:xxxx` key
            client.connection.once(.failed) { _ in
                done()
            }
            client.connect()
        }

        expect(urlConnections.count > 1 && urlConnections.count <= options.fallbackHosts!.count + 1).to(beTrue())
        expect(NSRegularExpression.match(urlConnections[0].absoluteString, pattern: "//realtime.ably.io")).to(beTrue())
        for connection in urlConnections.dropFirst() {
            expect(NSRegularExpression.match(connection.absoluteString, pattern: "//[f-j].ably-realtime.com")).to(beTrue())
        }

        afterEach__Connection__Host_Fallback()
    }

    // RTN17d

    func skipped__test__097__Connection__Host_Fallback__should_use_an_alternative_host_when___hostUnreachable() {
        beforeEach__Connection__Host_Fallback()

        testUsesAlternativeHostOnResponse(.hostUnreachable, channelName: uniqueChannelName())

        afterEach__Connection__Host_Fallback()
    }

    func skipped__test__098__Connection__Host_Fallback__should_use_an_alternative_host_when___requestTimeout_timeout__0_1_() {
        beforeEach__Connection__Host_Fallback()

        testUsesAlternativeHostOnResponse(.requestTimeout(timeout: 0.1), channelName: uniqueChannelName())

        afterEach__Connection__Host_Fallback()
    }

    func skipped__test__099__Connection__Host_Fallback__should_use_an_alternative_host_when___hostInternalError_code__501_() {
        beforeEach__Connection__Host_Fallback()

        testUsesAlternativeHostOnResponse(.hostInternalError(code: 501), channelName: uniqueChannelName())

        afterEach__Connection__Host_Fallback()
    }

    func test__100__Connection__Host_Fallback__should_move_to_disconnected_when_there_s_no_internet__with_NSPOSIXErrorDomain_with_code_57() {
        beforeEach__Connection__Host_Fallback()

        testMovesToDisconnectedWithNetworkingError(NSError(domain: "NSPOSIXErrorDomain", code: 57, userInfo: [NSLocalizedDescriptionKey: "shouldn't matter"]))

        afterEach__Connection__Host_Fallback()
    }

    func test__101__Connection__Host_Fallback__should_move_to_disconnected_when_there_s_no_internet__with_NSPOSIXErrorDomain_with_code_50() {
        beforeEach__Connection__Host_Fallback()

        testMovesToDisconnectedWithNetworkingError(NSError(domain: "NSPOSIXErrorDomain", code: 50, userInfo: [NSLocalizedDescriptionKey: "shouldn't matter"]))

        afterEach__Connection__Host_Fallback()
    }

    func test__102__Connection__Host_Fallback__should_move_to_disconnected_when_there_s_no_internet__with_any_kCFErrorDomainCFNetwork() {
        beforeEach__Connection__Host_Fallback()

        testMovesToDisconnectedWithNetworkingError(NSError(domain: "kCFErrorDomainCFNetwork", code: 1337, userInfo: [NSLocalizedDescriptionKey: "shouldn't matter"]))

        afterEach__Connection__Host_Fallback()
    }

    func test__090__Connection__Host_Fallback__should_not_use_an_alternative_host_when_the_client_receives_a_bad_request() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        let channel = client.channels.get(uniqueChannelName())

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        client.internal.setTransport(TestProxyTransport.self)
        TestProxyTransport.fakeNetworkResponse = .host400BadRequest
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        var urlConnections = [URL]()
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { _ in
                done()
            }
        }

        expect(urlConnections).to(haveCount(1))
        expect(NSRegularExpression.match(urlConnections[0].absoluteString, pattern: "//realtime.ably.io")).to(beTrue())

        afterEach__Connection__Host_Fallback()
    }

    // RTN17a
    func test__091__Connection__Host_Fallback__every_connection_is_first_attempted_to_the_primary_host_realtime_ably_io() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(uniqueChannelName())

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        client.internal.setTransport(TestProxyTransport.self)
        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        var urlConnections = [URL]()
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
            TestProxyTransport.fakeNetworkResponse = nil
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        waitUntil(timeout: testTimeout) { done in
            // Unreachable and try a fallback
            client.connection.on { stateChange in
                // Timeout or 401 occurs because of the `xxxx:xxxx` key
                if stateChange.current == .disconnected || stateChange.current == .failed {
                    client.connection.off()
                    done()
                }
            }
            client.connect()
        }

        client.connect()

        waitUntil(timeout: testTimeout) { done in
            // 401 occurs because of the `xxxx:xxxx` key
            client.connection.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                expect(error.message).to(contain("Invalid key"))
                done()
            }
        }

        expect(urlConnections).to(haveCount(3))
        expect(NSRegularExpression.match(urlConnections.at(0)?.absoluteString, pattern: "//realtime.ably.io")).to(beTrue())
        expect(NSRegularExpression.match(urlConnections.at(1)?.absoluteString, pattern: "//[a-e].ably-realtime.com")).to(beTrue())
        expect(NSRegularExpression.match(urlConnections.at(2)?.absoluteString, pattern: "//realtime.ably.io")).to(beTrue())

        afterEach__Connection__Host_Fallback()
    }

    // RTN17c
    func test__092__Connection__Host_Fallback__should_retry_hosts_in_random_order_after_checkin_if_an_internet_connection_is_available() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(uniqueChannelName())

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(5.0)

        let testHttpExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.rest.httpExecutor = testHttpExecutor

        client.internal.setTransport(TestProxyTransport.self)
        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }
        
        let hostPrefixes = Array("abcde")
        
        let extractHostname = { (url: URL) in
            NSRegularExpression.extract(url.absoluteString, pattern: "[\(hostPrefixes.first!)-\(hostPrefixes.last!)].ably-realtime.com")
        }
        
        var urls = [URL]()
        let expectedFallbackHosts = Array(expectedHostOrder.map { ARTDefault.fallbackHosts()[$0] })
        let allFallbackHostsTriedOfFailedExp = XCTestExpectation(description: "TestProxyTransport should spit 5 fallback hosts on networkConnectEvent")
        
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            DispatchQueue.main.async {
                urls.append(url)
            }
        }
        defer { TestProxyTransport.networkConnectEvent = nil }
        
        testHttpExecutor.setListenerAfterRequest { request in
            urls.append(request.url!)
        }

        waitUntil(timeout: testTimeout) { done in
            // wss://[a-e].ably-realtime.com: when a timeout occurs
            client.connection.once(.disconnected) { _ in
                done()
                allFallbackHostsTriedOfFailedExp.fulfill()
            }
            // wss://[a-e].ably-realtime.com: when a 401 occurs because of the `xxxx:xxxx` key
            client.connection.once(.failed) { _ in
                done()
                allFallbackHostsTriedOfFailedExp.fulfill()
            }
            client.connect()
        }
        
        wait(for: [allFallbackHostsTriedOfFailedExp], timeout: testTimeout.toTimeInterval())

        var resultFallbackHosts = [String]()
        var gotInternetIsUpCheck = false
        for url in urls {
            if NSRegularExpression.match(url.absoluteString, pattern: "//internet-up.ably-realtime.com/is-the-internet-up.txt") {
                gotInternetIsUpCheck = true
            } else if let fallbackHost = extractHostname(url) {
                if Optional(fallbackHost) == resultFallbackHosts.last {
                    continue
                }
                // Host changed; should've had an internet check before.
                expect(gotInternetIsUpCheck).to(beTrue())
                gotInternetIsUpCheck = false
                resultFallbackHosts.append(fallbackHost)
            }
        }

        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))

        afterEach__Connection__Host_Fallback()
    }

    // RTN17c
    func test__093__Connection__Host_Fallback__doesn_t_try_fallback_host_if_Internet_connection_check_fails() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(uniqueChannelName())

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(1.0)

        let mockHTTP = MockHTTP(logger: options.logHandler)
        let testHttpExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.rest.httpExecutor = testHttpExecutor

        client.internal.setTransport(TestProxyTransport.self)
        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        let extractHostname = { (url: URL) in
            NSRegularExpression.extract(url.absoluteString, pattern: "[a-e].ably-realtime.com")
        }

        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            if extractHostname(url) != nil {
                fail("shouldn't try fallback host after failed connectivity check")
            }
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        mockHTTP.setNetworkState(network: .hostInternalError(code: 500), forHost: "internet-up.ably-realtime.com")

        waitUntil(timeout: testTimeout) { done in
            // wss://[a-e].ably-realtime.com: when a timeout occurs
            client.connection.once(.disconnected) { _ in
                done()
            }
            // wss://[a-e].ably-realtime.com: when a 401 occurs because of the `xxxx:xxxx` key
            client.connection.once(.failed) { _ in
                done()
            }
            client.connect()
        }

        afterEach__Connection__Host_Fallback()
    }

    func test__094__Connection__Host_Fallback__should_retry_custom_fallback_hosts_in_random_order_after_checkin_if_an_internet_connection_is_available() {
        beforeEach__Connection__Host_Fallback()

        let hostPrefixes = Array("fghij")
        let expectedFallbackHosts = Array(expectedHostOrder.map { "\(hostPrefixes[$0]).ably-realtime.com" })

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        options.fallbackHosts = expectedFallbackHosts.sorted() // will be picked "randomly" as of expectedHostOrder
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(uniqueChannelName())

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(5.0)

        let testHttpExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.rest.httpExecutor = testHttpExecutor

        client.internal.setTransport(TestProxyTransport.self)
        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        let extractHostname = { (url: URL) in
            NSRegularExpression.extract(url.absoluteString, pattern: "[\(hostPrefixes.first!)-\(hostPrefixes.last!)].ably-realtime.com")
        }
        
        var urls = [URL]()
        let allFallbackHostsTriedOfFailedExp = XCTestExpectation(description: "TestProxyTransport should spit 5 fallback hosts on networkConnectEvent")
        
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            DispatchQueue.main.async {
                urls.append(url)
            }
        }
        
        defer { TestProxyTransport.networkConnectEvent = nil }

        testHttpExecutor.setListenerAfterRequest { request in
            urls.append(request.url!)
        }

        waitUntil(timeout: testTimeout) { done in
            // wss://[a-e].ably-realtime.com: when a timeout occurs
            client.connection.once(.disconnected) { _ in
                done()
                allFallbackHostsTriedOfFailedExp.fulfill()
            }
            // wss://[a-e].ably-realtime.com: when a 401 occurs because of the `xxxx:xxxx` key
            client.connection.once(.failed) { _ in
                done()
                allFallbackHostsTriedOfFailedExp.fulfill()
            }
            client.connect()
        }
        
        wait(for: [allFallbackHostsTriedOfFailedExp], timeout: testTimeout.toTimeInterval())

        var resultFallbackHosts = [String]()
        var gotInternetIsUpCheck = false
        for url in urls {
            if NSRegularExpression.match(url.absoluteString, pattern: "//internet-up.ably-realtime.com/is-the-internet-up.txt") {
                gotInternetIsUpCheck = true
            } else if let fallbackHost = extractHostname(url) {
                if Optional(fallbackHost) == resultFallbackHosts.last {
                    continue
                }
                // Host changed; should've had an internet check before.
                expect(gotInternetIsUpCheck).to(beTrue())
                gotInternetIsUpCheck = false
                resultFallbackHosts.append(fallbackHost)
            }
        }

        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))

        afterEach__Connection__Host_Fallback()
    }

    func test__095__Connection__Host_Fallback__won_t_use_fallback_hosts_feature_if_an_empty_array_is_provided() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        options.fallbackHosts = []
        let client = ARTRealtime(options: options)
        let channel = client.channels.get(uniqueChannelName())

        let testHttpExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.rest.httpExecutor = testHttpExecutor

        client.internal.setTransport(TestProxyTransport.self)
        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        var urlConnections = [URL]()
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { _ in
                done()
            }
        }

        expect(urlConnections).to(haveCount(1))

        afterEach__Connection__Host_Fallback()
    }

    // RTN17e
    func test__096__Connection__Host_Fallback__client_is_connected_to_a_fallback_host_endpoint_should_do_HTTP_requests_to_the_same_data_centre() {
        beforeEach__Connection__Host_Fallback()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        let client = ARTRealtime(options: options)

        let testHttpExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.rest.httpExecutor = testHttpExecutor

        client.internal.setTransport(TestProxyTransport.self)
        TestProxyTransport.fakeNetworkResponse = .hostUnreachable
        defer { TestProxyTransport.fakeNetworkResponse = nil }

        var urlConnections = [URL]()
        TestProxyTransport.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
            if urlConnections.count == 2 {
                TestProxyTransport.fakeNetworkResponse = nil
                (client.internal.transport as! TestProxyTransport).simulateTransportSuccess()
            }
        }
        defer { TestProxyTransport.networkConnectEvent = nil }

        client.connect()
        // Because we're faking the CONNECTED state, we can't client.close() or it
        // will actually try to use the connection believing it's ready and throw an
        // exception because it's really not.

        expect(urlConnections).toEventually(haveCount(2), timeout: testTimeout)

        expect(NSRegularExpression.match(urlConnections.at(1)?.absoluteString, pattern: "//[a-e].ably-realtime.com")).to(beTrue())

        waitUntil(timeout: testTimeout) { done in
            client.time { _, _ in
                done()
            }
        }

        let timeRequestUrl = testHttpExecutor.requests.last!.url!
        expect(timeRequestUrl.host).to(equal(urlConnections.at(1)?.host))

        afterEach__Connection__Host_Fallback()
    }

    // RTN19
    func test__010__Connection__attributes_within_ConnectionDetails_should_be_used_as_defaults() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        let realtime = AblyTests.newRealtime(options)
        defer { realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connecting) { stateChange in
                expect(stateChange.reason).to(beNil())

                let transport = realtime.internal.transport as! TestProxyTransport
                transport.setBeforeIncomingMessageModifier { protocolMessage in
                    if protocolMessage.action == .connected {
                        protocolMessage.connectionDetails!.clientId = "john"
                        protocolMessage.connectionDetails!.connectionKey = "123"
                    }
                    return protocolMessage
                }
            }
            realtime.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())

                let transport = realtime.internal.transport as! TestProxyTransport
                let connectedProtocolMessage = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]

                expect(realtime.auth.clientId).to(equal(connectedProtocolMessage.connectionDetails!.clientId))
                expect(realtime.connection.key).to(equal(connectedProtocolMessage.connectionDetails!.connectionKey))
                done()
            }
            realtime.connect()
        }

        let transport = realtime.internal.transport as! TestProxyTransport
        let connectedProtocolMessage = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
        expect(realtime.auth.clientId).to(equal(connectedProtocolMessage.connectionDetails!.clientId))
        expect(realtime.connection.key).to(equal(connectedProtocolMessage.connectionDetails!.connectionKey))
    }

    // RTN19a
    func skipped__test__103__Connection__Transport_disconnected_side_effects__should_resend_any_ProtocolMessage_that_is_awaiting_a_ACK_NACK() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport

        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in done() }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                guard let newTransport = client.internal.transport as? TestProxyTransport else {
                    fail("Transport is nil"); done(); return
                }
                expect(newTransport).toNot(beIdenticalTo(transport))
                expect(transport.protocolMessagesSent.filter { $0.action == .message }).to(haveCount(1))
                expect(transport.protocolMessagesReceived.filter { $0.action == .connected }).to(haveCount(1))
                expect(newTransport.protocolMessagesReceived.filter { $0.action == .connected }).to(haveCount(1))
                expect(transport.protocolMessagesReceived.filter { $0.action == .connected }).to(haveCount(1))
                expect(newTransport.protocolMessagesSent.filter { $0.action == .message }).to(haveCount(1))
                done()
            }
            client.internal.onDisconnected()
        }
    }

    // RTN19b
    func skipped__test__104__Connection__Transport_disconnected_side_effects__should_resend_the_ATTACH_message_if_there_are_any_pending_channels() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not setup"); return
        }

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            transport.ignoreSends = true
            channel.attach { error in
                expect(error).to(beNil())
                guard let newTransport = client.internal.transport as? TestProxyTransport else {
                    fail("Transport is nil"); done(); return
                }
                expect(transport.protocolMessagesReceived.filter { $0.action == .connected }).to(haveCount(1))
                expect(newTransport.protocolMessagesReceived.filter { $0.action == .connected }).to(haveCount(1))
                expect(transport.protocolMessagesSent.filter { $0.action == .attach }).to(haveCount(0))
                expect(transport.protocolMessagesSentIgnored.filter { $0.action == .attach }).to(haveCount(1))
                expect(newTransport.protocolMessagesSent.filter { $0.action == .attach }).to(haveCount(1))
                expect(transport).toNot(beIdenticalTo(newTransport))
                done()
            }
            expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
            transport.ignoreSends = false
            AblyTests.queue.async {
                client.internal.onDisconnected()
            }
        }
    }

    // RTN19b
    func skipped__test__105__Connection__Transport_disconnected_side_effects__should_resent_the_DETACH_message_if_there_are_any_pending_channels() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in done() }
        }

        waitUntil(timeout: testTimeout) { done in
            transport.ignoreSends = true
            channel.detach { error in
                expect(error).to(beNil())
                guard let newTransport = client.internal.transport as? TestProxyTransport else {
                    fail("Transport is nil"); done(); return
                }
                expect(transport.protocolMessagesReceived.filter { $0.action == .connected }).to(haveCount(1))
                expect(newTransport.protocolMessagesReceived.filter { $0.action == .connected }).to(haveCount(1))
                expect(transport.protocolMessagesSent.filter { $0.action == .detach }).to(haveCount(0))
                expect(transport.protocolMessagesSentIgnored.filter { $0.action == .detach }).to(haveCount(1))
                expect(newTransport.protocolMessagesSent.filter { $0.action == .detach }).to(haveCount(1))
                done()
            }
            expect(channel.state).to(equal(ARTRealtimeChannelState.detaching))
            transport.ignoreSends = false
            client.internal.onDisconnected()
        }
    }

    // RTN20

    // RTN20a

    func beforeEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        internetConnectionNotAvailableTestsClient = ARTRealtime(options: options)
        internetConnectionNotAvailableTestsClient.internal.setReachabilityClass(TestReachability.self)
    }

    func afterEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available() {
        internetConnectionNotAvailableTestsClient.dispose()
        internetConnectionNotAvailableTestsClient.close()
    }

    func test__109__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available__when_CONNECTING() {
        beforeEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available()

        waitUntil(timeout: testTimeout) { done in
            internetConnectionNotAvailableTestsClient.connection.on { stateChange in
                switch stateChange.current {
                case .connecting:
                    expect(stateChange.reason).to(beNil())
                    guard let reachability = internetConnectionNotAvailableTestsClient.internal.reachability as? TestReachability else {
                        fail("expected test reachability")
                        done(); return
                    }
                    expect(reachability.host).to(equal(internetConnectionNotAvailableTestsClient.internal.options.realtimeHost))
                    reachability.simulate(false)
                case .disconnected:
                    guard let reason = stateChange.reason else {
                        fail("expected error reason")
                        done(); return
                    }
                    expect(reason.code).to(equal(-1003))
                    done()
                default:
                    break
                }
            }
            internetConnectionNotAvailableTestsClient.connect()
        }

        afterEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available()
    }

    func test__110__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available__when_CONNECTED() {
        beforeEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available()

        waitUntil(timeout: testTimeout) { done in
            internetConnectionNotAvailableTestsClient.connection.on { stateChange in
                switch stateChange.current {
                case .connected:
                    expect(stateChange.reason).to(beNil())
                    guard let reachability = internetConnectionNotAvailableTestsClient.internal.reachability as? TestReachability else {
                        fail("expected test reachability")
                        done(); return
                    }
                    expect(reachability.host).to(equal(internetConnectionNotAvailableTestsClient.internal.options.realtimeHost))
                    reachability.simulate(false)
                case .disconnected:
                    guard let reason = stateChange.reason else {
                        fail("expected error reason")
                        done(); return
                    }
                    expect(reason.code).to(equal(-1003))
                    done()
                default:
                    break
                }
            }
            internetConnectionNotAvailableTestsClient.connect()
        }

        afterEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available()
    }

    // RTN20b
    func test__106__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_attempt_to_connect_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_now_available_when_DISCONNECTED_or_SUSPENDED() {
        var client: ARTRealtime!
        let options = AblyTests.commonAppSetup()
        // Ensure it won't reconnect because of timeouts.
        options.disconnectedRetryTimeout = testTimeout.incremented(by: 10).toTimeInterval()
        options.suspendedRetryTimeout = testTimeout.incremented(by: 10).toTimeInterval()
        options.autoConnect = false
        client = ARTRealtime(options: options)
        client.internal.setReachabilityClass(TestReachability.self)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                switch stateChange.current {
                case .connecting:
                    if stateChange.previous == .disconnected {
                        client.internal.onSuspended()
                    } else if stateChange.previous == .suspended {
                        done()
                    }
                case .connected:
                    client.internal.onDisconnected()
                case .disconnected, .suspended:
                    guard let reachability = client.internal.reachability as? TestReachability else {
                        fail("expected test reachability")
                        done(); return
                    }
                    expect(reachability.host).to(equal(client.internal.options.realtimeHost))
                    reachability.simulate(true)
                default:
                    break
                }
            }
            client.connect()
        }
    }

    // RTN22
    func test__107__Connection__Operating_System_events_for_network_internet_connectivity_changes__Ably_can_request_that_a_connected_client_re_authenticates_by_sending_the_client_an_AUTH_ProtocolMessage() {
        let options = AblyTests.commonAppSetup()
        options.autoConnect = false
        options.useTokenAuth = true
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        client.internal.setTransport(TestProxyTransport.self)
        
        let channelName = uniqueChannelName()
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
            client.connect()
        }

        guard let initialConnectionId = client.connection.id else {
            fail("ConnectionId is nil"); return
        }

        guard let initialToken = client.auth.tokenDetails?.token else {
            fail("Initial token is nil"); return
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.update) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(initialToken).toNot(equal(client.auth.tokenDetails?.token))
                done()
            }

            let authMessage = ARTProtocolMessage()
            authMessage.action = .auth
            client.internal.transport?.receive(authMessage)
        }

        expect(client.connection.id).to(equal(initialConnectionId))
        expect(client.internal.transport).to(beIdenticalTo(transport))

        let authMessages = transport.protocolMessagesSent.filter { $0.action == .auth }
        expect(authMessages).to(haveCount(1))

        guard let authMessage = authMessages.first else {
            fail("Missing AUTH protocol message"); return
        }

        expect(authMessage.auth).toNot(beNil())

        guard (authMessage.auth?.accessToken) != nil else {
            fail("Missing accessToken from AUTH ProtocolMessage auth attribute"); return
        }

        let restOptions = AblyTests.clientOptions(key: options.key!)
        restOptions.channelNamePrefix = options.channelNamePrefix
        let rest = ARTRest(options: restOptions)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            let expectedMessage = ARTMessage(name: "ios", data: "message1")

            channel.subscribe { message in
                expect(message.name).to(equal(expectedMessage.name))
                expect(message.data as? String).to(equal(expectedMessage.data as? String))
                partialDone()
            }

            rest.channels.get(channelName).publish([expectedMessage]) { error in
                expect(error).to(beNil())
                partialDone()
            }
        }

        channel.off()
    }

    // RTN22a
    func test__108__Connection__Operating_System_events_for_network_internet_connectivity_changes__re_authenticate_and_resume_the_connection_when_the_client_is_forcibly_disconnected_following_a_DISCONNECTED_message_containing_an_error_code_greater_than_or_equal_to_40140_and_less_than_40150() {
        let options = AblyTests.commonAppSetup()
        options.token = getTestToken(key: options.key!, ttl: 5.0)
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }
        
        let channelName = uniqueChannelName()
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                expect(error).to(beNil())
                done()
            }
        }

        guard let initialConnectionId = client.connection.id else {
            fail("ConnectionId is nil"); return
        }

        guard let initialToken = client.auth.tokenDetails?.token else {
            fail("Initial token is nil"); return
        }

        channel.once(.detached) { _ in
            fail("Should not detach channels")
        }

        var authorizeMethodCallCount = 0
        let hook = client.auth.internal.testSuite_injectIntoMethod(after: #selector(client.auth.internal._authorize(_:options:callback:))) {
            authorizeMethodCallCount += 1
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                expect(error.code) == ARTErrorCode.tokenExpired.intValue
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                expect(initialToken).toNot(equal(client.auth.tokenDetails?.token))
                done()
            }
        }

        expect(client.connection.id).to(equal(initialConnectionId))
        expect(authorizeMethodCallCount) == 1

        let restOptions = AblyTests.clientOptions(key: options.key!)
        restOptions.channelNamePrefix = options.channelNamePrefix
        let rest = ARTRest(options: restOptions)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            let expectedMessage = ARTMessage(name: "ios", data: "message1")

            channel.subscribe { message in
                expect(message.name).to(equal(expectedMessage.name))
                expect(message.data as? String).to(equal(expectedMessage.data as? String))
                partialDone()
            }

            rest.channels.get(channelName).publish([expectedMessage]) { error in
                expect(error).to(beNil())
                partialDone()
            }
        }

        channel.off()
    }

    // RTN23a
    func test__011__Connection__should_disconnect_the_transport_when_no_activity_exist() {
        let options = AblyTests.commonAppSetup()
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }

        let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
        defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
        ARTDefault.setRealtimeRequestTimeout(0.5)

        var expectedInactivityTimeout: TimeInterval?
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            guard let transport = client.internal.transport as? TestProxyTransport else {
                fail("TestProxyTransport is not set"); partialDone(); return
            }

            var noActivityHasStartedAt: Date?
            transport.setBeforeIncomingMessageModifier { protocolMessage in
                if protocolMessage.action == .connected, let connectionDetails = protocolMessage.connectionDetails {
                    connectionDetails.setMaxIdleInterval(3)
                    expectedInactivityTimeout = connectionDetails.maxIdleInterval + ARTDefault.realtimeRequestTimeout()
                    // Force no activity
                    transport.ignoreWebSocket = true
                    noActivityHasStartedAt = Date()
                    transport.setBeforeIncomingMessageModifier(nil)
                    partialDone()
                }
                return protocolMessage
            }

            client.connection.on(.disconnected) { stateChange in
                let now = Date()

                expect(stateChange.previous) == ARTRealtimeConnectionState.connected

                guard let noActivityHasStartedAt = noActivityHasStartedAt else {
                    fail("No activity date is missing"); partialDone(); return
                }
                guard let expectedInactivityTimeout = expectedInactivityTimeout else {
                    fail("Expected inactivity timeout is missing"); partialDone(); return
                }

                expect(now.timeIntervalSince(noActivityHasStartedAt)).to(beCloseTo(expectedInactivityTimeout, within: 1.0))

                guard let reason = stateChange.reason else {
                    fail("ConnectionStateChange reason is missing"); partialDone(); return
                }
                guard let errorReason = client.connection.errorReason else {
                    fail("Connection error is missing"); partialDone(); return
                }

                expect(reason.message).to(contain("Idle timer expired"))
                expect(errorReason.message).to(contain("Idle timer expired"))

                partialDone()
            }
        }

        expect(expectedInactivityTimeout) == 3.5
        expect(client.internal.maxIdleInterval) == 3.0
    }

    // RTN24
    func test__012__Connection__the_client_may_receive_a_CONNECTED_ProtocolMessage_from_Ably_at_any_point_and_should_emit_an_UPDATE_event() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let authMessage = ARTProtocolMessage()
            authMessage.action = ARTProtocolMessageAction.connected
            authMessage.error = ARTErrorInfo.create(withCode: 1234, message: "fabricated error")

            let listener = client.connection.once(.connected) { _ in
                fail("shouldn't emit CONNECTED")
            }
            client.connection.once(.update) { stateChange in
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                expect(stateChange.current).to(equal(ARTRealtimeConnectionState.connected))
                expect(stateChange.current).to(equal(stateChange.previous))
                expect(stateChange.reason).to(beIdenticalTo(authMessage.error))
                delay(0.5) { // Give some time for the other listener to be triggered.
                    client.connection.off(listener)
                    done()
                }
            }

            client.internal.transport?.receive(authMessage)
        }
    }

    // RTN24
    func test__013__Connection__should_set_the_Connection_reason_attribute_based_on_the_Error_member_of_the_CONNECTED_ProtocolMessage() {
        let options = AblyTests.commonAppSetup()
        options.useTokenAuth = true
        let client = AblyTests.newRealtime(options)
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
        guard let originalConnectedMessage = transport.protocolMessagesReceived.filter({ $0.action == .connected }).first else {
            fail("First CONNECTED message not received"); return
        }

        client.connection.once(.connected) { _ in
            fail("Should not emit a Connected state")
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.update) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                expect(error.code) == 1234
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                expect(stateChange.current).to(equal(ARTRealtimeConnectionState.connected))
                expect(stateChange.current).to(equal(stateChange.previous))
                done()
            }

            let connectedMessageWithError = originalConnectedMessage
            connectedMessageWithError.error = ARTErrorInfo.create(withCode: 1234, message: "fabricated error")
            client.internal.transport?.receive(connectedMessageWithError)
        }

        expect(client.connection.errorReason).to(beNil())
    }

    // https://github.com/ably/ably-cocoa/issues/454
    func test__014__Connection__should_not_move_to_FAILED_if_received_DISCONNECT_with_an_error() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer {
            client.dispose()
            client.close()
        }

        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

        let protoMsg = ARTProtocolMessage()
        protoMsg.action = .disconnect
        protoMsg.error = ARTErrorInfo.create(withCode: 123, message: "test error")
        client.internal.transport?.receive(protoMsg)

        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.disconnected))
        expect(client.connection.errorReason).to(equal(protoMsg.error))
    }

    // https://github.com/ably/wiki/issues/22
    func skipped__test__111__Connection__with_fixture_messages__should_encode_and_decode_fixture_messages_as_expected() {
        let options = AblyTests.commonAppSetup()
        options.useBinaryProtocol = false
        let client = AblyTests.newRealtime(options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(uniqueChannelName())
        channel.attach()

        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
        if channel.state != .attached {
            return
        }

        for (_, fixtureMessage) in fixtures["messages"] {
            var receivedMessage: ARTMessage?

            waitUntil(timeout: testTimeout) { done in
                channel.subscribe { message in
                    channel.unsubscribe()
                    receivedMessage = message
                    done()
                }

                let request = NSMutableURLRequest(url: URL(string: "/channels/\(channel.name)/messages")!)
                request.httpMethod = "POST"
                request.httpBody = try! fixtureMessage.rawData()
                request.allHTTPHeaderFields = [
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                ]
                client.internal.rest.execute(request, withAuthOption: .on, completion: { _, _, err in
                    if let err = err {
                        fail("\(err)")
                    }
                })
            }

            guard let message = receivedMessage else {
                continue
            }

            expectDataToMatch(message, fixtureMessage)

            waitUntil(timeout: testTimeout) { done in
                channel.publish([message]) { err in
                    if let err = err {
                        fail("\(err)")
                        done()
                        return
                    }

                    let request = NSMutableURLRequest(url: URL(string: "/channels/\(channel.name)/messages?limit=1")!)
                    request.httpMethod = "GET"
                    request.allHTTPHeaderFields = ["Accept": "application/json"]
                    client.internal.rest.execute(request, withAuthOption: .on, completion: { _, data, err in
                        if let err = err {
                            fail("\(err)")
                            done()
                            return
                        }
                        let persistedMessage = try! JSON(data: data!).array!.first!
                        expect(persistedMessage["data"]).to(equal(fixtureMessage["data"]))
                        expect(persistedMessage["encoding"]).to(equal(fixtureMessage["encoding"]))
                        done()
                    })
                }
            }
        }
    }

    func skipped__test__112__Connection__with_fixture_messages__should_send_messages_through_raw_JSON_POST_and_retrieve_equal_messages_through_MsgPack_and_JSON() {
        setupDependencies()
        let restPublishClient = ARTRest(options: jsonOptions)
        let realtimeSubscribeClientMsgPack = AblyTests.newRealtime(msgpackOptions)
        let realtimeSubscribeClientJSON = AblyTests.newRealtime(jsonOptions)
        defer {
            realtimeSubscribeClientMsgPack.close()
            realtimeSubscribeClientJSON.close()
        }

        let realtimeSubscribeChannelMsgPack = realtimeSubscribeClientMsgPack.channels.get(uniqueChannelName())
        let realtimeSubscribeChannelJSON = realtimeSubscribeClientJSON.channels.get(realtimeSubscribeChannelMsgPack.name)

        waitUntil(timeout: testTimeout) { done in
            let partlyDone = AblyTests.splitDone(2, done: done)
            realtimeSubscribeChannelMsgPack.attach { _ in partlyDone() }
            realtimeSubscribeChannelJSON.attach { _ in partlyDone() }
        }

        for (_, fixtureMessage) in fixtures["messages"] {
            waitUntil(timeout: testTimeout) { done in
                let partlyDone = AblyTests.splitDone(2, done: done)

                realtimeSubscribeChannelMsgPack.subscribe { message in
                    realtimeSubscribeChannelMsgPack.unsubscribe()
                    expectDataToMatch(message, fixtureMessage)
                    partlyDone()
                }

                realtimeSubscribeChannelJSON.subscribe { message in
                    realtimeSubscribeChannelJSON.unsubscribe()
                    expectDataToMatch(message, fixtureMessage)
                    partlyDone()
                }

                let request = NSMutableURLRequest(url: URL(string: "/channels/\(realtimeSubscribeChannelMsgPack.name)/messages")!)
                request.httpMethod = "POST"
                request.httpBody = try! fixtureMessage.rawData()
                request.allHTTPHeaderFields = [
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                ]
                restPublishClient.internal.execute(request, withAuthOption: .on, completion: { _, _, err in
                    if let err = err {
                        fail("\(err)")
                    }
                })
            }
        }
    }

    func skipped__test__113__Connection__with_fixture_messages__should_send_messages_through_MsgPack_and_JSON_and_retrieve_equal_messages_through_raw_JSON_GET() {
        setupDependencies()
        let restPublishClientMsgPack = ARTRest(options: msgpackOptions)
        let restPublishClientJSON = ARTRest(options: jsonOptions)
        let restRetrieveClient = ARTRest(options: jsonOptions)

        let restPublishChannelMsgPack = restPublishClientMsgPack.channels.get(uniqueChannelName())
        let restPublishChannelJSON = restPublishClientJSON.channels.get(restPublishChannelMsgPack.name)

        for (_, fixtureMessage) in fixtures["messages"] {
            var data: AnyObject
            if fixtureMessage["expectedType"] == "binary" {
                data = fixtureMessage["expectedHexValue"].string!.dataFromHexadecimalString()! as AnyObject
            } else {
                data = fixtureMessage["expectedValue"].object as AnyObject
            }

            for restPublishChannel in [restPublishChannelMsgPack, restPublishChannelJSON] {
                waitUntil(timeout: testTimeout) { done in
                    restPublishChannel.publish("event", data: data) { err in
                        if let err = err {
                            fail("\(err)")
                            done()
                            return
                        }
                        done()
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    let request = NSMutableURLRequest(url: URL(string: "/channels/\(restPublishChannel.name)/messages?limit=1")!)
                    request.httpMethod = "GET"
                    request.allHTTPHeaderFields = ["Accept": "application/json"]
                    restRetrieveClient.internal.execute(request, withAuthOption: .on, completion: { _, data, err in
                        if let err = err {
                            fail("\(err)")
                            done()
                            return
                        }
                        let persistedMessage = try! JSON(data: data!).array!.first!
                        expect(persistedMessage["data"]).to(equal(persistedMessage["data"]))
                        expect(persistedMessage["encoding"]).to(equal(fixtureMessage["encoding"]))
                        done()
                    })
                }
            }
        }
    }

    func test__015__Connection__should_abort_reconnection_with_new_token_if_the_server_has_requested_it_to_authorize_and_after_it_the_connection_has_been_closed() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(stateChange.reason).to(beNil())
                done()
            }
        }

        client.auth.internal.options.authCallback = { _, completion in
            getTestTokenDetails(ttl: 0.1) { tokenDetails, error in
                expect(error).to(beNil())
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); return
                }
                // Let the token expire
                delay(0.1) {
                    completion(tokenDetails.token as ARTTokenDetailsCompatible?, nil)
                }
            }
        }

        let authMessage = ARTProtocolMessage()
        authMessage.action = .auth
        client.internal.transport?.receive(authMessage)

        client.close()

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.failed) { _ in
                fail("Should not receive error 40142")
            }
            client.connection.once(.connected) { _ in
                fail("Should not connect")
            }
            client.connection.once(.closed) { _ in
                done()
            }
        }
    }
}
