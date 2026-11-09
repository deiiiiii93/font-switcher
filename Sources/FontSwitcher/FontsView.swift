import FontSwitcherCore
import SwiftUI

enum FontFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case monospaced = "Mono"
    case favorites = "Favorites"
    var id: String { rawValue }
}

struct FontsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filter: FontFilter = .all
    @State private var dropTargeted = false

    private var visible: [FontFamily] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return model.families.filter { f in
            (filter == .all || (filter == .monospaced && f.isMonospaced) ||
             (filter == .favorites && model.isFavorite(f.name))) &&
            (q.isEmpty || f.name.localizedCaseInsensitiveContains(q))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Collection").font(.headline)
                    Spacer()
                    Text("\(visible.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search fonts", text: $query).textFieldStyle(.plain)
                        .accessibilityLabel("Search fonts")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear search")
                    }
                }
                .padding(9)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                Picker("Filter", selection: $filter) {
                    ForEach(FontFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                list
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.doc")
                    Text("Drop font files here to install")
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }
            .padding(16)
            .frame(width: 270)
            Divider()
            Group {
                if let family = model.family(named: model.selectedFamilyName) {
                    FontPreview(family: family).id(family.name)
                } else {
                    ContentUnavailableView(model.isLoadingFonts ? "Loading Fonts…" : "Select a Font",
                                           systemImage: "textformat")
                        .englishSymbols()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.presentInstallPanel() } label: {
                    Label("Install Fonts…", systemImage: "plus")
                }
                .help("Install font files (or drop them on this window)")
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.doc").font(.largeTitle)
                            Text("Drop fonts to install").font(.title2.weight(.semibold))
                            Text("TrueType and OpenType font files").foregroundStyle(.secondary)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                    .padding(12).allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.installFonts(files)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    @ViewBuilder private var list: some View {
        if model.families.isEmpty && model.isLoadingFonts {
            ProgressView("Loading fonts…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visible.isEmpty {
            ContentUnavailableView(filter == .favorites && query.isEmpty ? "No Favorites Yet" : "No Matching Fonts",
                                   systemImage: filter == .favorites ? "star" : "magnifyingglass",
                                   description: Text(filter == .favorites && query.isEmpty ? "Star a font to keep it here." : "Try another name or filter."))
                .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(selection: Binding(get: { model.selectedFamilyName },
                                        set: { if let name = $0 { model.selectedFamilyName = name } })) {
                    ForEach(visible) { family in
                        FontRow(family: family, favorite: model.isFavorite(family.name),
                                toggleFavorite: { model.toggleFavorite(family.name) })
                            .tag(family.name).id(family.name)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear {
                    if let name = model.selectedFamilyName { proxy.scrollTo(name, anchor: .center) }
                }
                .onChange(of: filter) {
                    if let name = model.selectedFamilyName { proxy.scrollTo(name, anchor: .center) }
                }
            }
        }
    }
}

private struct FontRow: View {
    let family: FontFamily
    let favorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(family.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("Aa Bb 0123").font(.custom(family.name, size: 16)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: toggleFavorite) {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(favorite ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(favorite ? "Unfavorite" : "Favorite") \(family.name)")
            .help(favorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.vertical, 6)
    }
}

private struct FontPreview: View {
    @Environment(AppModel.self) private var model
    let family: FontFamily
    @State private var size: Double = 14
    @State private var includeSize = false
    @State private var showingSaveSheet = false
    @State private var confirmingRemove = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heading
                    specimen
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("CODE PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                            Spacer()
                            Text("Swift").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        CodeSample(family: family.name, size: size)
                        HStack(spacing: 12) {
                            Image(systemName: "textformat.size").foregroundStyle(.secondary).englishSymbols()
                            Slider(value: $size, in: 8...32, step: 1).accessibilityLabel("Preview font size")
                            Text("\(Format.size(size)) pt").font(.callout.monospacedDigit()).frame(width: 44, alignment: .trailing)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CHARACTER CHECK").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                        Text("0O  1lI  {} []  => !=  @#&")
                            .font(.custom(family.name, size: 20))
                            .lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18).glassCard(cornerRadius: 12)
                }
                .padding(28)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider().opacity(0.5)
            actionBar
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveProfileSheet(family: family.name, size: includeSize ? size : nil)
        }
        .alert("Move “\(family.name)” to the Trash?", isPresented: $confirmingRemove) {
            Button("Move to Trash", role: .destructive) { model.removeFamily(family) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its \(family.faceURLs.count) font file\(family.faceURLs.count == 1 ? "" : "s") in ~/Library/Fonts will be moved to the Trash.")
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(family.name).font(.system(size: 24, weight: .semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Tag(text: family.isMonospaced ? "Monospaced" : "Proportional")
                    if family.isUserInstalled { Tag(text: "Installed by you") }
                }
            }
            Spacer(minLength: 0)
            Button { model.toggleFavorite(family.name) } label: {
                Image(systemName: model.isFavorite(family.name) ? "star.fill" : "star")
                    .foregroundStyle(model.isFavorite(family.name) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .frame(width: 20, height: 24)
            }
            .glassButton()
            .accessibilityLabel(model.isFavorite(family.name) ? "Remove from favorites" : "Add to favorites")
            if family.isUserInstalled {
                Menu {
                    Button("Remove Font…", role: .destructive) { confirmingRemove = true }
                } label: { Image(systemName: "ellipsis").frame(height: 24) }
                    .menuStyle(.borderlessButton).fixedSize().help("Font actions")
            }
        }
    }

    private var specimen: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aa Bb Cc")
                .font(.custom(family.name, size: 64))
                .lineLimit(1).minimumScaleFactor(0.4)
            Text("The quick brown fox jumps\nover the lazy dog.")
                .font(.custom(family.name, size: 22))
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Also apply size · \(Format.size(size)) pt", isOn: $includeSize)
                .toggleStyle(.checkbox).font(.callout).foregroundStyle(.secondary)
                .help("Leave unchecked to keep each app’s current font size.")
            HStack(spacing: 10) {
                Button {
                    model.applyFamily(family.name, size: includeSize ? size : nil)
                } label: {
                    Label("Apply to \(model.enabledTargets.count) Apps", systemImage: "checkmark")
                }
                .glassButton(prominent: true)
                .disabled(model.enabledTargets.isEmpty || model.isBusy || !model.targetsLoaded)
                Button("Save as Profile…") { showingSaveSheet = true }.glassButton()
                Spacer(minLength: 0)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
    }
}
/// A short Swift function, syntax-colored, in the previewed family, on a dark editor card.
private struct CodeSample: View {
    let family: String
    let size: Double

    var body: some View {
        ScrollView(.horizontal) {
            Text(Self.highlighted)
                .font(.custom(family, size: size))
                .lineSpacing(size * 0.3)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CodePalette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private enum Kind { case keyword, function, type, string, plain }

    private static let tokens: [(String, Kind)] = [
        ("func", .keyword), (" ", .plain), ("greet", .function), ("(name: ", .plain), ("String", .type),
        (") -> ", .plain), ("String", .type), (" {\n    ", .plain),
        ("return", .keyword), (" ", .plain), ("\"Hello, ", .string), ("\\(name)", .plain), ("!\"", .string),
        ("\n}", .plain),
    ]

    private static let highlighted: AttributedString = {
        var out = AttributedString()
        for (text, kind) in tokens {
            var run = AttributedString(text)
            run.foregroundColor = switch kind {
            case .keyword: CodePalette.keyword
            case .function: CodePalette.function
            case .type: CodePalette.type
            case .string: CodePalette.string
            case .plain: CodePalette.plain
            }
            out += run
        }
        return out
    }()
}

struct SaveProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let family: String
    let size: Double?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save as Profile").font(.title3.weight(.semibold))
            Text(size.map { "\(family) · \(Format.size($0)) pt" } ?? "\(family) · size unchanged")
                .foregroundStyle(.secondary)
            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Text("Per-app overrides can be added later in Profiles.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmed.isEmpty else { return }
        model.saveProfile(name: trimmed, family: family, size: size)
        model.show("Saved profile “\(trimmed)”", isError: false)
        dismiss()
    }
}
