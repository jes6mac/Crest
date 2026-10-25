import UIKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileCommandPaletteEditingTests: XCTestCase {
    /// Recreating the native field preserves the caret after a Unicode prefix,
    /// even when that prefix is marked by an interrupted input composition.
    /// Resuming must insert text without replacing the draft or marked prefix.
    func testReplacementFieldContinuesTheDraftAtItsCaret() throws {
        for isComposing in [false, true] {
            let fixture = makeEditor()
            fixture.field.insertText("café 🧭 test")
            fixture.coordinator.editingChanged()
            let caret = try XCTUnwrap(fixture.field.position(from: fixture.field.beginningOfDocument, offset: 8))
            if isComposing {
                fixture.field.selectedTextRange = fixture.field.textRange(
                    from: fixture.field.beginningOfDocument, to: caret)
                fixture.field.setMarkedText("café 🧭 ", selectedRange: NSRange(location: 0, length: 8))
                XCTAssertNotNil(fixture.field.markedTextRange)
            } else {
                fixture.field.selectedTextRange = fixture.field.textRange(from: caret, to: caret)
            }
            fixture.coordinator.editingChanged()
            XCTAssertEqual(fixture.model.completionEditing.isComposing, isComposing)
            XCTAssertEqual(fixture.field.text, fixture.model.query)

            let replacement = BrowserPlatformCommandPaletteField(
                model: fixture.model, presentation: .overlay, identifier: "command-palette-field", focused: true)
            let coordinator = replacement.makeCoordinator()
            let field = replacement.makeField(coordinator: coordinator)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousKeyWindow = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            let controller = UIViewController()
            window.rootViewController = controller
            field.frame = CGRect(x: 20, y: 100, width: 300, height: 44)
            controller.view.addSubview(field)
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }
            coordinator.focusField()
            XCTAssertTrue(field.isFirstResponder)
            XCTAssertTrue(try XCTUnwrap(field.selectedTextRange).isEmpty)
            field.insertText("nouveau ")
            coordinator.editingChanged()

            XCTAssertEqual(field.text, "café 🧭 nouveau test")
            XCTAssertEqual(fixture.model.query, "café 🧭 nouveau test")
        }
    }

    /// Creates an editor backed by seeded browsing state. Unexpected tab
    /// selection or navigation fails the test, keeping field replacement
    /// separate from submitting the draft.
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
