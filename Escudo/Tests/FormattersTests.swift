import XCTest
@testable import Escudo

final class FormattersTests: XCTestCase {

    func testPercentagePositive() {
        let result = Formatters.percentage(Decimal(string: "12.34")!)
        XCTAssertTrue(result.hasPrefix("+"), "positive P&L should have '+' prefix")
        XCTAssertTrue(result.hasSuffix("%"))
    }

    func testPercentageNegative() {
        let result = Formatters.percentage(Decimal(string: "-5.5")!)
        XCTAssertFalse(result.hasPrefix("+"))
        XCTAssertTrue(result.hasSuffix("%"))
    }
}
