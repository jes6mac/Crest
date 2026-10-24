import SwiftUI

struct BrowserHiddenElementsSheet: View {
    // MARK: - Variables

    let session: BrowserElementHidingSession
    @Environment(\.dismiss) private var dismiss

    // MARK: - Actions - Presentation

    var body: some View {
        NavigationStack {
            let state = session.state
            List {
                if state.entries.isEmpty {
                    ContentUnavailableView("No Hidden Elements", systemImage: "eye")
                }
                let global = state.entries.filter { $0.rule.spaceID == nil }
                if !global.isEmpty {
                    Section("All Spaces") {
                        ForEach(global, id: \.rule.id) { entry in
                            row(entry, canRemove: state.canChangeGlobal)
                        }
                    }
                }
                let local = state.entries.filter { $0.rule.spaceID != nil }
                if !local.isEmpty {
                    Section(state.isPrivate ? "Private Session" : "This Space") {
                        ForEach(local, id: \.rule.id) { entry in row(entry, canRemove: true) }
                    }
                }
                if state.isPrivate {
                    Section {
                        Text("Changes in Private Browsing last only for this private session.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let status = session.status {
                    Section { Text(status).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Hidden Elements")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ entry: ElementHidingEntry, canRemove: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.rule.label.isEmpty ? String(localized: "Element") : entry.rule.label)
                    .lineLimit(2)
                Text(entry.isHidden ? "Hidden in This Space" : "Visible in This Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if entry.isHidden {
                    Button("Show in This Space", systemImage: "eye") { session.show(entry.rule) }
                } else {
                    Button("Follow Global Rule", systemImage: "eye.slash") { session.follow(entry.rule) }
                }
                if canRemove {
                    Button("Delete Rule", systemImage: "trash", role: .destructive) { session.forget(entry.rule) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(CrestChromeButtonStyle())
            .accessibilityLabel("Element Options")
        }
    }
}
