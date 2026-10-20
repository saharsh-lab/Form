import XCTest
@testable import FormCore

final class TextSearchTests: XCTestCase {

    private let locale = Locale(identifier: "en_GB")

    func testCaseAndDiacriticInsensitivePartialMatch() {
        XCTAssertNotNil(TextSearch.match("Crème fraîche", query: "creme", locale: locale))
        XCTAssertNotNil(TextSearch.match("Greek Yoghurt", query: "YOG", locale: locale))
        XCTAssertNil(TextSearch.match("Greek Yoghurt", query: "milk", locale: locale))
    }

    func testAllTermsMustMatchInAnyOrder() {
        XCTAssertNotNil(TextSearch.match("Yoghurt, Greek style", query: "greek yog", locale: locale))
        XCTAssertNil(TextSearch.match("Yoghurt, natural", query: "greek yog", locale: locale))
    }

    func testMatchQualityOrdering() {
        XCTAssertEqual(TextSearch.match("Oats", query: "oats", locale: locale), .exact)
        XCTAssertEqual(TextSearch.match("Oat milk", query: "oat", locale: locale), .prefix)
        XCTAssertEqual(TextSearch.match("Rolled oats", query: "oat", locale: locale), .wordPrefix)
        XCTAssertEqual(TextSearch.match("Goat cheese", query: "oat", locale: locale), .contains)
    }

    func testRankOrdersByQualityThenName() {
        let names = ["Goat cheese", "Rolled oats", "Oat milk", "Oats", "Banana"]
        XCTAssertEqual(TextSearch.rank(names, query: "oat", name: { $0 }, locale: locale),
                       ["Oat milk", "Oats", "Rolled oats", "Goat cheese"])
    }

    func testEmptyQueryKeepsEverythingInOrder() {
        let names = ["b", "a"]
        XCTAssertEqual(TextSearch.rank(names, query: "  ", name: { $0 }, locale: locale), names)
    }
}
