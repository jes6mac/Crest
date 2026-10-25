import Foundation

extension ElementHidingChanged {
    /// Invalidates scoped rule queries without placing any saved or private rules in shared UI state.
    @MainActor func apply(to state: CoreState) {
        state.elementHidingRevision = revision
    }
}
