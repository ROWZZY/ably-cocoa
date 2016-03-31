//
//  RealtimeClientPresence.swift
//  Ably
//
//  Created by Ricardo Pereira on 07/03/16.
//  Copyright © 2016 Ably. All rights reserved.
//

import Quick
import Nimble

class RealtimeClientPresence: QuickSpec {
    override func spec() {
        describe("Presence") {

            // RTP1
            context("ProtocolMessage bit flag") {

                it("when no members are present") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let client = ARTRealtime(options: options)
                    client.setTransportClass(TestProxyTransport)
                    client.connect()
                    defer { client.close() }
                    let channel = client.channels.get("test")
                    channel.attach()

                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    let transport = client.transport as! TestProxyTransport
                    let attached = transport.protocolMessagesReceived.filter({ $0.action == .Attached })[0]

                    expect(attached.flags & 0x1).to(equal(0))
                    expect(attached.isSyncEnabled()).to(beFalse())
                    expect(channel.presence.syncComplete).to(beFalse())
                    expect(channel.presenceMap.syncComplete).to(beFalse())
                }

                it("when members are present") {
                    let options = AblyTests.commonAppSetup()

                    var disposable = [ARTRealtime]()
                    defer {
                        for clientItem in disposable {
                            clientItem.close()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        disposable += AblyTests.addMembersSequentiallyToChannel("test", members: 250, options: options) {
                            done()
                        }
                    }

                    options.autoConnect = false
                    let client = ARTRealtime(options: options)
                    client.setTransportClass(TestProxyTransport)
                    client.connect()
                    defer { client.close() }
                    let channel = client.channels.get("test")
                    channel.attach()

                    expect(channel.presence.syncComplete).to(beFalse())
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    let transport = client.transport as! TestProxyTransport
                    let attached = transport.protocolMessagesReceived.filter({ $0.action == .Attached })[0]

                    // There are members present on the channel
                    expect(attached.flags & 0x1).to(equal(1))
                    expect(attached.isSyncEnabled()).to(beTrue())
                    
                    expect(channel.presence.syncComplete).toEventually(beTrue(), timeout: testTimeout)

                    expect(transport.protocolMessagesReceived.filter({ $0.action == .Sync })).to(haveCount(3))
                }

            }

            // RTP3
            pending("should complete the SYNC operation when the connection is disconnected unexpectedly") {
                let options = AblyTests.commonAppSetup()
                options.disconnectedRetryTimeout = 1.0
                var clientSecondary: ARTRealtime!
                defer { clientSecondary.close() }

                waitUntil(timeout: testTimeout) { done in
                    clientSecondary = AblyTests.addMembersSequentiallyToChannel("test", members: 150, options: options) {
                        done()
                    }.first
                }

                let client = AblyTests.newRealtime(options)
                defer { client.close() }
                let channel = client.channels.get("test")

                var lastSyncSerial: String?
                waitUntil(timeout: testTimeout) { done in
                    channel.attach() { _ in
                        let transport = client.transport as! TestProxyTransport
                        transport.beforeProcessingReceivedMessage = { protocolMessage in
                            if protocolMessage.action == .Sync {
                                lastSyncSerial = protocolMessage.channelSerial
                                client.onDisconnected()
                                done()
                            }
                        }
                    }
                }

                expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.Connecting), timeout: options.disconnectedRetryTimeout + 1.0)

                //Client library requests a SYNC resume by sending a SYNC ProtocolMessage with the last received sync serial number
                let transport = client.transport as! TestProxyTransport
                expect(transport.protocolMessagesSent.filter{ $0.action == .Sync }).toEventually(haveCount(1), timeout: testTimeout)
                expect(transport.protocolMessagesSent.filter{ $0.action == .Sync }.first!.channelSerial).to(equal(lastSyncSerial))

                expect(transport.protocolMessagesReceived.filter{ $0.action == .Sync }).to(haveCount(2))
            }

            // RTP4
            pending("should receive all 250 members") {
                let options = AblyTests.commonAppSetup()
                var clientSource: ARTRealtime!
                defer { clientSource.close() }

                let clientTarget = ARTRealtime(options: options)
                defer { clientTarget.close() }
                let channel = clientTarget.channels.get("test")

                channel.presence.subscribe { member in
                    expect(member.action).to(equal(ARTPresenceAction.Present))
                }

                waitUntil(timeout: testTimeout) { done in
                    clientSource = AblyTests.addMembersSequentiallyToChannel("test", members: 250, options: options) {
                        done()
                    }.first
                }

                waitUntil(timeout: testTimeout) { done in
                    channel.presence.get() { members, error in
                        expect(error).to(beNil())
                        expect(members).to(haveCount(250))
                        done()
                    }
                }
            }

