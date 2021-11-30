import Ably
import Nimble
import Quick
import SwiftyJSON
import Foundation

class Stats: QuickSpec {
    override func spec() {
        describe("Stats") {
            let encoder = ARTJsonLikeEncoder()

            // TS6
            func reusableTestsTestAttribute(_ attribute: String) {
                let data: JSON = [
                    [ attribute: [ "messages": [ "count": 5], "all": [ "data": 10 ] ] ]
                ]
                let rawData = try! data.rawData()
                let stats = try! encoder.decodeStats(rawData)[0] as? ARTStats
                let subject = stats?.value(forKey: attribute) as? ARTStatsMessageTypes

                it("should return a MessagesTypes object") {
                    expect(subject).to(beAnInstanceOf(ARTStatsMessageTypes.self))
                }

                // TS5
                it("should return value for message counts") {
                    expect(subject?.messages.count).to(equal(5))
                }

                // TS5
                it("should return value for all data transferred") {
                    expect(subject?.all.data).to(equal(10))
                }

                // TS2
                it("should return zero for empty values") {
                    expect(subject?.presence.count).to(equal(0))
                }
            }
            
            context("all") {
                reusableTestsTestAttribute("all")
            }
            
            context("persisted") {
                reusableTestsTestAttribute("persisted")
            }

            // TS7
            func reusableTestsTestDirection(_ direction: String) {
                let data: JSON = [
                    [ direction: [
                        "realtime": [ "messages": [ "count": 5] ],
                        "all": [ "messages": [ "count": 25 ], "presence": [ "data": 210 ] ]
                    ] ]
                ]
                let rawData = try! data.rawData()
                let stats = try! encoder.decodeStats(rawData)[0] as? ARTStats
                let subject = stats?.value(forKey: direction) as? ARTStatsMessageTraffic

                it("should return a MessageTraffic object") {
                    expect(subject).to(beAnInstanceOf(ARTStatsMessageTraffic.self))
                }

                // TS5
                it("should return value for realtime message counts") {
                    expect(subject?.realtime.messages.count).to(equal(5))
                }

                // TS5
                it("should return value for all presence data") {
                    expect(subject?.all.presence.data).to(equal(210))
                }
            }
        
            context("inbound") {
                reusableTestsTestDirection("inbound")
            }
            
            context("outbound") {
                reusableTestsTestDirection("outbound")
            }

            // TS4
            context("connections") {
                let subject: ARTStatsConnectionTypes? = {
                    let data: JSON = [
                        [ "connections": [ "tls": [ "opened": 5], "all": [ "peak": 10 ] ] ]
                    ]
                    let rawData = try! data.rawData()
                    let stats = try! encoder.decodeStats(rawData)[0] as? ARTStats
                    return stats?.connections
                }()

                it("should return a ConnectionTypes object") {
                    expect(subject).to(beAnInstanceOf(ARTStatsConnectionTypes.self))
                }

                it("should return value for tls opened counts") {
                    expect(subject?.tls.opened).to(equal(5))
                }

                it("should return value for all peak connections") {
                    expect(subject?.all.peak).to(equal(10))
                }

                // TS2
                it("should return zero for empty values") {
                    expect(subject?.all.refused).to(equal(0))
                }
            }

            // TS9
            context("channels") {
                let channelsTestsSubject: ARTStatsResourceCount? = {
                    let data: JSON = [
                        [ "channels": [ "opened": 5, "peak": 10 ] ]
                    ]
                    let rawData = try! data.rawData()
                    let stats = try! encoder.decodeStats(rawData)[0] as? ARTStats
                    return stats?.channels
                }()

                it("should return a ResourceCount object") {
                    expect(channelsTestsSubject).to(beAnInstanceOf(ARTStatsResourceCount.self))
                }

                it("should return value for opened counts") {
                    expect(channelsTestsSubject?.opened).to(equal(5))
                }

                it("should return value for peak channels") {
                    expect(channelsTestsSubject?.peak).to(equal(10))
                }

                // TS2
                it("should return zero for empty values") {
                    expect(channelsTestsSubject?.refused).to(equal(0))
                }
            }

            // TS8
            func reusableTestsTestRequestType(_ requestType: String) {
                let data: JSON = [
                    [ requestType: [ "succeeded": 5, "failed": 10 ] ]
                ]
                let rawData = try! data.rawData()
                let stats = try! encoder.decodeStats(rawData)[0] as? ARTStats
                let subject = stats?.value(forKey: requestType) as? ARTStatsRequestCount
                
                it("should return a RequestCount object") {
                    expect(subject).to(beAnInstanceOf(ARTStatsRequestCount.self))
                }

                it("should return value for succeeded") {
                    expect(subject?.succeeded).to(equal(5))
                }

                it("should return value for failed") {
                    expect(subject?.failed).to(equal(10))
                }
            }
            
            context("apiRequests") {
                reusableTestsTestRequestType("apiRequests")
            }
            
            context("tokenRequests") {
                reusableTestsTestRequestType("tokenRequests")
            }
            
            context("interval") {
                it("should return a Date object representing the start of the interval") {
                    let data: JSON = [
                        [ "intervalId": "2004-02-01:05:06" ]
                    ]
                    let rawData = try! data.rawData()
                    let stats = try! encoder.decodeStats(rawData)[0] as? ARTStats
                    
                    let dateComponents = NSDateComponents()
                    dateComponents.year = 2004
                    dateComponents.month = 2
                    dateComponents.day = 1
                    dateComponents.hour = 5
                    dateComponents.minute = 6
                    dateComponents.timeZone = NSTimeZone(name: "UTC") as TimeZone?

                    let expected = NSCalendar(identifier: NSCalendar.Identifier.gregorian)?.date(from: dateComponents as DateComponents)

                    expect(stats?.intervalTime()).to(equal(expected))
                }
            }
            
            context("push") {
                let pushTestsSubject: ARTStatsPushCount? = {
                    let data: JSON = [
                        [ "push":
                            [
                                "messages": 10,
                                "notifications": [
                                    "invalid": 1,
                                    "attempted": 2,
                                    "successful": 3,
                                    "failed": 4
                                ],
                                "directPublishes": 5
                            ]
                        ]
                    ]
                    let rawData = try! data.rawData()
                    let stats = try! encoder.decodeStats(rawData)[0] as? ARTStats
                    return stats?.pushes
                }()

                it("should return a ARTStatsPushCount object") {
                    expect(pushTestsSubject).to(beAnInstanceOf(ARTStatsPushCount.self))
                }

                it("should return value for messages count") {
                    expect(pushTestsSubject?.messages).to(equal(10))
                }

                it("should return value for invalid notifications") {
                    expect(pushTestsSubject?.invalid).to(equal(1))
                }

                it("should return value for attempted notifications") {
                    expect(pushTestsSubject?.attempted).to(equal(2))
                }

                it("should return value for successful notifications") {
                    expect(pushTestsSubject?.succeeded).to(equal(3))
                }

                it("should return value for failed notifications") {
                    expect(pushTestsSubject?.failed).to(equal(4))
                }

                it("should return value for directPublishes") {
                    expect(pushTestsSubject?.direct).to(equal(5))
                }
            }

            context("inProgress") {
                let inProgressTestsStats: ARTStats? = {
                    let data: JSON = [
                        [ "inProgress": "2004-02-01:05:06" ]
                    ]
                    let rawData = try! data.rawData()
                    return try! encoder.decodeStats(rawData)[0] as? ARTStats
                }()

                it("should return a Date object representing the last sub-interval included in this statistic") {
                    let dateComponents = NSDateComponents()
                    dateComponents.year = 2004
                    dateComponents.month = 2
                    dateComponents.day = 1
                    dateComponents.hour = 5
                    dateComponents.minute = 6
                    dateComponents.timeZone = NSTimeZone(name: "UTC") as TimeZone?

                    let expected = NSCalendar(identifier: NSCalendar.Identifier.gregorian)?.date(from: dateComponents as DateComponents)

                    expect(inProgressTestsStats?.dateFromInProgress()).to(equal(expected))
                }
            }
            
            context("count") {
                let countTestStats: ARTStats? = {
                    let data: JSON = [
                        [ "count": 55 ]
                    ]
                    let rawData = try! data.rawData()
                    return try! encoder.decodeStats(rawData)[0] as? ARTStats
                }()

                it("should return value for number of lower-level stats") {
                    expect(countTestStats?.count).to(equal(55))
                }
            }
        }
    }
}
