import UIKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileCommandPaletteEditingTests: XCTestCase {
    func testReplacementFieldContinuesTheDraftAtItsCaret() throws {
        let fixture = makeEditor()
        fixture.field.insertText("café 🧭 test")
        fixture.coordinator.editingChanged()
        let caret = try XCTUnwrap(fixture.field.position(from: fixture.field.beginningOfDocument, offset: 8))
        fixture.field.selectedTextRange = fixture.field.textRange(from: caret, to: caret)
        fixture.coordinator.editingChanged()

        let replacement = BrowserPlatformCommandPaletteField(
            model: fixture.model, presentation: .overlay, identifier: "command-palette-field", focused: true)
        let coordinator = replacement.makeCoordinator()
        let field = replacement.makeField(coordinator: coordinator)
        coordinator.focusField()
        field.insertText("nouveau ")
        coordinator.editingChanged()

        XCTAssertEqual(field.text, "café 🧭 nouveau test")
        XCTAssertEqual(fixture.model.query, "café 🧭 nouveau test")
    }

    private func makeEditor(
        presentation: BrowserCommandPalettePresentation = .overlay,
        openURL: @escaping (URL) -> Bool = { _ in
            XCTFail("Unexpected navigation")
            return false
        }
    ) -> (
        field: BrowserPlatformCommandPaletteField.CompletionField,
        coordinator: BrowserPlatformCommandPaletteField.Coordinator, model: BrowserCommandPaletteModel
    ) {
        let tab = TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let space = SpaceState.Seed(name: "Test", symbol: "globe", accent: .indigo, tabs: [tab])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: tab.id, initialQuery: "",
            commands: nil,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in
                XCTFail("Unexpected navigation")
                return false
            },
            openURL: { _, url, _ in openURL(url) }, dismiss: {})
        let view = BrowserPlatformCommandPaletteField(
            model: model, presentation: presentation, identifier: "command-palette-field", focused: false)
        let coordinator = view.makeCoordinator()
        let field = view.makeField(coordinator: coordinator)
        return (field, coordinator, model)
    }
}
