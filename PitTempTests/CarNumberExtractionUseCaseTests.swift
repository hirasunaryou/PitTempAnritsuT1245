import XCTest
@testable import PitTemp

final class CarNumberExtractionUseCaseTests: XCTestCase {

    func testExtractsTrailingDigitsAsCarNumber() {
        let useCase = CarNumberExtractionUseCase()
        let result = useCase.extract(from: "Team Phoenix 018")

        XCTAssertEqual(result.carNumber, "018")
        XCTAssertEqual(result.cleanedCarText, "Team Phoenix 018")
        XCTAssertEqual(result.memoText, "Team Phoenix 018")
    }

    func testNormalizesWhitespaceWhenNoDigitsPresent() {
        let useCase = CarNumberExtractionUseCase()
        let result = useCase.extract(from: "  Super  GT   car  ")

        XCTAssertEqual(result.carNumber, "")
        XCTAssertEqual(result.cleanedCarText, "Super GT car")
        XCTAssertEqual(result.memoText, "Super GT car")
    }
}
