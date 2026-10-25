import Foundation
import Observation

// MARK: - Types

struct BrowserElementHidingMessage: Decodable {
    enum Kind: String, Decodable { case ready, selected, unavailable, cancelled }
    let kind: Kind
    let documentID: String
    let selectionToken: String?
    let selector: String?
    let tagName: String?
    let label: String?
    let canSelectParent: Bool?
    let bounds: BrowserElementHidingBounds?
}

struct BrowserElementHidingBounds: Decodable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let viewportWidth: Double
}

struct BrowserElementHidingSelection: Equatable {
    let sessionID: String
    let selector: String
    let tagName: String
    let label: String
    let canSelectParent: Bool
    let bounds: BrowserElementHidingBounds
}

private struct BrowserHiddenElement: Encodable {
    let selector: String
    let tagName: String
    let label: String
}

/// Keeps previews bound to one document until Finish saves the batch through the core.
/// Saved-rule management sends its changes immediately, independently of selection.
@MainActor
@Observable
final class BrowserElementHidingSession {
    // MARK: - Types

    typealias Evaluate = @MainActor (String, [String: Any]) async throws -> Any?

    // MARK: - Variables

    let spaceID: UUID
    private let core: CrestCore
    private(set) var origin: SiteOrigin?
    private(set) var selection: BrowserElementHidingSelection?
    private(set) var isSelecting = false
    private(set) var isBusy = false
    private var previews: [BrowserHiddenElement] = []
    var hidesAcrossSpaces = false
    var showsRules = false
    private(set) var status: String?
    @ObservationIgnored private var evaluate: Evaluate?
    @ObservationIgnored private var documentID: String?
    @ObservationIgnored private var selectionToken: String?
    @ObservationIgnored private var revision = 0
    private(set) var isAvailable = false

    var previewCount: Int { previews.count }

    var state: ElementHidingState {
        _ = core.state.elementHidingRevision
        guard let origin else { return ElementHidingState(isPrivate: false, canChangeGlobal: false, entries: []) }
        return (try? core.query(GetElementHiding(spaceID: spaceID, origin: origin)))
            ?? ElementHidingState(isPrivate: false, canChangeGlobal: false, entries: [])
    }

    // MARK: - Initializers

    /// Binds rule queries and intents to one Space; document access is supplied later by the engine adapter.
    init(core: CrestCore, spaceID: UUID) {
        self.core = core
        self.spaceID = spaceID
    }

    // MARK: - Actions - Document

    /// Attaches the adapter for isolated document commands and observes rule changes from other Spaces.
    func connect(evaluate: @escaping Evaluate) {
        self.evaluate = evaluate
        observeChanges()
    }

    /// Accepts messages from an origin verified by the adapter. Selection messages must also match
    /// the current document and selection token, with bounded text and finite viewport coordinates.
    func receive(_ message: BrowserElementHidingMessage, origin: SiteOrigin) {
        guard UUID(uuidString: message.documentID) != nil else { return }
        switch message.kind {
        case .ready:
            if documentID != message.documentID || self.origin != origin {
                cancel()
            }
            documentID = message.documentID
            self.origin = origin
            isAvailable = true
            refresh()
        case .selected:
            guard isSelecting, !isBusy, message.documentID == documentID, self.origin == origin,
                message.selectionToken == selectionToken,
                let selector = message.selector, selector.count <= 1_024,
                let tagName = message.tagName, tagName.count <= 64,
                let label = message.label, label.count <= 80,
                let bounds = message.bounds,
                [bounds.x, bounds.y, bounds.width, bounds.height, bounds.viewportWidth].allSatisfy(\.isFinite),
                bounds.width > 0, bounds.height > 0, bounds.viewportWidth > 0
            else { return }
            selection = BrowserElementHidingSelection(
                sessionID: message.selectionToken ?? "", selector: selector, tagName: tagName, label: label,
                canSelectParent: message.canSelectParent == true, bounds: bounds)
            status = nil
        case .unavailable:
            guard message.documentID == documentID, message.selectionToken == selectionToken else { return }
            selection = nil
            status = String(localized: "This element cannot be identified reliably.")
        case .cancelled:
            guard message.documentID == documentID else { return }
            cancel()
        }
    }

