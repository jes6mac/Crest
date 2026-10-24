import SwiftUI

struct MobileBrowserRootSurface<Compact: View, Regular: View, Palette: View>:
    View, BrowserChromeAnimating
{
    let presentation: MobileBrowserPresentation
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let preferredSidebarWidth: CGFloat
    let isCommandPalettePresented: Bool
    let isURLCopiedFeedbackVisible: Bool
    let pageZoomFeedbackLabel: String?
    let reduceMotion: Bool
    let didPromoteTransientPage: () -> Void
    let compact: Compact
    let regular: (MobileRegularWindowLayout) -> Regular
    let palette: (EdgeInsets) -> Palette
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.browserWindowCornerRadius) private var windowCornerRadius
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement

    private var sidebarOnRight: Bool { BrowserDeviceAppearanceStore.shared.sidebarOnRight }
    private var appearance: BrowserChromeAppearance { .device(windowCornerRadius: windowCornerRadius) }

    private var requiredDetailWidth: CGFloat {
        let count = browser.shownCards.count
        guard count > 1 else { return MobileRegularWindowLayout.minimumDetailWidth }
        let insets = controlPlacement.pageInsets(appearance.pageInsets(docked: true, direction: layoutDirection))
        return CGFloat(count) * BrowserSplitLayoutMetrics.minimumCardWidth
            + CGFloat(count - 1) * BrowserSplitLayoutMetrics.interCardGap
            + insets.leading + insets.trailing
    }

    var body: some View {
        ZStack {
            if !presentation.presentsPageOverTabViewer {
                SpaceBackdropBlend(
                    spaces: browser.availableSpaces,
                    selectedSpace: browser.shownSpace
                ) {
                    BrowserWindowAtmosphere(space: $0)
                }
                .ignoresSafeArea()
            }

            if presentation.presentsPageOverTabViewer {
                compact
                    .allowsHitTesting(!isCommandPalettePresented || navigation.compactShowsPage)
                    .accessibilityHidden(isCommandPalettePresented && !navigation.compactShowsPage)
                    .overlay {
                        if !navigation.compactShowsPage { palette(EdgeInsets()) }
                    }
            } else {
                GeometryReader { proxy in
                    let fold = MobileBrowserFold.dividing(proxy)
                    let layout = MobileRegularWindowLayout(
                        availableWidth: proxy.size.width,
                        preferredSidebarWidth: preferredSidebarWidth,
                        foldSpan: fold?.span(across: proxy.frame(in: .global), direction: layoutDirection),
                        sidebarEdge: BrowserChromeAppearance.sidebarEdge(
                            onRight: sidebarOnRight, in: layoutDirection),
                        presentsColumns: browser.shownCards.count > 1,
                        requiredDetailWidth: requiredDetailWidth,
                        sharesTopBandWithStatusBar: MobileBrowserFold.isFoldable(proxy)
                            && proxy.size.height > proxy.size.width
                    )
                    regular(layout)
                        .environment(\.mobileBrowserFold, fold)
                        .allowsHitTesting(!isCommandPalettePresented)
                        .accessibilityHidden(isCommandPalettePresented)
                        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
                            GeometryReader { pageProxy in
                                let rect = anchor.map { pageProxy[$0] } ?? CGRect(origin: .zero, size: pageProxy.size)
                                palette(
                                    BrowserChromeAppearance.contentInsets(
                                        for: rect, in: pageProxy.size, direction: layoutDirection))
                            }
                        }
                }
            }
        }
        .overlay {
            if presentation.presentsPageOverTabViewer && !navigation.compactShowsPage {
                MobileTransientBrowsingOverlay(
                    browser: browser,
                    pages: pages,
                    coordinator: transientBrowsing,
                    spaceAccess: spaceAccess,
                    didPromote: didPromoteTransientPage,
                    showsPeeks: false
                )
            }
        }
        .overlay(alignment: .top) {
            if !presentation.presentsPageOverTabViewer || !navigation.compactShowsPage {
                MobileURLCopyFeedback(
                    isVisible: isURLCopiedFeedbackVisible,
                    topPadding: presentation.overlayTopPadding
                )
                if let pageZoomFeedbackLabel {
                    MobilePageZoomFeedback(
                        label: pageZoomFeedbackLabel,
                        topPadding: presentation.overlayTopPadding
                    )
                }
            }
        }
        .onChange(of: transientBrowsing.orphanedPeeks(in: browser), initial: true) {
            transientBrowsing.reconcilePeeks(in: browser)
        }
        .onChange(of: transientBrowsing.peekRequests, initial: true) {
            pages.retainPeekPages(for: transientBrowsing.peekRequests)
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .animation(
            BrowserCommandSurfaceMorph.commandPaletteAnimation(reduceMotion: reduceMotion),
            value: isCommandPalettePresented
        )
    }
}
