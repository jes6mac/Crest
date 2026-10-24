import Foundation

extension ElementHidingChanged {
    @MainActor func apply(to state: CoreState) {
        state.elementHidingRevision = revision
    }
}