    /// Cancels previews while the old document still owns the page. A stopped
    /// load, provisional failure or download may never replace that document.
    func navigationStarted() {
        cancel()
        showsRules = false
    }

    /// Retires document identity only after replacement or adapter teardown.
    func invalidateDocument() {
        navigationStarted()
        documentID = nil
        origin = nil
        isAvailable = false
    }

    /// Cancels previews, retires document identity and releases the adapter when the page is removed.
    func disconnect() {
        invalidateDocument()
        evaluate = nil
    }

    /// Sends the effective hidden rules for this Space and origin. A monotonically increasing revision
    /// lets the document ignore an older update that arrives after a newer one.
    func refresh() {
        guard let documentID, let evaluate else { return }
        let rules = state.entries.filter(\.isHidden).map {
            BrowserHiddenElement(selector: $0.rule.selector, tagName: $0.rule.tagName, label: $0.rule.label)
        }
        guard let data = try? JSONEncoder().encode(rules), let json = String(data: data, encoding: .utf8) else {
            return
        }
        revision += 1
        let arguments: [String: Any] = ["documentID": documentID, "revision": revision, "rules": json]
        Task {
            _ = try? await evaluate(
                "return globalThis.__crestElementHiding?.update(documentID, revision, JSON.parse(rules));", arguments)
        }
    }

