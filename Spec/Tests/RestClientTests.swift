import Ably
import Nimble
 import XCTest

private var testHTTPExecutor: TestProxyHTTPExecutor!

private func testOptionsGiveBasicAuthFalse(_ caseSetter: (ARTAuthOptions) -> Void) {
    let options = ARTClientOptions()
    caseSetter(options)

    let client = ARTRest(options: options)

    expect(client.auth.internal.options.isBasicAuth()).to(beFalse())
}

private let expectedHostOrder = [4, 3, 0, 2, 1]

private let originalARTFallback_shuffleArray = ARTFallback_shuffleArray

private let _fallbackHosts = ["f.ably-realtime.com", "g.ably-realtime.com", "h.ably-realtime.com", "i.ably-realtime.com", "j.ably-realtime.com"]

private func testUsesAlternativeHost(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ARTClientOptions(key: "xxxx:xxxx")
    let client = ARTRest(options: options)
    let mockHTTP = MockHTTP(logger: options.logHandler)
    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
    client.internal.httpExecutor = testHTTPExecutor
    mockHTTP.setNetworkState(network: caseTest, resetAfter: 1)
    let channel = client.channels.get(channelName)

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    expect(testHTTPExecutor.requests).to(haveCount(2))
    if testHTTPExecutor.requests.count != 2 {
        return
    }
    expect(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//rest.ably.io")).to(beTrue())
    expect(NSRegularExpression.match(testHTTPExecutor.requests[1].url!.absoluteString, pattern: "//[a-e].ably-realtime.com")).to(beTrue())
}

private func testStoresSuccessfulFallbackHostAsDefaultHost(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ARTClientOptions(key: "xxxx:xxxx")
    let client = ARTRest(options: options)
    let mockHTTP = MockHTTP(logger: options.logHandler)
    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
    client.internal.httpExecutor = testHTTPExecutor
    mockHTTP.setNetworkState(network: caseTest, resetAfter: 1)
    let channel = client.channels.get(channelName)

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    expect(testHTTPExecutor.requests).to(haveCount(2))
    expect(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.host, pattern: "rest.ably.io")).to(beTrue())
    expect(NSRegularExpression.match(testHTTPExecutor.requests[1].url!.host, pattern: "[a-e].ably-realtime.com")).to(beTrue())

    // #1 Store fallback used to request
    let usedFallbackURL = testHTTPExecutor.requests[1].url!

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    let reusedURL = testHTTPExecutor.requests[2].url!

    // Reuse host has to be equal previous (stored #1) fallback host
    expect(testHTTPExecutor.requests).to(haveCount(3))
    expect(usedFallbackURL.host).to(equal(reusedURL.host))
}

private func testRestoresDefaultPrimaryHostAfterTimeoutExpires(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ARTClientOptions(key: "xxxx:xxxx")
    options.logLevel = .debug
    options.fallbackRetryTimeout = 1
    let client = ARTRest(options: options)
    let mockHTTP = MockHTTP(logger: options.logHandler)
    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
    client.internal.httpExecutor = testHTTPExecutor
    mockHTTP.setNetworkState(network: caseTest, resetAfter: 1)
    let channel = client.channels.get(channelName)

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    waitUntil(timeout: testTimeout) { done in
        delay(1.1) {
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }
    }

    expect(testHTTPExecutor.requests).to(haveCount(3))
    expect(testHTTPExecutor.requests[2].url!.host).to(equal("rest.ably.io"))
}

private func testUsesAnotherFallbackHost(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ARTClientOptions(key: "xxxx:xxxx")
    options.fallbackRetryTimeout = 10
    options.logLevel = .debug
    let client = ARTRest(options: options)
    let mockHTTP = MockHTTP(logger: options.logHandler)
    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
    client.internal.httpExecutor = testHTTPExecutor
    mockHTTP.setNetworkState(network: caseTest, resetAfter: 2)
    let channel = client.channels.get(channelName)

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    expect(testHTTPExecutor.requests).to(haveCount(3))
    expect(NSRegularExpression.match(testHTTPExecutor.requests[1].url!.host, pattern: "[a-e].ably-realtime.com")).to(beTrue())
    expect(NSRegularExpression.match(testHTTPExecutor.requests[2].url!.host, pattern: "[a-e].ably-realtime.com")).to(beTrue())
    expect(testHTTPExecutor.requests[1].url!.host).toNot(equal(testHTTPExecutor.requests[2].url!.host))
}

class RestClientTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = testHTTPExecutor
        _ = expectedHostOrder
        _ = originalARTFallback_shuffleArray
        _ = _fallbackHosts

        return super.defaultTestSuite
    }

    // G4
    func test__001__RestClient__All_REST_requests_should_include_the_current_API_version() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                let version = testHTTPExecutor.requests.first!.allHTTPHeaderFields?["X-Ably-Version"]

                // This test should not directly validate version against ARTDefault.version(), as
                // ultimately the version header has been derived from that value.
                expect(version).to(equal("1.2"))

                done()
            }
        }
    }

    // RSC1

    func test__015__RestClient__initializer__should_accept_an_API_key() {
        let options = AblyTests.commonAppSetup()

        let client = ARTRest(key: options.key!)
        client.internal.prioritizedHost = options.restHost

        let publishTask = publishTestMessage(client, channelName: uniqueChannelName())

        expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
    }

    func test__016__RestClient__initializer__should_throw_when_provided_an_invalid_key() {
        expect { ARTRest(key: "invalid_key") }.to(raiseException())
    }

    func test__017__RestClient__initializer__should_result_in_error_status_when_provided_a_bad_key() {
        let client = ARTRest(key: "fake:key")

        let publishTask = publishTestMessage(client, channelName: uniqueChannelName(), failOnError: false)

        expect(publishTask.error?.code).toEventually(equal(ARTErrorCode.invalidCredential.intValue), timeout: testTimeout)
    }

    func test__018__RestClient__initializer__should_accept_a_token() {
        ARTClientOptions.setDefaultEnvironment(getEnvironment())
        defer { ARTClientOptions.setDefaultEnvironment(nil) }

        let client = ARTRest(token: getTestToken())
        let publishTask = publishTestMessage(client, channelName: uniqueChannelName())
        expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
    }

    func test__019__RestClient__initializer__should_accept_an_options_object() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRest(options: options)

        let publishTask = publishTestMessage(client, channelName: uniqueChannelName())

        expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
    }

    func test__020__RestClient__initializer__should_accept_an_options_object_with_token_authentication() {
        let options = AblyTests.clientOptions(requestToken: true)
        let client = ARTRest(options: options)

        let publishTask = publishTestMessage(client, channelName: uniqueChannelName())

        expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
    }

    func test__021__RestClient__initializer__should_result_in_error_status_when_provided_a_bad_token() {
        let options = AblyTests.clientOptions()
        options.token = "invalid_token"
        let client = ARTRest(options: options)

        let publishTask = publishTestMessage(client, channelName: uniqueChannelName(), failOnError: false)

        expect(publishTask.error?.code).toEventually(equal(ARTErrorCode.invalidCredential.intValue), timeout: testTimeout)
    }

    // RSC2
    func test__022__RestClient__logging__should_output_to_the_system_log_and_the_log_level_should_be_Warn() {
        ARTClientOptions.setDefaultEnvironment(getEnvironment())
        defer {
            ARTClientOptions.setDefaultEnvironment(nil)
        }

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.logHandler = ARTLog(capturingOutput: true)
        let client = ARTRest(options: options)

        client.internal.logger.log("This is a warning", with: .warn)

        expect(client.internal.logger.logLevel).to(equal(ARTLogLevel.warn))
        guard let line = options.logHandler.captured.last else {
            fail("didn't log line.")
            return
        }
        expect(line.level).to(equal(ARTLogLevel.warn))
        expect(line.toString()).to(equal("WARN: This is a warning"))
    }

    // RSC3
    func test__023__RestClient__logging__should_have_a_mutable_log_level() {
        let options = AblyTests.commonAppSetup()
        options.logHandler = ARTLog(capturingOutput: true)
        let client = ARTRest(options: options)
        client.internal.logger.logLevel = .error

        let logTime = NSDate()
        client.internal.logger.log("This is a warning", with: .warn)

        let logs = options.logHandler.captured.filter { !$0.date.isBefore(logTime as Date) }
        expect(logs).to(beEmpty())
    }

    // RSC4
    func test__024__RestClient__logging__should_accept_a_custom_logger() {
        enum Log {
            static var interceptedLog: (String, ARTLogLevel) = ("", .none)
        }
        class MyLogger: ARTLog {
            override func log(_ message: String, with level: ARTLogLevel) {
                Log.interceptedLog = (message, level)
            }
        }

        let options = AblyTests.commonAppSetup()
        let customLogger = MyLogger()
        options.logHandler = customLogger
        options.logLevel = .verbose
        let client = ARTRest(options: options)

        client.internal.logger.log("This is a warning", with: .warn)

        expect(Log.interceptedLog.0).to(equal("This is a warning"))
        expect(Log.interceptedLog.1).to(equal(ARTLogLevel.warn))

        expect(client.internal.logger.logLevel).to(equal(customLogger.logLevel))
    }

    // RSC11

    // RSC11a
    func test__025__RestClient__endpoint__should_accept_a_custom_host_and_send_requests_to_the_specified_host() {
        let options = ARTClientOptions(key: "fake:key")
        options.restHost = "fake.ably.io"
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.host).toEventually(equal("fake.ably.io"), timeout: testTimeout)
    }

    func test__026__RestClient__endpoint__should_ignore_an_environment_when_restHost_is_customized() {
        let options = ARTClientOptions(key: "fake:key")
        options.environment = "test"
        options.restHost = "fake.ably.io"
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.host).toEventually(equal("fake.ably.io"), timeout: testTimeout)
    }

    // RSC11b
    func test__027__RestClient__endpoint__should_accept_an_environment_when_restHost_is_left_unchanged() {
        let options = ARTClientOptions(key: "fake:key")
        options.environment = "myEnvironment"
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.host).toEventually(equal("myEnvironment-rest.ably.io"), timeout: testTimeout)
    }

    func test__028__RestClient__endpoint__should_default_to_https___rest_ably_io() {
        let options = ARTClientOptions(key: "fake:key")
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.absoluteString).toEventually(beginWith("https://rest.ably.io"), timeout: testTimeout)
    }

    func test__029__RestClient__endpoint__should_connect_over_plain_http____when_tls_is_off() {
        let options = AblyTests.clientOptions(requestToken: true)
        options.tls = false
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.scheme).toEventually(equal("http"), timeout: testTimeout)
    }

    // RSC11b
    func test__030__RestClient__endpoint__should_not_prepend_the_environment_if_environment_is_configured_as__production_() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.environment = "production"
        let client = ARTRest(options: options)
        expect(client.internal.options.restHost).to(equal(ARTDefault.restHost()))
        expect(client.internal.options.realtimeHost).to(equal(ARTDefault.realtimeHost()))
    }

    // RSC13

    func test__031__RestClient__should_use_the_the_connection_and_request_timeouts_specified__timeout_for_any_single_HTTP_request_and_response() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.restHost = "10.255.255.1" // non-routable IP address
        expect(options.httpRequestTimeout).to(equal(10.0)) // Seconds
        options.httpRequestTimeout = 1.0
        let client = ARTRest(options: options)
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            let start = NSDate()
            channel.publish(nil, data: "message") { error in
                let end = NSDate()
                expect(end.timeIntervalSince(start as Date)).to(beCloseTo(options.httpRequestTimeout, within: 0.5))
                expect(error).toNot(beNil())
                if let error = error {
                    expect(error.code).to(satisfyAnyOf(equal(-1001 /* Timed Out */ ), equal(-1004 /* Cannot Connect To Host */ )))
                }
                done()
            }
        }
    }

    func test__032__RestClient__should_use_the_the_connection_and_request_timeouts_specified__max_number_of_fallback_hosts() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        expect(options.httpMaxRetryCount).to(equal(3))
        options.httpMaxRetryCount = 1
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)

        var totalRetry: UInt = 0
        testHTTPExecutor.setListenerAfterRequest { request in
            if NSRegularExpression.match(request.url!.absoluteString, pattern: "//[a-e].ably-realtime.com") {
                totalRetry += 1
            }
        }

        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }
        expect(totalRetry).to(equal(options.httpMaxRetryCount))
    }

    func test__033__RestClient__should_use_the_the_connection_and_request_timeouts_specified__max_elapsed_time_in_which_fallback_host_retries_for_HTTP_requests_will_be_attempted() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        expect(options.httpMaxRetryDuration).to(equal(15.0)) // Seconds
        options.httpMaxRetryDuration = 1.0
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .requestTimeout(timeout: 0.1))
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            let start = Date()
            channel.publish(nil, data: "nil") { _ in
                let end = Date()
                expect(end.timeIntervalSince(start)).to(beCloseTo(options.httpMaxRetryDuration, within: 0.9))
                done()
            }
        }
    }

    // RSC5
    func test__002__RestClient__should_provide_access_to_the_AuthOptions_object_passed_in_ClientOptions() {
        let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
        let client = ARTRest(options: options)

        let authOptions = client.auth.internal.options

        expect(authOptions == options).to(beTrue())
    }

    // RSC12
    func test__003__RestClient__REST_endpoint_host_should_be_configurable_in_the_Client_constructor_with_the_option_restHost() throws {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        expect(options.restHost).to(equal("rest.ably.io"))
        options.restHost = "rest.ably.test"
        expect(options.restHost).to(equal("rest.ably.test"))
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        waitUntil(timeout: testTimeout) { done in
            client.channels.get(uniqueChannelName()).publish(nil, data: "message") { error in
                expect(error).toNot(beNil())
                done()
            }
        }
        
        let url = try XCTUnwrap(testHTTPExecutor.requests.first?.url, "No request url found")

        expect(url.absoluteString).to(contain("//rest.ably.test"))
    }

    // RSC16

    func test__034__RestClient__time__should_return_server_time() {
        let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
        let client = ARTRest(options: options)

        var time: NSDate?

        client.time { date, _ in
            time = date as NSDate? as NSDate?
        }

        expect(time?.timeIntervalSince1970).toEventually(beCloseTo(NSDate().timeIntervalSince1970, within: 60), timeout: testTimeout)
    }

    // RSC7, RSC18
    func test__004__RestClient__should_send_requests_over_http_and_https() throws {
        let options = AblyTests.commonAppSetup()

        let clientHttps = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        clientHttps.internal.httpExecutor = testHTTPExecutor

        let channelName = uniqueChannelName()
        
        waitUntil(timeout: testTimeout) { done in
            publishTestMessage(clientHttps, channelName: channelName) { _ in
                done()
            }
        }

        let requestUrlA = try XCTUnwrap(testHTTPExecutor.requests.first?.url, "No request url found")

        expect(requestUrlA.scheme).to(equal("https"))

        options.clientId = "client_http"
        options.useTokenAuth = true
        options.tls = false
        let clientHttp = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        clientHttp.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            publishTestMessage(clientHttp, channelName: channelName) { _ in
                done()
            }
        }

        let requestUrlB = try XCTUnwrap(testHTTPExecutor.requests.last?.url, "No request url found")
        expect(requestUrlB.scheme).to(equal("http"))
    }

    // RSC9
    func test__005__RestClient__should_use_Auth_to_manage_authentication() {
        let options = AblyTests.clientOptions()
        guard let testTokenDetails = getTestTokenDetails() else {
            fail("No test token details"); return
        }
        options.tokenDetails = testTokenDetails
        options.authCallback = { _, completion in
            completion(testTokenDetails, nil)
        }

        let client = ARTRest(options: options)
        expect(client.auth).to(beAnInstanceOf(ARTAuth.self))

        waitUntil(timeout: testTimeout) { done in
            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                if let e = error {
                    XCTFail(e.localizedDescription)
                    done()
                    return
                }
                guard let tokenDetails = tokenDetails else {
                    XCTFail("expected tokenDetails to not be nil when error is nil")
                    done()
                    return
                }
                expect(tokenDetails.token).to(equal(testTokenDetails.token))
                done()
            }
        }
    }

    // RSC10
    func test__006__RestClient__should_request_another_token_after_current_one_is_no_longer_valid() {
        let options = AblyTests.commonAppSetup()
        options.token = getTestToken(ttl: 0.5)
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        let auth = client.auth

        waitUntil(timeout: testTimeout) { done in
            delay(1.0) {
                client.channels.get(uniqueChannelName()).history { result, error in
                    expect(error).to(beNil())
                    expect(result).toNot(beNil())

                    guard let headerErrorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                        fail("X-Ably-Errorcode not found"); done()
                        return
                    }
                    expect(Int(headerErrorCode)).to(equal(ARTErrorCode.tokenExpired.intValue))

                    // Different token
                    expect(auth.tokenDetails!.token).toNot(equal(options.token))
                    done()
                }
            }
        }
    }

    // RSC10
    func test__007__RestClient__should_result_in_an_error_when_user_does_not_have_sufficient_permissions() {
        let options = AblyTests.clientOptions()
        options.token = getTestToken(capability: "{ \"main\":[\"subscribe\"] }")
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            client.channels.get(uniqueChannelName()).history { result, error in
                guard let errorCode = error?.code else {
                    fail("Error is empty"); done()
                    return
                }
                expect(errorCode).to(equal(ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue))
                expect(result).to(beNil())

                guard let headerErrorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                    fail("X-Ably-Errorcode not found"); done()
                    return
                }
                expect(Int(headerErrorCode)).to(equal(ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue))
                done()
            }
        }
    }

    // RSC14

    // RSC14a
    func test__035__RestClient__Authentication__should_support_basic_authentication_when_an_API_key_is_provided_with_the_key_option() {
        let options = AblyTests.commonAppSetup()
        guard let components = options.key?.components(separatedBy: ":"), let keyName = components.first, let keySecret = components.last else {
            fail("Invalid API key: \(options.key ?? "nil")"); return
        }
        ARTClientOptions.setDefaultEnvironment(getEnvironment())
        defer {
            ARTClientOptions.setDefaultEnvironment(nil)
        }
        let rest = ARTRest(key: "\(keyName):\(keySecret)")
        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(uniqueChannelName()).publish(nil, data: "testing") { error in
                expect(error).to(beNil())
                done()
            }
        }
    }

    // RSC14b

    func test__038__RestClient__Authentication__basic_authentication_flag__should_be_true_when_initialized_with_a_key() {
        let client = ARTRest(key: "key:secret")
        expect(client.auth.internal.options.isBasicAuth()).to(beTrue())
    }

    func test__039__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__useTokenAuth_is_set() {
        testOptionsGiveBasicAuthFalse { $0.useTokenAuth = true; $0.key = "fake:key" }
    }

    func test__040__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__authUrl_is_set() {
        testOptionsGiveBasicAuthFalse { $0.authUrl = URL(string: "http://test.com") }
    }

    func test__041__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__authCallback_is_set() {
        testOptionsGiveBasicAuthFalse { $0.authCallback = { _, _ in } }
    }

    func test__042__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__tokenDetails_is_set() {
        testOptionsGiveBasicAuthFalse { $0.tokenDetails = ARTTokenDetails(token: "token") }
    }

    func test__043__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__token_is_set() {
        testOptionsGiveBasicAuthFalse { $0.token = "token" }
    }

    func test__044__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__key_is_set() {
        testOptionsGiveBasicAuthFalse { $0.tokenDetails = ARTTokenDetails(token: "token"); $0.key = "fake:key" }
    }

    // RSC14c
    func test__036__RestClient__Authentication__should_error_when_expired_token_and_no_means_to_renew() {
        let client = ARTRest(options: AblyTests.commonAppSetup())
        let auth = client.auth

        let tokenParams = ARTTokenParams()
        tokenParams.ttl = 3.0 // Seconds

        guard let options: ARTClientOptions = (AblyTests.waitFor(timeout: testTimeout) { value in
            auth.requestToken(tokenParams, with: nil) { tokenDetails, error in
                if let e = error {
                    XCTFail(e.localizedDescription)
                    value(nil)
                    return
                }

                guard let currentTokenDetails = tokenDetails else {
                    XCTFail("expected tokenDetails not to be nil when error is nil")
                    value(nil)
                    return
                }

                let options = AblyTests.clientOptions()
                options.key = client.internal.options.key

                // Expired token
                options.tokenDetails = ARTTokenDetails(
                    token: currentTokenDetails.token,
                    expires: currentTokenDetails.expires!.addingTimeInterval(testTimeout.toTimeInterval()),
                    issued: currentTokenDetails.issued,
                    capability: currentTokenDetails.capability,
                    clientId: currentTokenDetails.clientId
                )

                options.authUrl = URL(string: "http://test-auth.ably.io")
                value(options)
            }
        }) else {
            return
        }

        let rest = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        rest.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            // Delay for token expiration
            delay(TimeInterval(truncating: tokenParams.ttl!)) {
                // [40140, 40150) - token expired and will not recover because authUrl is invalid
                publishTestMessage(rest, channelName: uniqueChannelName()) { error in
                    guard let errorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                        fail("expected X-Ably-Errorcode header in request")
                        return
                    }
                    expect(Int(errorCode)).to(beGreaterThanOrEqualTo(ARTErrorCode.tokenErrorUnspecified.intValue))
                    expect(Int(errorCode)).to(beLessThan(ARTErrorCode.connectionLimitsExceeded.intValue))
                    expect(error).toNot(beNil())
                    done()
                }
            }
        }
    }

    // RSC14d
    func test__037__RestClient__Authentication__should_renew_the_token_when_it_has_expired() {
        let client = ARTRest(options: AblyTests.commonAppSetup())
        let auth = client.auth

        let tokenParams = ARTTokenParams()
        tokenParams.ttl = 3.0 // Seconds

        waitUntil(timeout: testTimeout) { done in
            auth.requestToken(tokenParams, with: nil) { tokenDetails, error in
                if let e = error {
                    XCTFail(e.localizedDescription)
                    done()
                    return
                }

                guard let currentTokenDetails = tokenDetails else {
                    XCTFail("expected tokenDetails not to be nil when error is nil")
                    done()
                    return
                }

                let options = AblyTests.clientOptions()
                options.key = client.internal.options.key

                // Expired token
                options.tokenDetails = ARTTokenDetails(
                    token: currentTokenDetails.token,
                    expires: currentTokenDetails.expires!.addingTimeInterval(testTimeout.toTimeInterval()),
                    issued: currentTokenDetails.issued,
                    capability: currentTokenDetails.capability,
                    clientId: currentTokenDetails.clientId
                )

                let rest = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                rest.internal.httpExecutor = testHTTPExecutor

                // Delay for token expiration
                delay(TimeInterval(truncating: tokenParams.ttl!)) {
                    // [40140, 40150) - token expired and will not recover because authUrl is invalid
                    publishTestMessage(rest, channelName: uniqueChannelName()) { error in
                        guard let errorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                            fail("expected X-Ably-Errorcode header in request")
                            return
                        }
                        expect(Int(errorCode)).to(beGreaterThanOrEqualTo(ARTErrorCode.tokenErrorUnspecified.intValue))
                        expect(Int(errorCode)).to(beLessThan(ARTErrorCode.connectionLimitsExceeded.intValue))
                        expect(error).to(beNil())
                        expect(rest.auth.tokenDetails!.token).toNot(equal(currentTokenDetails.token))
                        done()
                    }
                }
            }
        }
    }

    // RSC15

    // TO3k7

    @available(*, deprecated, message: "This test is marked as deprecated so as to not trigger a compiler warning for using the -ARTClientOptions.fallbackHostsUseDefault property. Remove this deprecation when removing the property.")
    func test__051__RestClient__Host_Fallback__fallbackHostsUseDefault_option__allows_the_default_fallback_hosts_to_be_used_when__environment__is_not_production() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.environment = "not-production"
        options.fallbackHostsUseDefault = true

        let client = ARTRest(options: options)
        expect(client.internal.options.fallbackHostsUseDefault).to(beTrue())
        // Not production
        expect(client.internal.options.environment).toNot(beNil())
        expect(client.internal.options.environment).toNot(equal("production"))

        let hosts = ARTFallbackHosts.hosts(from: client.internal.options)
        let fallback = ARTFallback(fallbackHosts: hosts)
        expect(fallback.hosts).to(haveCount(ARTDefault.fallbackHosts().count))

        ARTDefault.fallbackHosts().forEach {
            expect(fallback.hosts).to(contain($0))
        }
    }

    @available(*, deprecated, message: "This test is marked as deprecated so as to not trigger a compiler warning for using the -ARTClientOptions.fallbackHostsUseDefault property. Remove this deprecation when removing the property.")
    func test__052__RestClient__Host_Fallback__fallbackHostsUseDefault_option__allows_the_default_fallback_hosts_to_be_used_when_a_custom_Realtime_or_REST_host_endpoint_is_being_used() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.restHost = "fake1.ably.io"
        options.realtimeHost = "fake2.ably.io"
        options.fallbackHostsUseDefault = true

        let client = ARTRest(options: options)
        expect(client.internal.options.fallbackHostsUseDefault).to(beTrue())
        // Custom
        expect(client.internal.options.restHost).toNot(equal(ARTDefault.restHost()))
        expect(client.internal.options.realtimeHost).toNot(equal(ARTDefault.realtimeHost()))

        let hosts = ARTFallbackHosts.hosts(from: client.internal.options)
        let fallback = ARTFallback(fallbackHosts: hosts)
        expect(fallback.hosts).to(haveCount(ARTDefault.fallbackHosts().count))

        ARTDefault.fallbackHosts().forEach {
            expect(fallback.hosts).to(contain($0))
        }
    }

    @available(*, deprecated, message: "This test is marked as deprecated so as to not trigger a compiler warning for using the -ARTClientOptions.fallbackHostsUseDefault property. Remove this deprecation when removing the property.")
    func test__053__RestClient__Host_Fallback__fallbackHostsUseDefault_option__should_be_inactive_by_default() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        expect(options.fallbackHostsUseDefault).to(beFalse())
    }

    @available(*, deprecated, message: "This test is marked as deprecated so as to not trigger a compiler warning for using the -ARTClientOptions.fallbackHostsUseDefault property. Remove this deprecation when removing the property.")
    func test__054__RestClient__Host_Fallback__fallbackHostsUseDefault_option__should_never_accept_to_configure__fallbackHost__and_set__fallbackHostsUseDefault__to__true_() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        expect(options.fallbackHosts).to(beNil())
        expect(options.fallbackHostsUseDefault).to(beFalse())

        expect { options.fallbackHosts = [] }.toNot(raiseException())

        expect { options.fallbackHostsUseDefault = true }.to(raiseException(named: ARTFallbackIncompatibleOptionsException))

        options.fallbackHosts = nil

        expect { options.fallbackHostsUseDefault = true }.toNot(raiseException())

        expect { options.fallbackHosts = ["fake.ably.io"] }.to(raiseException(named: ARTFallbackIncompatibleOptionsException))
    }

    // RSC15b

    // RSC15b1
    func test__055__RestClient__Host_Fallback__Fallback_behavior__should_be_applied_when_restHost__port_and_tlsPort_has_not_been_set_to_an_explicit_value() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 2)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error).to(beNil())
                done()
            }
        }

        let requests = testHTTPExecutor.requests
        expect(requests).to(haveCount(3))
        let capturedURLs = requests.map { $0.url!.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(2), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
    }

    // RSC15b1
    func test__056__RestClient__Host_Fallback__Fallback_behavior__should_NOT_be_applied_when_ClientOptions_restHost_has_been_set() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.restHost = "fake.ably.io"
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        let requests = testHTTPExecutor.requests
        expect(requests).to(haveCount(1))
        let capturedURLs = requests.map { $0.url!.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(0), pattern: "//fake.ably.io")).to(beTrue())
    }

    // RSC15b1
    func test__057__RestClient__Host_Fallback__Fallback_behavior__should_NOT_be_applied_when_ClientOptions_port_has_been_set() {
        let options = ARTClientOptions(token: "xxxx")
        options.tls = false
        options.port = 999
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        let requests = testHTTPExecutor.requests
        expect(requests).to(haveCount(1))
        let capturedURLs = requests.map { $0.url!.absoluteString }
        expect(capturedURLs.at(0)).to(beginWith("http://rest.ably.io:999"))
    }

    // RSC15b1
    func test__058__RestClient__Host_Fallback__Fallback_behavior__should_NOT_be_applied_when_ClientOptions_tlsPort_has_been_set() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.tlsPort = 999
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        let requests = testHTTPExecutor.requests
        expect(requests).to(haveCount(1))
        let capturedURLs = requests.map { $0.url!.absoluteString }
        expect(capturedURLs.at(0)).to(beginWith("https://rest.ably.io:999"))
    }

    // RSC15b2
    func test__059__RestClient__Host_Fallback__Fallback_behavior__should_be_applied_when_ClientOptions_fallbackHosts_is_provided() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.fallbackHosts = ["a.cocoa.ably", "b.cocoa.ably"]
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(3))
        let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-b].cocoa.ably")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(2), pattern: "//[a-b].cocoa.ably")).to(beTrue())
    }

    // RSC15b3, RSC15g4
    @available(*, deprecated, message: "This test is marked as deprecated so as to not trigger a compiler warning for using the -ARTClientOptions.fallbackHostsUseDefault property. Remove this deprecation when removing the property.")
    func test__060__RestClient__Host_Fallback__Fallback_behavior__should_be_applied_when_ClientOptions_fallbackHosts_is_not_provided_and_deprecated_fallbackHostsUseDefault_is_on() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.fallbackHostsUseDefault = true
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 2)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error).to(beNil())
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(3))
        let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(2), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
    }

    // RSC15k
    func test__045__RestClient__Host_Fallback__failing_HTTP_requests_with_custom_endpoint_should_result_in_an_error_immediately() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.restHost = "fake.ably.io"
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }
        expect(testHTTPExecutor.requests).to(haveCount(1))
    }

    // RSC15g

    // RSC15g1
    func test__061__RestClient__Host_Fallback__fallback_hosts_list_and_priorities__should_use_ClientOptions_fallbackHosts_when_list_is_provided() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.fallbackHosts = ["f.ably-realtime.com"]
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(2))
        let capturedURLs = testHTTPExecutor.requests.compactMap { $0.url?.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//f.ably-realtime.com")).to(beTrue())
    }

    // RSC15g2
    func test__062__RestClient__Host_Fallback__fallback_hosts_list_and_priorities__should_use_environment_fallback_hosts_when_ClientOptions_environment_is_set_to_a_value_other_than__production__and_ClientOptions_fallbackHosts_is_not_set() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.environment = "test"
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 2)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error).to(beNil())
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(3))
        let capturedURLs = testHTTPExecutor.requests.compactMap { $0.url?.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(0), pattern: "//test-rest.ably.io")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//test-[a-e]-fallback.ably-realtime.com")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//test-[a-e]-fallback.ably-realtime.com")).to(beTrue())
    }

    // RSC15g2
    func test__063__RestClient__Host_Fallback__fallback_hosts_list_and_priorities__should_NOT_use_environment_fallback_hosts_when_ClientOptions_environment_is_set_to__production_() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.environment = "production"
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(4))
        let capturedURLs = testHTTPExecutor.requests.compactMap { $0.url?.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(2), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(3), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
    }

    // RSC15g3
    func test__064__RestClient__Host_Fallback__fallback_hosts_list_and_priorities__should_use_default_fallback_hosts_when_both_ClientOptions_fallbackHosts_and_ClientOptions_environment_are_not_set() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.environment = ""
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(4))
        let capturedURLs = testHTTPExecutor.requests.compactMap { $0.url?.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(2), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
        expect(NSRegularExpression.match(capturedURLs.at(3), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
    }

    // RSC15g4
    @available(*, deprecated, message: "This test is marked as deprecated so as to not trigger a compiler warning for using the -ARTClientOptions.fallbackHostsUseDefault property. Remove this deprecation when removing the property.")
    func test__046__RestClient__Host_Fallback__applies_when_ClientOptions_fallbackHostsUseDefault_is_true() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.environment = "test"
        options.fallbackHostsUseDefault = true
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { error in
                expect(error).to(beNil())
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(2))
        let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
    }

    // RSC15g1
    func test__047__RestClient__Host_Fallback__won_t_apply_fallback_hosts_if_ClientOptions_fallbackHosts_array_is_empty() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.fallbackHosts = [] // to test TO3k6
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(1))
        let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io")).to(beTrue())
    }

    // RSC15g3
    func test__048__RestClient__Host_Fallback__won_t_apply_custom_fallback_hosts_if_ClientOptions_fallbackHosts_and_ClientOptions_environment_are_not_set__use_defaults_instead() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.fallbackHosts = nil
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(2))
        if testHTTPExecutor.requests.count < 2 {
            return
        }

        let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
        expect(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com")).to(beTrue())
    }

    // RSC15e
    func test__049__RestClient__Host_Fallback__every_new_HTTP_request_is_first_attempted_to_the_default_primary_host_rest_ably_io() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 1
        options.fallbackRetryTimeout = 1 // RSC15j exception
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            // RSC15j exception
            delay(1.1) {
                channel.publish(nil, data: "nil") { _ in
                    done()
                }
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(3))
        expect(NSRegularExpression.match(testHTTPExecutor.requests.at(0)?.url?.absoluteString, pattern: "//\(ARTDefault.restHost())")).to(beTrue())
        expect(NSRegularExpression.match(testHTTPExecutor.requests.at(1)?.url?.absoluteString, pattern: "//[a-e].ably-realtime.com")).to(beTrue())
        expect(NSRegularExpression.match(testHTTPExecutor.requests.at(2)?.url?.absoluteString, pattern: "//\(ARTDefault.restHost())")).to(beTrue())
    }

    // RSC15a

    func beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order() {
        ARTFallback_shuffleArray = { array in
            let arranged = expectedHostOrder.reversed().map { array[$0] }
            for (i, element) in arranged.enumerated() {
                array[i] = element
            }
        }
    }

    func afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order() {
        ARTFallback_shuffleArray = originalARTFallback_shuffleArray
    }

    // RSC15h
    func test__065__RestClient__Host_Fallback__retry_hosts_in_random_order__default_fallback_hosts_should_match__a_e__ably_realtime_com() {
        beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order()

        let defaultFallbackHosts = ARTDefault.fallbackHosts()
        defaultFallbackHosts.forEach { host in
            expect(host).to(match("[a-e].ably-realtime.com"))
        }
        expect(defaultFallbackHosts).to(haveCount(5))

        afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order()
    }

    // RSC15i
    func test__066__RestClient__Host_Fallback__retry_hosts_in_random_order__environment_fallback_hosts_have_the_format__environment___a_e__fallback_ably_realtime_com() {
        beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order()

        let environmentFallbackHosts = ARTDefault.fallbackHosts(withEnvironment: "sandbox")
        environmentFallbackHosts.forEach { host in
            expect(host).to(match("sandbox-[a-e]-fallback.ably-realtime.com"))
        }
        expect(environmentFallbackHosts).to(haveCount(5))

        afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order()
    }

    func test__067__RestClient__Host_Fallback__retry_hosts_in_random_order__until_httpMaxRetryCount_has_been_reached() {
        beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        let client = ARTRest(options: options)
        options.httpMaxRetryCount = 3
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(Int(1 + options.httpMaxRetryCount)))

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[a-e].ably-realtime.com")
        }
        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = Array(expectedHostOrder.map { ARTDefault.fallbackHosts()[$0] }[0 ..< Int(options.httpMaxRetryCount)])

        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))

        afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order()
    }

    func test__068__RestClient__Host_Fallback__retry_hosts_in_random_order__use_custom_fallback_hosts_if_set() {
        beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 10
        let customFallbackHosts = ["j.ably-realtime.com",
                                   "i.ably-realtime.com",
                                   "h.ably-realtime.com",
                                   "g.ably-realtime.com",
                                   "f.ably-realtime.com"]
        options.fallbackHosts = customFallbackHosts
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(customFallbackHosts.count + 1))

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
        }
        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = expectedHostOrder.map { customFallbackHosts[$0] }

        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))

        afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order()
    }

    func test__069__RestClient__Host_Fallback__retry_hosts_in_random_order__until_all_fallback_hosts_have_been_tried() {
        beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 10
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(ARTDefault.fallbackHosts().count + 1))

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[a-e].ably-realtime.com")
        }
        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = expectedHostOrder.map { ARTDefault.fallbackHosts()[$0] }

        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))

        afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order()
    }

    func test__070__RestClient__Host_Fallback__retry_hosts_in_random_order__until_httpMaxRetryCount_has_been_reached__if_custom_fallback_hosts_are_provided_in_ClientOptions_fallbackHosts__then_they_will_be_used_instead() {
        beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 4
        options.fallbackHosts = _fallbackHosts

        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(Int(1 + options.httpMaxRetryCount)))
        expect((testHTTPExecutor.requests.count) < (_fallbackHosts.count + 1)).to(beTrue())

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
        }
        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = Array(expectedHostOrder.map { _fallbackHosts[$0] }[0 ..< Int(options.httpMaxRetryCount)])

        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))

        afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order()
    }

    func test__071__RestClient__Host_Fallback__retry_hosts_in_random_order__until_all_fallback_hosts_have_been_tried__if_custom_fallback_hosts_are_provided_in_ClientOptions_fallbackHosts__then_they_will_be_used_instead() {
        beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 10
        options.fallbackHosts = _fallbackHosts

        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(ARTDefault.fallbackHosts().count + 1))

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
        }

        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = expectedHostOrder.map { _fallbackHosts[$0] }

        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))

        afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order()
    }

    func test__072__RestClient__Host_Fallback__retry_hosts_in_random_order__all_fallback_requests_headers_should_contain__Host__header_with_fallback_host_address() {
        beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 10
        options.fallbackHosts = _fallbackHosts

        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(ARTDefault.fallbackHosts().count + 1))

        let fallbackRequests = testHTTPExecutor.requests.filter {
            NSRegularExpression.match($0.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
        }

        let fallbackRequestsWithHostHeader = fallbackRequests.filter {
            $0.allHTTPHeaderFields!["Host"] == $0.url?.host
        }

        expect(fallbackRequests.count).to(be(fallbackRequestsWithHostHeader.count))

        afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order()
    }

    func test__073__RestClient__Host_Fallback__retry_hosts_in_random_order__if_an_empty_array_of_fallback_hosts_is_provided__then_fallback_host_functionality_is_disabled() {
        beforeEach__RestClient__Host_Fallback__retry_hosts_in_random_order()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 5
        options.fallbackHosts = []

        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(1))
        expect(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//rest.ably.io")).to(beTrue())

        afterEach__RestClient__Host_Fallback__retry_hosts_in_random_order()
    }

    // RSC15d

    func test__074__RestClient__Host_Fallback__should_use_an_alternative_host_when___hostUnreachable() {
        testUsesAlternativeHost(.hostUnreachable, channelName: uniqueChannelName())
    }

    func test__075__RestClient__Host_Fallback__should_use_an_alternative_host_when___requestTimeout_timeout__0_1_() {
        testUsesAlternativeHost(.requestTimeout(timeout: 0.1), channelName: uniqueChannelName())
    }

    func test__076__RestClient__Host_Fallback__should_use_an_alternative_host_when___hostInternalError_code__501_() {
        testUsesAlternativeHost(.hostInternalError(code: 501), channelName: uniqueChannelName())
    }

    // RSC15d
    func test__050__RestClient__Host_Fallback__should_not_use_an_alternative_host_when_the_client_receives_an_bad_request() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .host400BadRequest, resetAfter: 1)
        let channel = client.channels.get(uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        expect(testHTTPExecutor.requests).to(haveCount(1))
        expect(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//rest.ably.io")).to(beTrue())
    }

    // RSC15f

    func test__077__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host___hostUnreachable() {
        testStoresSuccessfulFallbackHostAsDefaultHost(.hostUnreachable, channelName: uniqueChannelName())
    }

    func test__078__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host___requestTimeout_timeout__0_1_() {
        testStoresSuccessfulFallbackHostAsDefaultHost(.requestTimeout(timeout: 0.1), channelName: uniqueChannelName())
    }

    func test__079__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host___hostInternalError_code__501_() {
        testStoresSuccessfulFallbackHostAsDefaultHost(.hostInternalError(code: 501), channelName: uniqueChannelName())
    }

    func test__080__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_restore_default_primary_host_after_fallbackRetryTimeout_expired___hostUnreachable() {
        testRestoresDefaultPrimaryHostAfterTimeoutExpires(.hostUnreachable, channelName: uniqueChannelName())
    }

    func test__081__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_restore_default_primary_host_after_fallbackRetryTimeout_expired___requestTimeout_timeout__0_1_() {
        testRestoresDefaultPrimaryHostAfterTimeoutExpires(.requestTimeout(timeout: 0.1), channelName: uniqueChannelName())
    }

    func test__082__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_restore_default_primary_host_after_fallbackRetryTimeout_expired___hostInternalError_code__501_() {
        testRestoresDefaultPrimaryHostAfterTimeoutExpires(.hostInternalError(code: 501), channelName: uniqueChannelName())
    }

    func test__083__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_use_another_fallback_host_if_previous_fallback_request_failed_and_store_it_as_default_if_current_fallback_request_succseeded___hostUnreachable() {
        testUsesAnotherFallbackHost(.hostUnreachable, channelName: uniqueChannelName())
    }

    func test__084__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_use_another_fallback_host_if_previous_fallback_request_failed_and_store_it_as_default_if_current_fallback_request_succseeded___requestTimeout_timeout__0_1_() {
        testUsesAnotherFallbackHost(.requestTimeout(timeout: 0.1), channelName: uniqueChannelName())
    }

    func test__085__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_use_another_fallback_host_if_previous_fallback_request_failed_and_store_it_as_default_if_current_fallback_request_succseeded___hostInternalError_code__501_() {
        testUsesAnotherFallbackHost(.hostInternalError(code: 501), channelName: uniqueChannelName())
    }

    // RSC8a
    func test__008__RestClient__should_use_MsgPack_binary_protocol() throws {
        let options = AblyTests.commonAppSetup()
        expect(options.useBinaryProtocol).to(beTrue())

        let rest = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        rest.internal.httpExecutor = testHTTPExecutor
        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(uniqueChannelName(prefix: "rest")).publish(nil, data: "message") { _ in
                done()
            }
        }
        
        let request = try XCTUnwrap(testHTTPExecutor.requests.first, "No request found")

        switch extractBodyAsMsgPack(request) {
        case let .failure(error):
            fail(error)
        default: break
        }

        let realtime = AblyTests.newRealtime(options)
        defer { realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.channels.get(uniqueChannelName(prefix: "realtime")).publish(nil, data: "message") { _ in
                done()
            }
        }

        let transport = realtime.internal.transport as! TestProxyTransport
        let jsonArray = transport.rawDataSent.map { AblyTests.msgpackToJSON($0) }
        let messageJson = jsonArray.filter { item in item["action"] == 15 }.last!
        expect(messageJson["messages"][0]["data"].string).to(equal("message"))
    }

    // RSC8b
    func test__009__RestClient__should_use_JSON_text_protocol() throws {
        let options = AblyTests.commonAppSetup()
        options.useBinaryProtocol = false

        let rest = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        rest.internal.httpExecutor = testHTTPExecutor
        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(uniqueChannelName(prefix: "rest")).publish(nil, data: "message") { _ in
                done()
            }
        }
        
        let request = try XCTUnwrap(testHTTPExecutor.requests.first, "No request found")

        switch extractBodyAsJSON(request) {
        case let .failure(error):
            fail(error)
        default: break
        }

        let realtime = AblyTests.newRealtime(options)
        defer { realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.channels.get(uniqueChannelName(prefix: "realtime")).publish(nil, data: "message") { _ in
                done()
            }
        }

        let transport = realtime.internal.transport as! TestProxyTransport
        let object = try! JSONSerialization.jsonObject(with: transport.rawDataSent.first!, options: JSONSerialization.ReadingOptions(rawValue: 0))
        expect(JSONSerialization.isValidJSONObject(object)).to(beTrue())
    }

    // RSC7a
    func test__010__RestClient__X_Ably_Version_must_be_included_in_all_REST_requests() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        waitUntil(timeout: testTimeout) { done in
            client.channels.get(uniqueChannelName()).publish(nil, data: "message") { error in
                expect(error).to(beNil())
                guard let headerAblyVersion = testHTTPExecutor.requests.first?.allHTTPHeaderFields?["X-Ably-Version"] else {
                    fail("X-Ably-Version header not found"); done()
                    return
                }

                // This test should not directly validate version against ARTDefault.version(), as
                // ultimately the version header has been derived from that value.
                expect(headerAblyVersion).to(equal("1.2"))

                done()
            }
        }
    }

    // RSC7b (Deprecated in favor of RCS7d)

    // RSC7d
    func test__011__RestClient__The_Agent_library_identifier_is_composed_of_a_series_of_key__value__entries_joined_by_spaces() {
        let options = AblyTests.commonAppSetup()
        let client = ARTRest(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                let headerAgent = testHTTPExecutor.requests.first!.allHTTPHeaderFields?["Ably-Agent"]
                let ablyAgent = ARTClientInformation.agentIdentifier(withAdditionalAgents: options.agents)
                expect(headerAgent).to(equal(ablyAgent))
                expect(headerAgent!.hasPrefix("ably-cocoa/1.2.18")).to(beTrue())
                done()
            }
        }
    }

    // https://github.com/ably/ably-cocoa/issues/117
    func test__012__RestClient__should_indicate_an_error_if_there_is_no_way_to_renew_the_token() {
        let options = AblyTests.clientOptions()
        options.token = getTestToken(ttl: 0.1)
        let client = ARTRest(options: options)
        waitUntil(timeout: testTimeout) { done in
            delay(0.1) {
                client.channels.get(uniqueChannelName()).publish(nil, data: "message") { error in
                    guard let error = error else {
                        fail("Error is empty"); done()
                        return
                    }
                    expect(error.code).to(equal(Int(ARTState.requestTokenFailed.rawValue)))
                    expect(error.message).to(contain("no means to renew the token is provided"))
                    done()
                }
            }
        }
    }

    // https://github.com/ably/ably-cocoa/issues/577
    func test__013__RestClient__background_behaviour() {
        let options = AblyTests.commonAppSetup()
        waitUntil(timeout: testTimeout) { done in
            URLSession.shared.dataTask(with: URL(string: "https://ably.io")!) { _, _, _ in
                let rest = ARTRest(options: options)
                rest.channels.get(uniqueChannelName()).history { _, _ in
                    done()
                }
            }.resume()
        }
    }

    // https://github.com/ably/ably-cocoa/issues/589
    func test__014__RestClient__client_should_handle_error_messages_in_plaintext_and_HTML_format() {
        let request = URLRequest(url: URL(string: "https://www.example.com")!)
        waitUntil(timeout: testTimeout) { done in
            let rest = ARTRest(key: "xxxx:xxxx")
            rest.internal.execute(request, completion: { response, _, error in
                guard let contentType = response?.allHeaderFields["Content-Type"] as? String else {
                    fail("Response should have a Content-Type"); done(); return
                }
                expect(contentType).to(contain("text/html"))
                guard let error = error as? ARTErrorInfo else {
                    fail("Error is nil"); done(); return
                }
                expect(error.statusCode) == 200
                expect(error.message.lengthOfBytes(using: String.Encoding.utf8)) == 1000
                done()
            })
        }
    }

    // RSC19

    // RSC19a

    func test__086__RestClient__request__method_signature_and_arguments__should_add_query_parameters() throws {
        let rest = ARTRest(key: "xxxx:xxxx")
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        let params = ["foo": "1"]

        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("patch", path: "feature", params: params, body: nil, headers: nil) { paginatedResult, error in
                    expect(error).to(beNil())
                    expect(paginatedResult).toNot(beNil())
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let url = try XCTUnwrap(request.url, "No request url found")
        let acceptHeaderValue = try XCTUnwrap(request.allHTTPHeaderFields?["Accept"], "Accept HTTP Header is missing")
        
        expect(request.httpMethod) == "patch"
        expect(url.absoluteString).to(equal("https://rest.ably.io:443/feature?foo=1"))
        expect(acceptHeaderValue).to(equal("application/x-msgpack,application/json"))
    }

    func test__087__RestClient__request__method_signature_and_arguments__should_add_a_HTTP_body() throws {
        let rest = ARTRest(key: "xxxx:xxxx")
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        let bodyDict = ["blockchain": true]

        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("post", path: "feature", params: nil, body: bodyDict, headers: nil) { paginatedResult, error in
                    expect(error).to(beNil())
                    expect(paginatedResult).toNot(beNil())
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }
        
        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No requests found")
        let rawBody = try XCTUnwrap(request.httpBody, "should have a body")
        let decodedBody = try XCTUnwrap(try rest.internal.defaultEncoder.decode(rawBody), "Decode request body failed")
        let body = try XCTUnwrap(decodedBody as? NSDictionary, "Request body is invalid")
        
        expect(body.value(forKey: "blockchain") as? Bool).to(beTrue())
    }

    func test__088__RestClient__request__method_signature_and_arguments__should_add_a_HTTP_header() throws {
        let rest = ARTRest(key: "xxxx:xxxx")
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        let headers = ["X-foo": "ok"]

        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("get", path: "feature", params: nil, body: nil, headers: headers) { paginatedResult, error in
                    expect(error).to(beNil())
                    expect(paginatedResult).toNot(beNil())
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No requests found")

        let authorization = request.allHTTPHeaderFields?["X-foo"]
        expect(authorization).to(equal("ok"))
    }

    func test__089__RestClient__request__method_signature_and_arguments__should_error_if_method_is_invalid() {
        let rest = ARTRest(key: "xxxx:xxxx")
        let mockHTTPExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHTTPExecutor

        do {
            try rest.request("A", path: "feature", params: nil, body: nil, headers: nil) { _, _ in
                fail("Completion closure should not be called")
            }
        } catch let error as NSError {
            expect(error.code).to(equal(ARTCustomRequestError.invalidMethod.rawValue))
            expect(error.localizedDescription).to(contain("Method isn't valid"))
        }

        do {
            try rest.request("", path: "feature", params: nil, body: nil, headers: nil) { _, _ in
                fail("Completion closure should not be called")
            }
        } catch let error as NSError {
            expect(error.code).to(equal(ARTCustomRequestError.invalidMethod.rawValue))
            expect(error.localizedDescription).to(contain("Method isn't valid"))
        }
    }

    func test__090__RestClient__request__method_signature_and_arguments__should_error_if_path_is_invalid() {
        let rest = ARTRest(key: "xxxx:xxxx")
        let mockHTTPExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHTTPExecutor

        do {
            try rest.request("get", path: "new feature", params: nil, body: nil, headers: nil) { _, _ in
                fail("Completion closure should not be called")
            }
        } catch let error as NSError {
            expect(error.code).to(equal(ARTCustomRequestError.invalidPath.rawValue))
            expect(error.localizedDescription).to(contain("Path isn't valid"))
        }

        do {
            try rest.request("get", path: "", params: nil, body: nil, headers: nil) { _, _ in
                fail("Completion closure should not be called")
            }
        } catch let error as NSError {
            expect(error.code).to(equal(ARTCustomRequestError.invalidPath.rawValue))
            expect(error.localizedDescription).to(contain("Path cannot be empty"))
        }
    }

    func test__091__RestClient__request__method_signature_and_arguments__should_error_if_body_is_not_a_Dictionary_or_an_Array() {
        let rest = ARTRest(key: "xxxx:xxxx")
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor

        do {
            try rest.request("get", path: "feature", params: nil, body: mockHttpExecutor, headers: nil) { _, _ in
                fail("Completion closure should not be called")
            }
        } catch let error as NSError {
            expect(error.code).to(equal(ARTCustomRequestError.invalidBody.rawValue))
            expect(error.localizedDescription).to(contain("should be a Dictionary or an Array"))
        }
    }

    func test__092__RestClient__request__method_signature_and_arguments__should_do_a_request_and_receive_a_valid_response() throws {
        let options = AblyTests.commonAppSetup()
        let rest = ARTRest(options: options)
        let channel = rest.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish("a", data: nil) { error in
                expect(error).to(beNil())
                done()
            }
        }

        let proxyHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        rest.internal.httpExecutor = proxyHTTPExecutor

        var httpPaginatedResponse: ARTHTTPPaginatedResponse!
        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("get", path: "/channels/\(channel.name)", params: nil, body: nil, headers: nil) { paginatedResponse, error in
                    expect(error).to(beNil())
                    guard let paginatedResponse = paginatedResponse else {
                        fail("PaginatedResult is empty"); done(); return
                    }
                    expect(paginatedResponse.items.count) == 1
                    guard let channelDetailsDict = paginatedResponse.items.first else {
                        fail("PaginatedResult first element is missing"); done(); return
                    }
                    expect(channelDetailsDict.value(forKey: "channelId") as? String).to(equal(channel.name))
                    expect(paginatedResponse.hasNext) == false
                    expect(paginatedResponse.isLast) == true
                    expect(paginatedResponse.statusCode) == 200
                    expect(paginatedResponse.success) == true
                    expect(paginatedResponse.errorCode) == 0
                    expect(paginatedResponse.errorMessage).to(beNil())
                    expect(paginatedResponse.headers).toNot(beEmpty())
                    httpPaginatedResponse = paginatedResponse
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }

        let response = try XCTUnwrap(proxyHTTPExecutor.responses.first, "No responses found")

        expect(response.statusCode) == httpPaginatedResponse.statusCode
        expect(response.allHeaderFields as NSDictionary) == httpPaginatedResponse.headers
    }

    func test__093__RestClient__request__method_signature_and_arguments__should_handle_response_failures() throws {
        let options = AblyTests.commonAppSetup()
        let rest = ARTRest(options: options)
        let channel = rest.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish("a", data: nil) { error in
                expect(error).to(beNil())
                done()
            }
        }

        let proxyHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
        rest.internal.httpExecutor = proxyHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("get", path: "feature", params: nil, body: nil, headers: nil) { paginatedResponse, error in
                    expect(error).to(beNil())
                    guard let paginatedResponse = paginatedResponse else {
                        fail("PaginatedResult is empty"); done(); return
                    }
                    expect(paginatedResponse.items.count) == 0
                    expect(paginatedResponse.hasNext) == false
                    expect(paginatedResponse.isLast) == true
                    expect(paginatedResponse.statusCode) == 404
                    expect(paginatedResponse.success) == false
                    expect(paginatedResponse.errorCode) == ARTErrorCode.notFound.intValue
                    expect(paginatedResponse.errorMessage).to(contain("Could not find path"))
                    expect(paginatedResponse.headers).toNot(beEmpty())
                    expect(paginatedResponse.headers["X-Ably-Errorcode"] as? String).to(equal("\(ARTErrorCode.notFound.intValue)"))
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }

        let response = try XCTUnwrap(proxyHTTPExecutor.responses.first, "No responses found")

        expect(response.statusCode) == 404
        expect(response.value(forHTTPHeaderField: "X-Ably-Errorcode")).to(equal("\(ARTErrorCode.notFound.intValue)"))
    }

    // RSA4e
    func test__094__RestClient__if_in_the_course_of_a_REST_request_an_attempt_to_authenticate_using_authUrl_fails_due_to_a_timeout__the_request_should_result_in_an_error_with_code_40170__statusCode_401__and_a_suitable_error_message() {
        let options = AblyTests.commonAppSetup()
        let token = getTestToken()
        options.httpRequestTimeout = 3 // short timeout to make it fail faster
        options.authUrl = URL(string: "http://10.255.255.1")!
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "text"))
        options.authParams?.append(URLQueryItem(name: "body", value: token))

        let client = ARTRest(options: options)
        waitUntil(timeout: testTimeout) { done in
            let channel = client.channels.get(uniqueChannelName())
            channel.publish("test", data: "test-data") { error in
                guard let error = error else {
                    fail("Error should not be empty")
                    done()
                    return
                }
                expect(error.statusCode).to(equal(401))
                expect(error.code).to(equal(ARTErrorCode.errorFromClientTokenCallback.intValue))
                expect(error.message).to(contain("Error in requesting auth token"))
                done()
            }
        }
    }

    // RSC7c

    func test__095__RestClient__request_IDs__should_add__request_id__query_parameter() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.addRequestIds = true

        let restA = ARTRest(options: options)
        let mockHttpExecutor = MockHTTPExecutor()
        restA.internal.httpExecutor = mockHttpExecutor
        waitUntil(timeout: testTimeout) { done in
            restA.channels.get(uniqueChannelName()).publish(nil, data: "something") { error in
                expect(error).to(beNil())
                guard let url = mockHttpExecutor.requests.first?.url else {
                    fail("No requests found")
                    return
                }
                expect(url.query).to(contain("request_id"))
                done()
            }
        }

        mockHttpExecutor.reset()

        options.addRequestIds = false
        let restB = ARTRest(options: options)
        restB.internal.httpExecutor = mockHttpExecutor
        waitUntil(timeout: testTimeout) { done in
            restB.channels.get(uniqueChannelName()).publish(nil, data: "something") { error in
                expect(error).to(beNil())
                expect(mockHttpExecutor.requests).to(haveCount(1))
                guard let url = mockHttpExecutor.requests.first?.url else {
                    fail("No requests found")
                    return
                }
                expect(url.query).to(beNil())
                done()
            }
        }
    }

    func test__096__RestClient__request_IDs__should_remain_the_same_if_a_request_is_retried_to_a_fallback_host() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 5
        options.addRequestIds = true
        options.logLevel = .debug

        let client = ARTRest(options: options)
        let mockHTTP = MockHTTP(logger: options.logHandler)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)

        var fallbackRequests: [URLRequest] = []
        testHTTPExecutor.setListenerAfterRequest { request in
            if NSRegularExpression.match(request.url!.absoluteString, pattern: "//[a-e].ably-realtime.com") {
                fallbackRequests += [request]
            }
        }

        var requestId: String = ""
        let channel = client.channels.get(uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "something") { error in
                guard let error = error else {
                    fail("Expecting an error"); done(); return
                }
                guard let firstRequestId = extractURLQueryValue(testHTTPExecutor.requests.first?.url, key: "request_id") else {
                    fail("First request attempt doesn't have the 'request_id'."); return
                }
                requestId = firstRequestId
                expect(error.message).to(contain(requestId))
                done()
            }
        }

        expect(fallbackRequests).toNot(beEmpty())
        expect(fallbackRequests).to(allPass { extractURLQueryValue($0?.url, key: "request_id") == requestId })
    }

    func test__097__RestClient__request_IDs__ErrorInfo_should_have__requestId__property() {
        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.addRequestIds = true

        let rest = ARTRest(options: options)
        let mockHttpExecutor = MockHTTPExecutor()
        mockHttpExecutor.simulateIncomingErrorOnNextRequest(NSError(domain: "ably-test", code: ARTErrorCode.invalidMessageDataOrEncoding.intValue, userInfo: ["Message": "Ably test message"]))
        rest.internal.httpExecutor = mockHttpExecutor

        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(uniqueChannelName()).publish(nil, data: "something") { error in
                expect(error).toNot(beNil())
                expect(error?.requestId).toNot(beNil())
                done()
            }
        }
    }
}
