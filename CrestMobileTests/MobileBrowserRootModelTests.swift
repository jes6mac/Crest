import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserRootModelTests: XCTestCase {
    func testAddressDraftSurvivesPresentationChangesWithoutNavigating() throws {
        let space = makeSpace(index: 10)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .regular)
        fixture.model.presentCommandPalette(mode: .editLocation("https://example.com/"))
        let palette = try XCTUnwrap(fixture.model.commandPalette)
        palette.query = "essai pliage Crest"
        let before = fixture.browser.sessionSeed

        for presentation in [MobileBrowserPresentation.compact, .regular, .compact] {
            fixture.model.presentationChanged(to: presentation)
            fixture.model.reconcileCommandPalette()
            XCTAssertTrue(fixture.model.commandPalette === palette)
            XCTAssertEqual(fixture.model.commandPalette?.query, "essai pliage Crest")
            XCTAssertEqual(fixture.browser.sessionSeed, before)
        }

        palette.dismiss()
        XCTAssertNil(fixture.model.commandPalette)
        fixture.model.presentCommandPalette(mode: .editLocation("https://example.com/"))
        XCTAssertEqual(fixture.model.commandPalette?.query, "https://example.com/")
    }

    func testAddressDraftDoesNotFollowAnotherTabOrProfile() throws {
        var space = makeSpace(index: 10)
        let otherTab = TabState.Seed(title: "Second", url: URL(string: "https://example.org/"), placement: .current)
        space.tabs.append(otherTab)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentCommandPalette(mode: .editLocation("private draft"))
        XCTAssertNotNil(fixture.model.commandPalette)
        let previous = fixture.model.selectionSnapshot

        fixture.browser.selectTab(otherTab.id)
        fixture.model.synchronizeSelection(from: previous, to: fixture.model.selectionSnapshot)
        XCTAssertNil(fixture.model.commandPalette)

        fixture.model.presentCommandPalette(mode: .editLocation("another draft"))
        XCTAssertNotNil(fixture.model.commandPalette)
        let beforeProfile = fixture.model.selectionSnapshot
        fixture.browser.replaceProfileForTesting(of: space.id, with: UUID())
        fixture.model.synchronizeSelection(from: beforeProfile, to: fixture.model.selectionSnapshot)
        XCTAssertNil(fixture.model.commandPalette)
    }

    func testLockImmediatelyRevokesRetainedPageActionsBeforeReconciliation() async throws {
        var space = makeSpace(index: 52)
        space.settings.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(authenticator: MobileRootDeviceAuthenticator())
        let fixture = makeFixture(
            spaces: [space], selectedSpaceID: space.id,
            startupBehavior: .lastActiveTab, spaceAccess: access
        )
        let unlocked = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(space.id)))
        XCTAssertTrue(unlocked)
        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()
        let page = try XCTUnwrap(fixture.model.selectedPage)
        let actions = try XCTUnwrap(fixture.model.selectedPageActions)
        XCTAssertTrue(actions.isAvailable)
        let session = fixture.browser.sessionSeed

        fixture.model.presentCommandPalette(mode: .editLocation("draft in protected space"))
        XCTAssertNotNil(fixture.model.commandPalette)
        access.lock(space.id)
        actions.presentFind()
        fixture.model.synchronizePageMetadata(isAddressEditing: false)

        XCTAssertTrue(fixture.pages.activePage === page)
        XCTAssertNil(fixture.model.selectedPage)
        XCTAssertFalse(actions.isAvailable)
        XCTAssertNil(actions.pageAssignment)
        XCTAssertNil(actions.activeURL)
        XCTAssertFalse(page.isFindPresented)
        XCTAssertEqual(fixture.browser.sessionSeed, session)

        fixture.model.reconcileCommandPalette()
        XCTAssertNil(fixture.model.commandPalette)

        let unlockedAgain = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(space.id)))
        XCTAssertTrue(unlockedAgain)
        XCTAssertTrue(actions.isAvailable)
        XCTAssertTrue(actions.activePage === page)
    }

    private func makeFixture(
        spaces: [SpaceState.Seed],
        selectedSpaceID: UUID,
        browsingMode: BrowserBrowsingMode = .standard,
        startupBehavior: StartupBehavior,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController()
    ) -> MobileBrowserRootFixture {
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: spaces),
            showing: selectedSpaceID,
            // Every Space shows its first tab, as a window restoring them would.
            tabs: Dictionary(
                uniqueKeysWithValues: spaces.compactMap { space in space.tabs.first.map { (space.id, $0.id) } }),
            browsingMode: browsingMode,
            core: .hostingPages(contentRuleLists: EmptyMobileRootContentRuleListProvider())
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true
        )
        let navigation = MobileBrowserNavigationState()
        browser.attachSpaceAccess(spaceAccess)
        let model = MobileBrowserRootModel(
            browser: browser,
            pages: pages,
            navigation: navigation,
            spaceAccess: spaceAccess,
            windowState: nil,
            startupBehavior: startupBehavior,
            persistedSidebarWidth: MobileBrowserRootLayout.defaultRegularSidebarWidth
        )
        return MobileBrowserRootFixture(
            browser: browser,
            pages: pages,
            navigation: navigation,
            model: model
        )
    }

    private func makeSpace(index: Int) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage(
            id: fixedUUID(index * 10 + 1),
            placement: .current
        )
        return SpaceState.Seed(
            id: fixedUUID(index * 10 + 2),
            profileID: fixedUUID(index * 10 + 3),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012x",
                value
            )
        )!
    }
}

@MainActor
private struct MobileBrowserRootFixture {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let model: MobileBrowserRootModel
}

@MainActor
private final class EmptyMobileRootContentRuleListProvider:
    BrowserContentRuleListProviding
{
    func balancedRuleLists() async throws -> [WKContentRuleList] { [] }
}

@MainActor
private final class MobileRootDeviceAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason: String) async throws -> Bool { true }
}
