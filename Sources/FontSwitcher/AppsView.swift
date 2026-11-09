import FontSwitcherCore
import SwiftUI

struct AppsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Made for your workspace", subtitle: "Choose which editors and terminals receive font changes.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], spacing: 16) {
                    ForEach(TargetID.allCases) { target in AppSection(target: target) }
                }
                Label("Only font settings change. A backup is saved before every switch.", systemImage: "checkmark.shield")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.refreshTargets() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Re-detect apps and re-read their current fonts")
            }
        }
        .task { await model.refreshTargets() }
    }
}

private struct AppSection: View {
    @Environment(AppModel.self) private var model
    let target: TargetID

    var body: some View {
        let detected = model.detected.contains(target)
        let enabled = model.enabledTargets.contains(target)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                SymbolTile(symbol: target.isTerminal ? "terminal" : "curlybraces")
                VStack(alignment: .leading, spacing: 5) {
                    Text(target.displayName).font(.headline)
                    Label(detected ? "Detected" : "Not detected", systemImage: detected ? "checkmark.circle.fill" : "minus.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle(target.displayName, isOn: Binding(get: { enabled }, set: { _ in model.toggleTarget(target) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .disabled(!model.targetsLoaded)
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT FONT").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Text(model.currentFonts[target].map(Format.choice) ?? "Not available")
                    .font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(model.configPath(for: target))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .help(model.configPath(for: target))
            }
            if let note = TargetSpec.spec(for: target).note {
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .glassCard()
    }
}
