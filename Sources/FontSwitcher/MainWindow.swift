import AppKit
import FontSwitcherCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case fonts = "Fonts"
    case profiles = "Profiles"
    case apps = "Apps"
    case freshDay = "Fresh Day"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .fonts: "textformat"
        case .profiles: "square.stack.3d.up"
        case .apps: "square.grid.2x2"
        case .freshDay: "sun.horizon"
        }
    }
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var section: SidebarItem = .fonts

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    SymbolTile(symbol: "textformat")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("FontSwitcher").font(.headline)
                        Text("Your type. Everywhere.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 22)

                List(selection: Binding(get: { section }, set: { if let s = $0 { section = s } })) {
                    Section("Library") {
                        sidebarRow(.fonts)
                        sidebarRow(.profiles)
                    }
                    Section("Workspace") {
                        sidebarRow(.apps)
                        sidebarRow(.freshDay)
                    }
                }
                .listStyle(.sidebar)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(model.families.count) font families", systemImage: "textformat")
                        .englishSymbols()
                    Label("\(model.installedFavorites.count) favorites", systemImage: "star")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Appearance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AppearancePicker()
                }
                .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 250)
        } detail: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(BottomBar {
                    VStack(spacing: 8) {
                        BannerView()
                        // The Apps page has a switch per app already.
                        if section != .apps { AppChipStrip() } else { Color.clear.frame(height: 4) }
                    }
                })
        }
        .navigationTitle(section.rawValue)
        .containerBackground(Color(nsColor: .windowBackgroundColor), for: .window)
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            // Spec D13: a Dock icon and app menu only while the window is open.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            Task { await model.refreshTargets() }
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.rawValue, systemImage: item.symbol)
            .englishSymbols()
            .padding(.vertical, 5)
            .tag(item)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .fonts: FontsView()
        case .profiles: ProfilesView()
        case .apps: AppsView()
        case .freshDay: FreshDayView()
        }
    }
}

/// Bottom strip: one chip per app; green dot = detected and enabled. Clicking toggles enabled.
struct AppChipStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Text("APPLY TO")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(TargetID.allCases) { target in chip(target) }
                }
                .padding(3)
            }
            .scrollIndicators(.hidden)
            .frame(height: 32)
            if model.isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func chip(_ target: TargetID) -> some View {
        let enabled = model.enabledTargets.contains(target)
        let detected = model.detected.contains(target)
        return Button {
            model.toggleTarget(target)
        } label: {
            HStack(spacing: 6) {
                StatusDot(on: enabled && detected, size: 7)
                Text(target.displayName)
                    .foregroundStyle(enabled ? .primary : .tertiary)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(tint: enabled ? Color.accentColor.opacity(0.06) : nil)
        .accessibilityLabel(target.displayName)
        .accessibilityValue(enabled ? "Enabled" : "Disabled")
        .disabled(!model.targetsLoaded)
        .help("\(target.displayName): \(detected ? "detected" : "not detected"), \(enabled ? "enabled" : "disabled") — click to \(enabled ? "disable" : "enable")")
    }
}

/// The latest result message, as a floating glass capsule; dismisses itself after a while.
struct BannerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let banner = model.lastMessage {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(banner.isError ? Color.orange : Color.green)
                Text(banner.text)
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Button {
                    model.lastMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassCapsule()
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: banner.id) {
                try? await Task.sleep(for: .seconds(banner.isError ? 20 : 10))
                if model.lastMessage?.id == banner.id { model.lastMessage = nil }
            }
        }
    }
}
