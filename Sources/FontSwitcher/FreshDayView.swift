import FontSwitcherCore
import SwiftUI

struct FreshDayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let fresh = model.state.freshDay
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "A fresh perspective, daily", subtitle: "A small change of type for a new day of work.")
                HStack(spacing: 14) {
                    SymbolTile(symbol: "sun.horizon", color: .orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fresh Day").font(.headline)
                        Text("Automatically switch your coding font each day.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enable Fresh Day", isOn: Binding(get: { fresh.enabled }, set: { model.setFreshDayEnabled($0) }))
                        .toggleStyle(.switch).labelsHidden()
                }
                .padding(20).glassCard()

                VStack(alignment: .leading, spacing: 22) {
                    Label("TODAY’S TYPE", systemImage: "sun.max")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                    if let today = model.freshDayToday {
                        Text(today).font(.custom(today, size: 36)).lineLimit(2)
                        Text("A new day. A different point of view.")
                            .font(.custom(today, size: 22)).foregroundStyle(.secondary)
                    } else {
                        Text(fresh.enabled ? "Your next favorite awaits." : "Start the day with something new.")
                            .font(.system(size: 30, weight: .medium, design: .serif))
                        Text(fresh.enabled ? "A font will be picked for your workspace." : "Turn on Fresh Day to discover a font each morning.")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button { model.rerollFreshDay() } label: { Label("Try Another Font", systemImage: "shuffle") }
                            .glassButton(prominent: true).controlSize(.large)
                            .disabled(!fresh.enabled || !model.fontsLoaded || model.isBusy)
                        Spacer()
                    }
                    Text(poolDescription).font(.callout).foregroundStyle(.secondary)
                }
                .padding(28).frame(maxWidth: .infinity, alignment: .leading).glassCard(cornerRadius: 20)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(.secondary)
                    Text("Picks from your favorites when you have at least two, otherwise from monospaced fonts. Yesterday’s pick is never repeated. Font sizes stay the same, and you can undo any switch.")
                        .font(.callout).foregroundStyle(.secondary).lineSpacing(3)
                }
                if !fresh.history.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recently in rotation").font(.headline)
                        ForEach(Array(fresh.history.reversed().enumerated()), id: \.offset) { _, record in
                            HStack {
                                Text(record.family).font(.custom(record.family, size: 15)).lineLimit(1)
                                Spacer()
                                Text(record.day).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            if record != fresh.history.first { Divider().opacity(0.5) }
                        }
                    }
                    .padding(20).glassCard()
                }
            }
            .padding(28)
        }
    }

    private var poolDescription: String {
        guard model.fontsLoaded else { return "Loading fonts…" }
        return "Choosing from \(model.freshDayPool.count) \(model.freshDayUsesFavorites ? "favorites" : "monospaced fonts")"
    }
}
