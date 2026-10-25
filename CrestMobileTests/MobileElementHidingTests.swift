import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileElementHidingTests: XCTestCase {
    // MARK: - Actions - Target identity

    /// A changing label is safe for a stable selector, but never permits a
    /// replaced node or a changed positional target to become a saved rule.
    func testSavingPreviewsKeepsTargetIdentityWhenPageTextChanges() async throws {
        let cases: [(html: String, mutation: String, saves: Bool)] = [
            ("<section id='target'>Before</section>", "document.querySelector('section').textContent = 'After'", true),
            (
                "<section data-testid='target'>Before</section>",
                "document.querySelector('section').textContent = 'After'", true
            ),
            (
                "<section>Before</section><section>Other</section>",
                "document.querySelector('section').textContent = 'After'", false
            ),
            (
                "<section id='target'>Before</section>",
                "document.querySelector('section').outerHTML = '<section id=target>Before</section>'", false
            ),
        ]
        for fixture in cases {
            let (browser, pages, page) = try makePage()
            defer { pages.unloadPages(in: page.spaceID) }
            try await load(fixture.html, in: page)
            try await previewFirstElement(in: page)
            _ = try await page.webView.evaluateJavaScript(fixture.mutation + "; true")

            await page.elementHiding.finish()

            XCTAssertEqual(page.elementHiding.state.entries.count, fixture.saves ? 1 : 0, fixture.html)
            XCTAssertEqual(page.elementHiding.isSelecting, !fixture.saves, fixture.html)
            withExtendedLifetime(browser) {}
        }
    }

    // MARK: - Actions - Document lifetime

    /// A provisional failure leaves the old document usable, but committing a
    /// replacement retires its selection and cannot save its pending targets.
    func testUncommittedNavigationPreservesTheDocumentUntilReplacement() async throws {
        let (browser, pages, page) = try makePage()
        defer { pages.unloadPages(in: page.spaceID) }
        try await load("<section id='target'>Before</section>", in: page)
        let originalOrigin = page.elementHiding.origin
        try await previewFirstElement(in: page)

        page.webView(page.webView, didStartProvisionalNavigation: nil)
        page.webView(page.webView, didFailProvisionalNavigation: nil, withError: URLError(.cancelled))

        XCTAssertTrue(page.elementHiding.isAvailable)
        XCTAssertEqual(page.elementHiding.origin, originalOrigin)
        XCTAssertFalse(page.elementHiding.isSelecting)
        XCTAssertEqual(page.elementHiding.previewCount, 0)
        try await waitUntil {
            try await page.webView.evaluateJavaScript("document.querySelector('section').style.display") as? String
                == ""
        }
        // A rule changed elsewhere must still reach the surviving document.
        try browser.core.send(
            HidePageElement(
                spaceID: page.spaceID, origin: try XCTUnwrap(originalOrigin), selector: "#target",
                tagName: "SECTION", label: "Before", allSpaces: false))
        page.elementHiding.refresh()
        try await waitUntil {
            try await page.webView.evaluateJavaScript("document.querySelector('section').style.display") as? String
                == "none"
        }
        let rule = try XCTUnwrap(page.elementHiding.state.entries.first?.rule)
        page.elementHiding.forget(rule)
        try await waitUntil {
            try await page.webView.evaluateJavaScript("document.querySelector('section').style.display") as? String
                == ""
        }
        try await previewFirstElement(in: page)

        page.webView(page.webView, didCommit: nil)
        await page.elementHiding.finish()

        XCTAssertFalse(page.elementHiding.isAvailable)
        XCTAssertNil(page.elementHiding.origin)
        XCTAssertFalse(page.elementHiding.isSelecting)
        XCTAssertEqual(
            try browser.core.query(GetElementHiding(spaceID: page.spaceID, origin: try XCTUnwrap(originalOrigin)))
                .entries.count, 0)
        try await load("<section id='new'>Replacement</section>", in: page, host: "replacement.crest.test")
        XCTAssertEqual(page.elementHiding.origin?.host, "replacement.crest.test")
        try await previewFirstElement(in: page)
        await page.elementHiding.finish()
        XCTAssertEqual(page.elementHiding.state.entries.count, 1)
    }

    // MARK: - Actions - Fixtures

    /// Creates an in-memory core and an ephemeral WebKit page so selection tests cannot touch browsing data.
    private func makePage() throws -> (BrowserStore, MobileBrowserPageStore, MobileBrowserPage) {
        let tab = TabState.Seed.startPage()
        let space = SpaceState.Seed(name: "Hiding", symbol: "circle", accent: .indigo, folders: [], tabs: [tab])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        pages.present(space: space.id)
        let page = try XCTUnwrap(pages.activePage)
        page.webView.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return (browser, pages, page)
    }

    /// Loads a simulated web origin without network access and waits for the isolated controller to identify it.
    private func load(_ html: String, in page: MobileBrowserPage, host: String = "hiding.crest.test") async throws {
        page.webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://\(host)/"))),
            responseHTML:
                "<html><head><style>section { width: 300px; height: 80px; }</style></head><body>\(html)</body></html>")
        try await waitUntil { page.elementHiding.isAvailable && page.elementHiding.origin?.host == host }
    }

    /// Exercises the document's click interception and native preview acknowledgement before mutating the fixture.
    private func previewFirstElement(in page: MobileBrowserPage) async throws {
        page.elementHiding.start()
        try await waitUntil {
            _ = try await page.webView.evaluateJavaScript(
                """
                (() => {
                    const rect = document.querySelector('section').getBoundingClientRect();
                    window.dispatchEvent(new MouseEvent('click', {clientX:rect.x + 10, clientY:rect.y + 10}));
                    return true;
                })();
                """)
            return page.elementHiding.selection != nil
        }
        let selection = try XCTUnwrap(page.elementHiding.selection)
        let previewed = await page.elementHiding.preview(selection)
        XCTAssertTrue(previewed)
    }

    /// Allows asynchronous WebKit messages to settle within a bounded deadline; reports and throws on timeout.
    private func waitUntil(_ predicate: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while ContinuousClock.now < deadline {
            if try await predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The element-hiding document did not reach the expected state.")
        throw URLError(.timedOut)
    }
}
