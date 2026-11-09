import FontSwitcherCore
import SwiftUI

struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(title: "Your favorite setups", subtitle: "Keep a few good combinations ready for every app.")
            HStack(spacing: 18) {
                Group {
                    if model.state.profiles.isEmpty {
                        ContentUnavailableView("No Profiles", systemImage: "square.stack.3d.up",
                                               description: Text("Create one with + or use “Save as Profile…” in Fonts."))
                    } else {
                        List(selection: $selection) {
                            ForEach(model.state.profiles) { profile in
                                ProfileRow(profile: profile, active: model.state.activeProfileID == profile.id)
                                    .tag(profile.id)
                            }
                        }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .frame(width: 230)
                .frame(maxHeight: .infinity)
                .glassCard()

                Group {
                    if let profile = model.state.profiles.first(where: { $0.id == selection }) {
                        ProfileEditor(original: profile, onDelete: { selection = nil })
                            .id(profile)
                    } else if !model.state.profiles.isEmpty {
                        ContentUnavailableView("Select a Profile", systemImage: "slider.horizontal.3")
                    } else {
                        ContentUnavailableView("A setup worth keeping", systemImage: "textformat",
                                               description: Text("Save a font, choose a size, and make it yours."))
                            .englishSymbols()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard()
            }
        }
        .padding(28)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let family = model.selectedFamilyName ?? model.monospacedNames.first ?? "Menlo"
                    selection = model.saveProfile(name: "New Profile", family: family, size: nil).id
                } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .help("New profile")
            }
        }
        .onAppear {
            if selection == nil { selection = model.state.activeProfileID ?? model.state.profiles.first?.id }
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(on: active)
                .help(active ? "Active profile" : "")
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.body.weight(.medium))
                Text(profile.size.map { "\(profile.family) · \(Format.size($0)) pt" } ?? profile.family)
                    .font(.custom(profile.family, size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let summary = StarterProfiles.summary(for: profile.name) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else if !profile.overrides.isEmpty {
                    Text("\(profile.overrides.count) per-app override\(profile.overrides.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// Edits a draft copy; nothing is stored until Save.
private struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    let original: Profile
    let onDelete: () -> Void
    @State private var draft: Profile
    @State private var confirmingDelete = false

    init(original: Profile, onDelete: @escaping () -> Void) {
        self.original = original
        self.onDelete = onDelete
        _draft = State(initialValue: original)
    }

    private var cleaned: Profile {
        var p = draft
        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.family = p.family.trimmingCharacters(in: .whitespacesAndNewlines)
        p.overrides = p.overrides.compactMapValues { o in
            let family = o.family?.trimmingCharacters(in: .whitespacesAndNewlines)
            let c = FontChoice(family: (family?.isEmpty ?? true) ? nil : family, size: o.size)
            return c.family == nil && c.size == nil ? nil : c
        }
        return p
    }

    private var isValid: Bool { !cleaned.name.isEmpty && !cleaned.family.isEmpty }
    private var isDirty: Bool { cleaned != original }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    LabeledContent("Font family") {
                        FamilyField(text: $draft.family, placeholder: "Family")
                            .frame(maxWidth: 300)
                    }
                    LabeledContent("Size") {
                        OptionalSizeField(value: $draft.size, unsetLabel: "Leave sizes as they are")
                    }
                } header: {
                    Text(original.name)
                        .font(.custom(draft.family, size: 22).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Section {
                    ForEach(TargetID.allCases) { target in
                        OverrideRow(target: target, choice: overrideBinding(target))
                    }
                } header: {
                    Text("Per-app overrides")
                } footer: {
                    Text("Empty fields fall back to the profile's family and size.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack(spacing: 10) {
                Button("Save") { model.updateProfile(cleaned) }
                    .glassButton(prominent: true)
                    .disabled(!isValid || !isDirty)
                    .keyboardShortcut("s", modifiers: .command)
                Button("Revert") { draft = original }
                    .glassButton()
                    .disabled(!isDirty)
                Button("Apply Now") {
                    if isDirty { model.updateProfile(cleaned) }
                    model.apply(cleaned)
                }
                .glassButton()
                .disabled(!isValid || model.isBusy || model.enabledTargets.isEmpty)
                Spacer()
                Button("Delete…", role: .destructive) { confirmingDelete = true }
                    .glassButton()
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
        .alert("Delete “\(original.name)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                model.deleteProfile(original.id)
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the profile only; your app configs are not changed.")
        }
    }

    private func overrideBinding(_ target: TargetID) -> Binding<FontChoice?> {
        Binding(get: { draft.overrides[target] }, set: { draft.overrides[target] = $0 })
    }
}

private struct OverrideRow: View {
    let target: TargetID
    @Binding var choice: FontChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { choice != nil },
                                 set: { choice = $0 ? (choice ?? FontChoice(family: nil, size: nil)) : nil })) {
                Text(target.displayName).frame(width: 70, alignment: .leading)
            }
            .toggleStyle(.checkbox)

            if let current = choice {
                FamilyField(text: Binding(get: { current.family ?? "" },
                                          set: { choice?.family = $0.isEmpty ? nil : $0 }),
                            placeholder: "Profile family")
                    .frame(maxWidth: 240)
                OptionalSizeField(value: Binding(get: { current.size }, set: { choice?.size = $0 }),
                                  unsetLabel: "Profile size")
            } else {
                Text("Uses the profile's font").foregroundStyle(.tertiary)
            }
        }
    }
}

/// Free-text family name plus a menu of favorites and monospaced families.
struct FamilyField: View {
    @Environment(AppModel.self) private var model
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
            Menu {
                if !model.installedFavorites.isEmpty {
                    Section("Favorites") {
                        ForEach(model.installedFavorites, id: \.self) { name in
                            Button(name) { text = name }
                        }
                    }
                }
                Section("Monospaced") {
                    ForEach(model.monospacedNames, id: \.self) { name in
                        Button(name) { text = name }
                    }
                }
            } label: {
                Image(systemName: "textformat")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Pick a font")
        }
    }
}

/// A size that may be unset (nil = leave the app's size alone).
struct OptionalSizeField: View {
    @Binding var value: Double?
    let unsetLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Set size", isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? 14) : nil }))
                .toggleStyle(.checkbox)
            if let v = value {
                Stepper(value: Binding(get: { v }, set: { value = $0 }), in: 6...72, step: 0.5) {
                    Text("\(Format.size(v)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            } else {
                Text(unsetLabel).foregroundStyle(.tertiary)
            }
        }
    }
}
