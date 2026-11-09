import AppKit
import FontSwitcherCore
import SwiftUI

/// The menu bar panel (`.window` style so it can host the Fresh Day toggle and Reroll button).
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                header
                stats
                openApps
                message
            }
            Divider().padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 12) {
                actions
                freshDayRow
            }
            Divider().padding(.vertical, 12)
            ScrollView { profiles }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.vertical, 12)
            footer
        }
        .padding(20)
        .frame(width: 380)
        .task {
            await model.refreshTargets()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await model.refreshTargets()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                SymbolTile(symbol: "textformat")
                VStack(alignment: .leading, spacing: 3) {
                    Text("FontSwitcher").font(.headline)
                    Text("Your workspace, in type.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        let (title, on): (String, Bool) =
            if let profile = model.activeProfile { (profile.name, true) }
            else if model.isOnFreshDayFont { ("Fresh Day", true) }
            else { ("Custom", false) }
        return HStack(spacing: 6) {
            StatusDot(on: on)
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .glassCapsule(tint: on ? Color.green.opacity(0.3) : nil)
        .help(on ? "Active: \(title)" : "No profile active")
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.currentSummary?.family ?? "Make yourself at home")
                .font(.custom(model.currentSummary?.family ?? "Menlo", size: 25))
                .lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 12) {
                stat("square.stack.3d.up", "\(model.enabledTargets.count) apps")
                if let size = model.currentSummary?.size { Text("\(Format.size(size)) pt") }
                Spacer()
                if model.lastApplyFailures > 0 {
                    stat("exclamationmark.triangle", "\(model.lastApplyFailures) failed").foregroundStyle(.orange)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
        .padding(.top, 10)
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).englishSymbols()
            Text(text).lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var openApps: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("OPEN APPS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.runningTargets.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 3)

            if model.runningTargets.isEmpty {
                Text("No supported apps are open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 7)
            } else {
                ForEach(TargetID.allCases.filter { model.runningTargets.contains($0) }) { target in
                    HStack(spacing: 9) {
                        Image(systemName: target.isTerminal ? "terminal" : "curlybraces")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .englishSymbols()
                        Text(target.displayName)
                            .font(.callout.weight(.medium))
                        Spacer(minLength: 8)
                        Text(model.currentFonts[target].map(Format.choice) ?? "Font not set")
                            .font(.caption.monospaced())
                            .foregroundStyle(model.currentFonts[target] == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12)
    }

    private var message: some View {
        Group {
            if let banner = model.lastMessage {
                Text(banner.text)
                    .foregroundStyle(banner.isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .help(banner.text)
            } else {
                Text(model.isBusy ? "Working…" : "Ready").foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    // MARK: - Actions

    private var actions: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                if model.state.freshDay.enabled {
                    Button {
                        model.rerollFreshDay()
                    } label: {
                        Label("Reroll Today’s Font", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(prominent: true)
                    .disabled(!model.fontsLoaded || model.isBusy)
                } else if let profile = model.activeProfile {
                    Button {
                        model.apply(profile)
                    } label: {
                        Label("Apply \(profile.name)", systemImage: "checkmark.circle")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(prominent: true)
                    .disabled(model.isBusy || model.enabledTargets.isEmpty)
                }
                Button {
                    model.undo()
                } label: {
                    Text("Undo")
                        .frame(maxWidth: hasPrimary ? nil : .infinity)
                        .padding(.horizontal, 6)
                }
                .glassButton()
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model.isBusy)
                .help("Undo the last switch (⌘Z)")
            }
            .controlSize(.large)
        }
    }

    private var hasPrimary: Bool { model.state.freshDay.enabled || model.activeProfile != nil }

    private var freshDayRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fresh Day")
                if model.state.freshDay.enabled, let today = model.freshDayToday {
                    Text("Today: \(today)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("Fresh Day", isOn: Binding(get: { model.state.freshDay.enabled },
                                              set: { model.setFreshDayEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    // MARK: - Profiles

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Profiles")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            if model.state.profiles.isEmpty {
                Text("No profiles yet — save one from the Fonts window.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(model.state.profiles) { profile in
                    PanelRow(action: { model.apply(profile) }) {
                        StatusDot(on: model.state.activeProfileID == profile.id)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name).font(.callout.weight(.medium))
                            Text(profile.family).font(.caption).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(profile.size.map { "\(Format.size($0)) pt" } ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .disabled(model.isBusy)
                    .help("Apply \(profile.name)")
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open FontSwitcher…", action: openMain)
                .glassButton()
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .glassButton()
                .keyboardShortcut("q", modifiers: .command)
        }
        .controlSize(.large)
    }

    private func openMain() {
        // The menu-bar panel is key while its button is being clicked. Close it
        // before opening the main window, which will become the new key window.
        NSApp.keyWindow?.close()
        openWindow(id: "main")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

/// A full-width, menu-like row: accent highlight with white text on hover.
private struct PanelRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let highlighted = hovering && isEnabled
        Button(action: action) {
            HStack(spacing: 8) { label }
                .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Dev-only (`FONTSWITCHER_PREVIEW=1`): the panel content in an ordinary window, for screenshots.
struct PanelPreview: View {
    var body: some View {
        MenuBarView()
            .modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: 24), tint: nil))
            .padding(24)
            // The real panel is always the key window while it is open; render it that way here too.
            .environment(\.controlActiveState, .key)
    }
}

enum DevPreview {
    static let isEnabled = ProcessInfo.processInfo.environment["FONTSWITCHER_PREVIEW"] == "1"
}
