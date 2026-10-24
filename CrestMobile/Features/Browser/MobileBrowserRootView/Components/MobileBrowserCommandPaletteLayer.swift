import SwiftUI

/// Both mobile presentations render the window's same editing session.
struct MobileBrowserCommandPaletteLayer: View {
    // MARK: - Variables

    let model: BrowserCommandPaletteModel?
    let morphNamespace: Namespace.ID?
    let overlayContentInsets: EdgeInsets

    var body: some View {
        if let model, model.isCompletionSourceAvailable {
            BrowserCommandPaletteContent(
                model: model,
                presentation: .overlay,
                morphNamespace: morphNamespace,
                overlayContentLeadingInset: 0,
                overlayContentInsets: overlayContentInsets
            )
            .id(ObjectIdentifier(model))
            .transition(.browserCommandPaletteOverlay)
            .zIndex(MobileBrowserRootLayout.paletteLayer)
        }
    }
}
