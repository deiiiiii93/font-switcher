import AppKit
import SwiftUI

@main
struct FontSwitcherApp: App {
    @State private var model = AppModel()

    init() {
        AppAppearance.restore()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("FontSwitcher", id: "main") {
            MainWindow()
                .environment(model)
        }
        .defaultSize(width: 1180, height: 780)
        .defaultLaunchBehavior(DevPreview.isEnabled ? .presented : .suppressed)

        // Dev-only: never presented unless FONTSWITCHER_PREVIEW=1, and kept out of the Window menu.
        Window("Panel Preview", id: "panel-preview") {
            PanelPreview()
                .environment(model)
                .containerBackground(.clear, for: .window)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .windowLevel(.floating)
        .defaultPosition(.topTrailing)
        .defaultLaunchBehavior(DevPreview.isEnabled ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
    }
}

/// The bundled template glyph (copied into Resources by bundle.sh), else an SF Symbol.
struct MenuBarLabel: View {
    var body: some View {
        if let image = Self.bundledIcon() {
            Image(nsImage: image)
        } else {
            Image(systemName: "textformat")
        }
    }

    static func bundledIcon() -> NSImage? {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon")?.copy() as? NSImage else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
