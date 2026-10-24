import SwiftUI

struct BrowserElementHidingSelectionControl: View {
    // MARK: - Variables

    let label: String
    let canSelectParent: Bool
    let hide: () -> Void
    let selectParent: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        HStack(spacing: 8) {
            Button(action: hide) {
                Label("Hide", systemImage: "eye.slash")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 34)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("Hide \(label)"))
            .accessibilityIdentifier("element-hiding-hide")
            if canSelectParent {
                Button("Select Parent", systemImage: "arrow.up.left.and.arrow.down.right", action: selectParent)
                    .labelStyle(.iconOnly)
                    .buttonStyle(CrestChromeButtonStyle())
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityIdentifier("element-hiding-parent")
            }
        }
    }
}

#if DEBUG
    #Preview("Selected element") {
        BrowserElementHidingSelectionControl(label: "Newsletter", canSelectParent: true, hide: {}, selectParent: {})
            .padding(30)
    }
#endif
