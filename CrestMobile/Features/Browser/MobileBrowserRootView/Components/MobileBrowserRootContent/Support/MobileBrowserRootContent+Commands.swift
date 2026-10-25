import SwiftUI

extension MobileBrowserRootContent {
    /// Whether the regular shell shows its overlay palette: one was asked for,
    /// over a selected tab the palette can act on.
    var isCommandPaletteShown: Bool {
        guard model.commandPalette != nil, !presentation.presentsPageOverTabViewer,
            let source = browser.shownTabAssignment
        else {
            return false
        }
        return model.isPaletteSourceAvailable(source)
    }

    /// Which side of the field-to-palette morph holds the shared identity.
    /// Only the regular sidebar sits beside the overlay palette.
    var commandPaletteHandoff: BrowserCommandPaletteHandoff {
        .resolve(
            isPaletteShown: isCommandPaletteShown,
            isFieldOnScreen: navigation.regularSidebarIsPresented,
            animates: BrowserCommandSurfaceMorph.animatesCommandPalette(reduceMotion: reduceMotion)
        )
    }

    func presentArchiveFromCommand() {
        model.revealSidebarForUtilityCommand(presentation: presentation)
        navigation.utilityPresentation.present(.archive)
    }

    func presentHistoryFromCommand() {
        presentation.presentHistory(in: self)
    }

    /// Reveals the sidebar in the current presentation before opening its
    /// download utility, including when a split temporarily put it away.
    func presentDownloadsFromCommand() {
        model.revealSidebarForUtilityCommand(presentation: presentation)
        navigation.utilityPresentation.present(.downloads)
    }

    /// Reuses the window's editing session in either shell. Only the regular
    /// shell supplies a morph namespace; insets keep its overlay within the
    /// page area without changing the draft.
    func commandPaletteLayer(contentInsets: EdgeInsets) -> some View {
        MobileBrowserCommandPaletteLayer(
            model: model.commandPalette,
            morphNamespace: presentation.presentsPageOverTabViewer ? nil : compactChromeNamespace,
            overlayContentInsets: contentInsets
        )
    }
}
