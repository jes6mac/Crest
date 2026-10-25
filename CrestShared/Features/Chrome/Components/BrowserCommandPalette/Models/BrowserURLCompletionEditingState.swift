import Foundation

/// Tracks native editing without putting the proposed suffix into the query.
struct BrowserURLCompletionEditingState: Equatable {
    private var text = ""
    private var selection = NSRange(location: 0, length: 0)
    private(set) var isComposing = false
    private var suppressed = true

    mutating func update(text: String, selection: NSRange, isComposing: Bool) {
        if text != self.text {
            suppressed = text.utf16.count < self.text.utf16.count
        }
        self.text = text
        self.selection = selection
        self.isComposing = isComposing
    }

    mutating func reject() { suppressed = true }

    /// The caret rests at the end of the text with nothing being composed.
    var isAtEnd: Bool {
        !isComposing && selection == NSRange(location: text.utf16.count, length: 0)
    }

    /// Allows a suffix only for the matching query with an unselected caret
    /// at its UTF-16 end, outside composition and without a prior rejection
    /// or deletion suppressing completion.
    func canPropose(for query: String) -> Bool {
        !suppressed && !isComposing && text == query
            && selection == NSRange(location: query.utf16.count, length: 0)
    }

    /// Returns the saved UTF-16 selection only for matching text outside
    /// IME composition. The native field must validate that it can form
    /// this range in its current document before applying it.
    func selectionForRestoration(of query: String) -> NSRange? {
        guard !isComposing, text == query else { return nil }
        return selection
    }
}
