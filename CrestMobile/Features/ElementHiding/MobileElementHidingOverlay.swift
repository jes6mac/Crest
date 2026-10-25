import SwiftUI
import WebKit

/// Binds page coordinates and a bounded, memory-only WebKit snapshot to native controls.
struct MobileElementHidingOverlay: View {
    // MARK: - Variables

    let page: MobileBrowserPage
    let viewport: MobileBrowserPageViewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: MobileElementHidingSnapshot?
    @State private var progress: CGFloat = 0
    @State private var isCapturing = false

    // MARK: - Actions - Presentation

    var body: some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size).inset(by: viewport.webViewFrameInsets)
            let visible = frame.inset(by: viewport.chromeOverlayInsets)
            ZStack(alignment: .topLeading) {
                if let selection = page.elementHiding.selection, page.elementHiding.isSelecting, !isCapturing {
                    let rect = selectionFrame(selection, pageFrame: frame).intersection(visible)
                    if !rect.isNull, rect.width > 1, rect.height > 1 {
                        RoundedRectangle(cornerRadius: CrestRadius.control)
                            .strokeBorder(.tint, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        BrowserElementHidingSelectionControl(
                            label: selection.label, canSelectParent: selection.canSelectParent,
                            hide: { Task { await hide(selection, pageFrame: frame, visible: visible) } },
                            selectParent: page.elementHiding.selectParent
                        )
                        .disabled(page.elementHiding.isBusy)
                        .position(
                            x: min(max(rect.midX, visible.minX + 104), visible.maxX - 104),
                            y: min(max(rect.midY, visible.minY + 26), visible.maxY - 26)
                        )
                        .transition(.opacity)
                    }
                }
                if let snapshot {
                    snapshot.render(progress: progress, reduceMotion: reduceMotion)
                        .id(snapshot.id)
                        .onAppear {
                            withAnimation(reduceMotion ? CrestMotion.reducedMotionFade : CrestMotion.elementDissolve) {
                                progress = 1
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .animation(
            CrestMotion.selection.unlessReducingMotion(reduceMotion), value: page.elementHiding.selection?.selector
        )
        .onChange(of: page.elementHiding.isSelecting) {
            if !page.elementHiding.isSelecting { snapshot = nil }
        }
    }

    // MARK: - Actions - Preview

    /// Converts CSS viewport coordinates to the native page frame, including the current page scale.
    private func selectionFrame(_ selection: BrowserElementHidingSelection, pageFrame: CGRect) -> CGRect {
        let bounds = selection.bounds
        let scale = pageFrame.width / bounds.viewportWidth
        return CGRect(
            x: pageFrame.minX + bounds.x * scale, y: pageFrame.minY + bounds.y * scale,
            width: bounds.width * scale, height: bounds.height * scale)
    }

    /// Captures only the visible portion, then asks the session to preview the same selection.
    /// A snapshot failure still permits hiding; successful animation images are discarded after the transition.
    private func hide(_ selection: BrowserElementHidingSelection, pageFrame: CGRect, visible: CGRect) async {
        guard !isCapturing, !page.elementHiding.isBusy else { return }
        isCapturing = true
        defer { isCapturing = false }
        let rect = selectionFrame(selection, pageFrame: pageFrame).intersection(visible)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect.offsetBy(dx: -pageFrame.minX, dy: -pageFrame.minY)
        configuration.snapshotWidth = NSNumber(value: min(rect.width, 800))
        let image = try? await page.webView.takeSnapshot(configuration: configuration)
        guard page.elementHiding.isSelecting, page.elementHiding.selection?.selector == selection.selector else {
            return
        }
        guard await page.elementHiding.preview(selection) else { return }
        if let image, let captured = MobileElementHidingSnapshot(image: image, frame: rect) {
            let identity = captured.id
            progress = 0
            snapshot = captured
            try? await Task.sleep(
                for: .seconds(
                    reduceMotion ? CrestMotion.reducedMotionFadeTransition : CrestMotion.elementDissolveTransition))
            if snapshot?.id == identity { snapshot = nil }
        }
    }
}
