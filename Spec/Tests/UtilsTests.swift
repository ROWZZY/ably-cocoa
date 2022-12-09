import Ably
import Nimble
import XCTest

class UtilsTests: XCTestCase {
    
    // MARK: Backoff and jitter
    
    func testRetryDelayCalculationForRetryNumberWithConstantRandomSeeding() {
        let initialRetryTimeout = 1.0
        
        AblyTests.resetRandomGenerator()
        
        let jitterValues = (0...4).map { _ in ARTUtils.generateJitterCoefficient() }
        let backoffValues = (1...5).map { n in ARTUtils.backoffCoefficient(forRetryNumber: n) } // [ 1.0, 4.0/3.0, 5.0/3.0, 2.0, 2.0 ]
        let delays1 = (0...4).map { i in initialRetryTimeout * backoffValues[i] * jitterValues[i] }
        
        AblyTests.resetRandomGenerator()
        let delays2 = (1...5).map { n in ARTUtils.retryDelay(fromInitialRetryTimeout: initialRetryTimeout, forRetryNumber: n) }
        
        expect(delays1).to(equal(delays2))
        
        AblyTests.resetRandomGenerator()
        expect(delays1).to(equal(AblyTests.backoffWithJitterDelaysForTimeout(initialRetryTimeout)))
    }
    
    func testRetryDelayCalculationForRetryNumberWithProperRandomSeeding() {
        ARTUtils.seedRandomWithSystemTime()
        
        let initialRetryTimeout = 15.0
        let delays = (1...5).map { n in ARTUtils.retryDelay(fromInitialRetryTimeout: initialRetryTimeout, forRetryNumber: n) }
        
        for i in 0..<delays.count {
            let delay = delays[i]
            let backoff = ARTUtils.backoffCoefficient(forRetryNumber: i + 1)
            let maxValue = initialRetryTimeout * backoff
            let minValue = initialRetryTimeout * backoff * (1.0 - ARTUtils.jitterDelta())
            expect((minValue...maxValue).contains(delay)).to(beTrue())
        }
    }
}
