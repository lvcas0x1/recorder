import XCTest
@testable import DesignSystem

final class InterfaceFontTests: XCTestCase {
    func testNilAndEmptyUseSystemFont() {
        XCTAssertNil(InterfaceFont.resolvedFamily(nil))
        XCTAssertNil(InterfaceFont.resolvedFamily(""))
    }

    func testUnknownFamilyFallsBackToSystemFont() {
        XCTAssertNil(InterfaceFont.resolvedFamily("No Such Font Family 12345"))
    }

    func testInstalledFamilyIsKept() throws {
        let family = try XCTUnwrap(NSFontManager.shared.availableFontFamilies.first)
        XCTAssertEqual(InterfaceFont.resolvedFamily(family), family)
    }
}
