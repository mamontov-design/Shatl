import Foundation
import XCTest
@testable import Shatl

final class MaterializedSelectionFootprintTests: XCTestCase {
    func testUnionKeepsAllMaterializedOrdinals() {
        let lhs = MaterializedSelectionFootprint(selectedFileCount: 5, materializedOrdinals: Set([0, 3]))
        let rhs = MaterializedSelectionFootprint(selectedFileCount: 5, materializedOrdinals: Set([1, 4]))

        XCTAssertEqual(lhs.union(rhs).materializedOrdinals, Set([0, 1, 3, 4]))
    }

    func testMissingOrdinalsDetectsPreviouslyKnownFileLoss() {
        let previous = MaterializedSelectionFootprint(selectedFileCount: 4, materializedOrdinals: Set([0, 2, 3]))
        let current = MaterializedSelectionFootprint(selectedFileCount: 4, materializedOrdinals: Set([0, 3]))

        XCTAssertEqual(previous.missingOrdinals(comparedTo: current), Set([2]))
    }
}
