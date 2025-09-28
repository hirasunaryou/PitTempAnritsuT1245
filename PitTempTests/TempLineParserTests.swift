//
//  TempLineParserTests.swift
//  Tests for Core/Parsing/TempLineParser
//

import XCTest
@testable import PitTemp   // ← 実プロジェクトのモジュール名に置き換え（例：PitTemp）

final class TempLineParserTests: XCTestCase {

    func test_parse_valid_integer() throws {
        let v = try TempLineParser.parse("023")
        XCTAssertEqual(v, 23.0, accuracy: 1e-6)
    }

    func test_parse_negative_decimal() throws {
        let v = try TempLineParser.parse("-12.5")
        XCTAssertEqual(v, -12.5, accuracy: 1e-6)
    }

    func test_parse_with_spaces() throws {
        let v = try TempLineParser.parse("   45.0  ")
        XCTAssertEqual(v, 45.0, accuracy: 1e-6)
    }

    func test_parse_comma_decimal() throws {
        let v = try TempLineParser.parse("18,7")
        XCTAssertEqual(v, 18.7, accuracy: 1e-6)
    }

    func test_parse_extra_noise_prefix_suffix() throws {
        let v = try TempLineParser.parse("T=27.3 C")
        XCTAssertEqual(v, 27.3, accuracy: 1e-6)
    }

    func test_parse_no_number() {
        XCTAssertThrowsError(try TempLineParser.parse("NaN ---")) { err in
            XCTAssertEqual(err as? TempParseError, .noNumber)
        }
    }

    func test_parse_out_of_range() {
        XCTAssertThrowsError(try TempLineParser.parse("999.0")) { err in
            if case let TempParseError.outOfRange(r) = err {
                XCTAssertEqual(r.lowerBound, -30.0)
                XCTAssertEqual(r.upperBound, 200.0)
            } else {
                XCTFail("unexpected error")
            }
        }
    }

    func test_parse_disable_range_check() throws {
        let v = try TempLineParser.parse("999.0", clamp: nil)
        XCTAssertEqual(v, 999.0, accuracy: 1e-6)
    }
}