    /// Rearms observation after each core revision so changes elsewhere reach this document
    /// without publishing private rules in the shared read model.
    private func observeChanges() {
        guard evaluate != nil else { return }
        withObservationTracking {
            _ = core.state.elementHidingRevision
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeChanges()
                self?.refresh()
            }
        }
    }

    // MARK: - Actions - Selection

    /// Starts an empty, Space-local preview batch with a fresh token. A delayed adapter reply
    /// cannot restart a session that has already been cancelled or replaced.
    func start() {
        guard isAvailable, !isSelecting, let documentID, let evaluate else { return }
        let token = UUID().uuidString
        selectionToken = token
        selection = nil
        previews = []
        hidesAcrossSpaces = false
        status = nil
        isBusy = false
        isSelecting = true
        Task {
            guard self.selectionToken == token else { return }
            let started = try? await evaluate(
                "return globalThis.__crestElementHiding?.start(documentID, token);",
                ["documentID": documentID, "token": token])
            guard self.selectionToken == token else { return }
            if started as? Bool != true {
                cancel()
                status = String(localized: "Reload this page to select an element.")
            }
        }
    }

    /// Asks the current document to select a reliably identifiable ancestor while no preview is in flight.
    func selectParent() {
        guard !isBusy, let documentID, let selectionToken, let evaluate else { return }
        Task {
            _ = try? await evaluate(
                "return globalThis.__crestElementHiding?.parent(documentID, token);",
                ["documentID": documentID, "token": selectionToken])
        }
    }

    /// Restores unsaved previews in the document and invalidates pending selection replies.
    /// Previously saved rules remain effective.
    func cancel() {
        if let documentID, let selectionToken, let evaluate {
            Task {
                _ = try? await evaluate(
                    "globalThis.__crestElementHiding?.stop(documentID, token);",
                    ["documentID": documentID, "token": selectionToken])
            }
        }
        selectionToken = nil
        selection = nil
        previews = []
        isSelecting = false
        isBusy = false
        status = nil
    }

    /// Temporarily hides the expected selection without saving a rule. Returns false if the
    /// selection, document or token changed while the adapter was working.
    func preview(_ expected: BrowserElementHidingSelection) async -> Bool {
        guard !isBusy, selection?.selector == expected.selector, selectionToken == expected.sessionID,
            let documentID, let selectionToken, let evaluate
        else { return false }
        isBusy = true
        defer { if self.selectionToken == selectionToken { isBusy = false } }
        do {
            let hidden = try await evaluate(
                "return globalThis.__crestElementHiding?.preview(documentID, token, selector);",
                ["documentID": documentID, "token": selectionToken, "selector": expected.selector])
            guard self.documentID == documentID, self.selectionToken == selectionToken else { return false }
            guard hidden as? Bool == true else {
                selection = nil
                status = String(localized: "The page changed. Select the element again.")
                return false
            }
            previews.append(
                BrowserHiddenElement(selector: expected.selector, tagName: expected.tagName, label: expected.label))
            selection = nil
            status = nil
            return true
        } catch {
            if self.selectionToken == selectionToken { status = String(localized: "This element could not be hidden.") }
            return false
        }
    }

    /// Restores the last unsaved element only after the matching document confirms the undo.
    /// Keeps the continuous selection session open.
    func undo() async {
        guard !isBusy, !previews.isEmpty, let documentID, let selectionToken, let evaluate else { return }
        isBusy = true
        defer { if self.selectionToken == selectionToken { isBusy = false } }
        let restored = try? await evaluate(
            "return globalThis.__crestElementHiding?.undo(documentID, token);",
            ["documentID": documentID, "token": selectionToken])
        guard self.selectionToken == selectionToken, restored as? Bool == true else { return }
        previews.removeLast()
        selection = nil
        status = nil
    }

    /// Revalidates every preview, then saves the batch in one core intent. Invalid or rejected
    /// batches stay open for undo or cancellation. Committed rules reach the document before previews end.
    func finish() async {
        guard !isBusy, let origin, let documentID, let selectionToken, let evaluate else { return }
        if previews.isEmpty {
            cancel()
            return
        }
        isBusy = true
        defer { if self.selectionToken == selectionToken { isBusy = false } }
        do {
            let valid = try await evaluate(
                "return globalThis.__crestElementHiding?.validatePreviews(documentID, token);",
                ["documentID": documentID, "token": selectionToken])
            guard self.documentID == documentID, self.selectionToken == selectionToken else { return }
            guard valid as? Bool == true else {
                status = String(localized: "The page changed. Undo or cancel this selection.")
                return
            }
            try core.send(
                HidePageElements(
                    spaceID: spaceID, origin: origin,
                    targets: previews.map {
                        ElementHidingTarget(selector: $0.selector, tagName: $0.tagName, label: $0.label)
                    },
                    allSpaces: hidesAcrossSpaces))
            // Deliver the committed read model before removing the temporary previews.
            let rules = state.entries.filter(\.isHidden).map {
                BrowserHiddenElement(selector: $0.rule.selector, tagName: $0.rule.tagName, label: $0.rule.label)
            }
            let data = try JSONEncoder().encode(rules)
            let json = String(decoding: data, as: UTF8.self)
            revision += 1
            _ = try? await evaluate(
                "globalThis.__crestElementHiding?.update(documentID, revision, JSON.parse(rules)); globalThis.__crestElementHiding?.stop(documentID, token);",
                ["documentID": documentID, "token": selectionToken, "revision": revision, "rules": json])
            guard self.selectionToken == selectionToken else { return }
            cancel()
        } catch {
            if self.selectionToken == selectionToken {
                status = String(localized: "This selection could not be saved.")
            }
        }
    }

    // MARK: - Actions - Rules

    /// Restores the element in this Space, using an exception for a global rule or deleting a local rule.
    func show(_ rule: ElementHidingRule) { perform(ShowPageElement(spaceID: spaceID, ruleID: rule.id)) }
    /// Removes this Space's exception so the inherited global rule hides the element again.
    func follow(_ rule: ElementHidingRule) { perform(FollowPageElementRule(spaceID: spaceID, ruleID: rule.id)) }
    /// Requests deletion of the saved rule; the core enforces ownership and private-session restrictions.
    func forget(_ rule: ElementHidingRule) { perform(ForgetPageElementRule(spaceID: spaceID, ruleID: rule.id)) }

    /// Applies a saved-rule action through the core and refreshes the document, or exposes a recoverable status.
    private func perform(_ intent: some Intent) {
        do {
            try core.send(intent)
            status = nil
            refresh()
        } catch {
            status = String(localized: "This rule could not be changed.")
        }
    }
}
