import XCTest
@testable import Escudo

final class CategoriserTests: XCTestCase {
    let categoriser = Categoriser()

    func makeTx(description: String) -> Transaction {
        Transaction(
            accountID: UUID(),
            date: Date(),
            amount: -10,
            currency: "EUR",
            type: .debit,
            rawDescription: description
        )
    }

    func testGroceries() {
        XCTAssertEqual(categoriser.categorise(makeTx(description: "CONTINENTE BELEM")), "Groceries")
    }

    func testTransport() {
        XCTAssertEqual(categoriser.categorise(makeTx(description: "Uber trip receipt")), "Transport")
    }

    func testSubscription() {
        XCTAssertEqual(categoriser.categorise(makeTx(description: "NETFLIX.COM")), "Subscriptions")
    }

    func testFallthrough() {
        XCTAssertEqual(categoriser.categorise(makeTx(description: "RANDOM MERCHANT XYZ")), "Other")
    }

    func testDividend() {
        XCTAssertEqual(categoriser.categorise(makeTx(description: "Dividend AAPL")), "Dividends")
    }
}
