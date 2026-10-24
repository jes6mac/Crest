import SwiftUI

struct BrowserElementHidingToolbar: View {
    // MARK: - Variables

    let count: Int
    let status: String?
    let isPrivate: Bool
    let canChangeGlobal: Bool
    let isBusy: Bool
    @Binding var allSpaces: Bool
    let undo: () -> Void
    let cancel: () -> Void
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Presentation

    var body: some View {
        VStack(spacing: 8) {
            if let status {
                Text(status)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: CrestRadius.control))
                    .accessibilityIdentifier("element-hiding-status")
            }
            HStack(spacing: 0) {
                Button("Cancel", systemImage: "xmark", action: cancel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(CrestChromeButtonStyle())
                    .accessibilityIdentifier("element-hiding-cancel")
                    .disabled(isBusy)
                Button("Restore Last", systemImage: "arrow.uturn.backward", action: undo)
                    .labelStyle(.iconOnly)
                    .buttonStyle(CrestChromeButtonStyle())
                    .disabled(count == 0 || isBusy)
                    .accessibilityIdentifier("element-hiding-undo")
                Menu {
                    Picker("Hide Elements", selection: $allSpaces) {
                        Text("This Space").tag(false)
                        Text("All Spaces").tag(true)
                    }
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(isPrivate ? "Temporary" : allSpaces ? "All Spaces" : "This Space")
                            if canChangeGlobal { Image(systemName: "chevron.down").font(.caption2) }
                        }
                        .font(.caption.weight(.semibold))
                        if count == 0 {
                            Text("Select an element").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("\(count) hidden")
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(CrestChromeButtonStyle(controlSize: nil))
                .disabled(!canChangeGlobal || isBusy)
                .accessibilityIdentifier("element-hiding-scope")
                Button("Done", action: finish)
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.glassProminent)
                    .tint(CrestBrandPalette.ink)
                    .controlSize(.regular)
                    .disabled(isBusy)
                    .accessibilityIdentifier("element-hiding-done")
                    .padding(.leading, 6)
            }
            .padding(6)
            .glassEffect(.regular.interactive(), in: .capsule)
            .animation(CrestMotion.selection.unlessReducingMotion(reduceMotion), value: count)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("element-hiding-toolbar")
    }
}

#if DEBUG
    #Preview("Hide several elements") {
        @Previewable @State var allSpaces = false
        BrowserElementHidingToolbar(
            count: 2, status: nil, isPrivate: false, canChangeGlobal: true, isBusy: false,
            allSpaces: $allSpaces, undo: {}, cancel: {}, finish: {}
        )
        .padding().frame(width: 390)
    }
#endif