            // RTP6
            context("subscribe") {

                // RTP6a
                pending("with no arguments should subscribe a listener to all presence messages") {
                    let options = AblyTests.commonAppSetup()

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    var receivedMembers = [ARTPresenceMessage]()
                    channel1.presence.subscribe { member in
                        receivedMembers.append(member)
                    }

                    channel2.presence.enterClient("john", data: "online")
                    channel2.presence.updateClient("john", data: "away")
                    channel2.presence.leaveClient("john", data: nil)

                    expect(receivedMembers).toEventually(haveCount(3), timeout: testTimeout)

                    expect(receivedMembers[0].action).to(equal(ARTPresenceAction.Enter))
                    expect(receivedMembers[0].data as? NSObject).to(equal("online"))
                    expect(receivedMembers[0].clientId).to(equal("john"))

                    expect(receivedMembers[1].action).to(equal(ARTPresenceAction.Update))
                    expect(receivedMembers[1].data as? NSObject).to(equal("away"))
                    expect(receivedMembers[1].clientId).to(equal("john"))

                    expect(receivedMembers[2].action).to(equal(ARTPresenceAction.Leave))
                    expect(receivedMembers[2].data).to(beNil())
                    expect(receivedMembers[2].clientId).to(equal("john"))
                }

            }

            // RTP7
            context("unsubscribe") {

                // RTP7a
                it("with no arguments unsubscribes the listener if previously subscribed with an action-specific subscription") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    let listener = channel.presence.subscribe { _ in }
                    expect(channel.presenceEventEmitter.anyListeners).to(haveCount(1))
                    channel.presence.unsubscribe(listener)
                    expect(channel.presenceEventEmitter.anyListeners).to(haveCount(0))
                }

            }

            // RTP5
            context("Channel state change side effects") {

                // RTP5a
                it("all queued presence messages should fail immediately if the channel enters the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let protocolError = AblyTests.newErrorProtocolMessage()
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).to(beIdenticalTo(protocolError.error))
                            done()
                        }
                        channel.onError(protocolError)
                    }
                }


                // RTP5a
                pending("all queued presence messages should fail immediately if the channel enters the DETACHED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).toNot(beNil())
                            done()
                        }
                        channel.detach()
                    }
                }

            }


            // RTP5
            context("Channel state change side effects") {

                // RTP5b
                pending("all queued presence messages will be sent immediately and a presence SYNC will be initiated implicitly if a channel enters the ATTACHED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")
                    channel.attach()

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).to(beNil())
                            expect(channel.queuedMessages).to(haveCount(0))
                            done()
                        }
                        expect(channel.queuedMessages).to(haveCount(1))
                    }

                    expect(channel.state).to(equal(ARTRealtimeChannelState.Attached))
                    expect(channel.presence.syncComplete).toEventually(beTrue(), timeout: testTimeout)
                    expect(channel.presenceMap.members).to(haveCount(1))
                }

            }

            // RTP8
            context("enter") {

                // RTP8a
                it("should enter the current client, optionally with the data provided") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel1.presence.subscribe(.Enter) { member in
                            expect(member.clientId).to(equal(options.clientId))
                            expect(member.data as? NSObject).to(equal("online"))
                            done()
                        }
                        channel2.presence.enter("online")
                    }
                }

            }

            // RTP7
            context("unsubscribe") {

                // RTP7b
                it("with a single action argument unsubscribes the provided listener to all presence messages for that action") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    let listener = channel.presence.subscribe(.Present) { _ in }
                    expect(channel.presenceEventEmitter.listeners).to(haveCount(1))
                    channel.presence.unsubscribe(.Present, listener: listener)
                    expect(channel.presenceEventEmitter.listeners).to(haveCount(0))
                }

            }

            // RTP6
            context("subscribe") {

                // RTP6c
                it("should implicitly attach the channel") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    expect(channel.state).to(equal(ARTRealtimeChannelState.Initialized))
                    channel.presence.subscribe { _ in }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    channel.detach()

                    channel.presence.subscribe(.Present) { _ in }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)
                }

                // RTP6c
                pending("should result in an error if the channel is in the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    channel.onError(AblyTests.newErrorProtocolMessage())

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe { member in
                            // TODO: missing error
                            done()
                        }
                    }
                    expect(channel.presenceEventEmitter.anyListeners).to(haveCount(0))
                }

                // RTP6c
                pending("should result in an error if the channel moves to the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let error = AblyTests.newErrorProtocolMessage()
                        channel.presence.subscribe { _ in
                            // TODO: missing error
                            done()
                        }
                        channel.onError(error)
                    }
                    expect(channel.presenceEventEmitter.anyListeners).to(haveCount(0))
                }

            }

            // RTP6
            context("subscribe") {

                // RTP6b
                it("with a single action argument") {
                    let options = AblyTests.commonAppSetup()

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel1.presence.subscribe(.Update) { member in
                            expect(member.action).to(equal(ARTPresenceAction.Update))
                            expect(member.clientId).to(equal("john"))
                            expect(member.data as? NSObject).to(equal("away"))
                            done()
                        }
                        channel2.presence.enterClient("john", data: "online")
                        channel2.presence.updateClient("john", data: "away")
                        channel2.presence.leaveClient("john", data: nil)
                    }
                }

            }

            // RTP8
            context("enter") {

                // RTP8b
                it("optionally a callback can be provided that is called for success") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel1.presence.subscribe(.Enter) { member in
                            expect(member.clientId).to(equal(options.clientId))
                            expect(member.data as? NSObject).to(equal("online"))
                            done()
                        }
                        channel2.presence.enter("online") { error in
                            expect(error).to(beNil())
                        }
                    }
                }

                // RTP8b
                it("optionally a callback can be provided that is called for failure") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel1.presence.subscribe(.Enter) { member in
                            fail("shouldn't be called")
                        }
                        let protocolError = AblyTests.newErrorProtocolMessage()
                        channel2.presence.enter("online") { error in
                            expect(error).to(beIdenticalTo(protocolError.error))
                            done()
                        }
                        channel2.onError(protocolError)
                    }
                }

            }

            // RTP15e
            let cases: [String:(ARTRealtimePresence, Optional<(ARTErrorInfo?)->Void>)->()] = [
                "enterClient": { $0.enterClient("john", data: nil, callback: $1) },
                "updateClient": { $0.updateClient("john", data: nil, callback: $1) },
                "leaveClient": { $0.leaveClient("john", data: nil, callback: $1) }
            ]
            for (testCase, performMethod) in cases {
                context(testCase) {
                    it("should implicitly attach the Channel") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }
                        let channel = client.channels.get("test")

                        expect(channel.state).to(equal(ARTRealtimeChannelState.Initialized))
                        waitUntil(timeout: testTimeout) { done in
                            //Call: enterClient, updateClient and leaveClient
                            performMethod(channel.presence) { errorInfo in
                                expect(errorInfo).to(beNil())
                                done()
                            }
                            expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))
                        }
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Attached))
                    }

                    it("should result in an error if the channel is in the FAILED state") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }
                        let channel = client.channels.get("test")

                        channel.onError(AblyTests.newErrorProtocolMessage())

                        waitUntil(timeout: testTimeout) { done in
                            //Call: enterClient, updateClient and leaveClient
                            performMethod(channel.presence) { errorInfo in
                                expect(errorInfo!.message).to(contain("invalid channel state"))
                                done()
                            }
                        }
                    }

                    it("should result in an error if the channel moves to the FAILED state") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }
                        let channel = client.channels.get("test")

                        waitUntil(timeout: testTimeout) { done in
                            let error = AblyTests.newErrorProtocolMessage()
                            //Call: enterClient, updateClient and leaveClient
                            performMethod(channel.presence) { errorInfo in
                                expect(errorInfo).to(equal(error.error))
                                done()
                            }
                            channel.onError(error)
                        }
                    }
                }
            }

            // RTP16
            context("Connection state conditions") {

                // RTP16a
                it("all presence messages are published immediately if the connection is CONNECTED") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).to(beNil())
                            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Connected))
                            expect(channel.queuedMessages).to(haveCount(0))
                            done()
                        }
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Connecting))
                        expect(channel.queuedMessages).to(haveCount(1))
                    }
                }

                // RTP16b
                pending("all presence messages will be queued and delivered as soon as the connection state returns to CONNECTED") {
                    let options = AblyTests.commonAppSetup()
                    options.disconnectedRetryTimeout = 1.0
                    let client = ARTRealtime(options: options)
                    defer { client.close() }
                    let channel = client.channels.get("test")
                    expect(client.options.queueMessages).to(beTrue())

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { _ in
                            client.onDisconnected()
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).to(beNil())
                            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Connected))
                            expect(channel.queuedMessages).to(haveCount(0))
                            done()
                        }
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Disconnected))
                        expect(channel.queuedMessages).to(haveCount(1))
                    }
                }

                // RTP16b
                pending("all presence messages will be lost if queueMessages has been explicitly set to false") {
                    let options = AblyTests.commonAppSetup()
                    options.disconnectedRetryTimeout = 1.0
                    options.queueMessages = false
                    let client = ARTRealtime(options: options)
                    defer { client.close() }
                    let channel = client.channels.get("test")
                    expect(client.options.queueMessages).to(beFalse())

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { _ in
                            client.onDisconnected()
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).toNot(beNil())
                            done()
                        }
                        expect(channel.queuedMessages).to(haveCount(0))
                    }
                }

                // RTP16c
                pending("should result in an error if the connection state is INITIALIZED") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let client = ARTRealtime(options: options)
                    defer { client.close() }
                    let channel = client.channels.get("test")
                    expect(client.options.queueMessages).to(beTrue())

                    expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Initialized))

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).toNot(beNil())
                            expect(channel.queuedMessages).to(haveCount(0))
                            done()
                        }
                        expect(channel.queuedMessages).to(haveCount(0))
                    }
                }

                // RTP16c
                let cases: [ARTRealtimeConnectionState:(ARTRealtime)->()] = [
                    .Suspended: { client in client.onSuspended() },
                    .Closed: { client in client.close() },
                    .Failed: { client in client.onError(AblyTests.newErrorProtocolMessage()) }
                ]
                for (connectionState, performMethod) in cases {
                    it("should result in an error if the connection state is \(connectionState)") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }
                        let channel = client.channels.get("test")
                        expect(client.options.queueMessages).to(beTrue())

                        waitUntil(timeout: testTimeout) { done in
                            channel.attach() { _ in
                                performMethod(client)
                                done()
                            }
                        }

                        expect(client.connection.state).toEventually(equal(connectionState), timeout: testTimeout)

                        waitUntil(timeout: testTimeout) { done in
                            channel.presence.enterClient("user", data: nil) { error in
                                expect(error).toNot(beNil())
                                expect(channel.queuedMessages).to(haveCount(0))
                                done()
                            }
                            expect(channel.queuedMessages).to(haveCount(0))
                        }
                    }
                }

            }

            // RTP11
            context("get") {

                context("query") {
                    it("waitForSync should be true by default") {
                        expect(ARTRealtimePresenceQuery().waitForSync).to(beTrue())
                    }
                }

                // RTP11a
                it("should return a list of current members on the channel") {
                    let options = AblyTests.commonAppSetup()

                    var disposable = [ARTRealtime]()
                    defer {
                        for clientItem in disposable {
                            clientItem.close()
                        }
                    }

                    let expectedData = "online"
                    waitUntil(timeout: testTimeout) { done in
                        disposable += AblyTests.addMembersSequentiallyToChannel("test", members: 150, data:expectedData, options: options) {
                            done()
                        }
                    }

                    let client = ARTRealtime(options: options)
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    var presenceQueryWasCreated = false
                    ARTRealtimePresenceQuery.testSuite_injectIntoClassMethod("init") { // Default initialiser
                        presenceQueryWasCreated = true
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            expect(members).to(haveCount(150))
                            expect(members!.first).to(beAnInstanceOf(ARTPresenceMessage))
                            expect(members).to(allPass({ member in
                                return NSRegularExpression.match(member!.clientId, pattern: "^user(\\d+)$")
                                    && (member!.data as? NSObject) == expectedData
                            }))
                            done()
                        }
                    }

                    expect(presenceQueryWasCreated).to(beTrue())
                }

                // RTP11b
                it("should implicitly attach the channel") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    expect(channel.state).to(equal(ARTRealtimeChannelState.Initialized))
                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get() { membersPage, error in
                            expect(error).to(beNil())
                            expect(membersPage).toNot(beNil())
                            done()
                        }
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))
                    }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.Attached))
                }

                // RTP11b
                pending("should result in an error if the channel is in the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    channel.onError(AblyTests.newErrorProtocolMessage())

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get() { members, error in
                            expect(error!.message).to(contain("invalid channel state"))
                            expect(members).to(beNil())
                            done()
                        }
                    }
                }

                // RTP11b
                pending("should result in an error if the channel moves to the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let error = AblyTests.newErrorProtocolMessage()
                        channel.presence.get() { members, error in
                            expect(error).to(equal(error))
                            expect(members).to(beNil())
                            done()
                        }
                        channel.onError(error)
                    }
                }

            }

        }
    }
}
