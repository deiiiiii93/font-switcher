# FontSwitcher

A native macOS menu bar app to manage your fonts and switch the coding font of your editors and terminals in one click.

The current interface uses a quiet native macOS layout: a grouped sidebar, searchable font collection, large type specimens, persistent Apply controls, and Liquid Glass actions on macOS 26+. Content surfaces adapt to light/dark appearance and Reduce Transparency.

## Features

- **One-click profiles**: start with Work (SF Mono 14 pt), Coding (Menlo 13 pt), and Design (Monaco 16 pt), then save your own named profiles with per-app overrides. Apply one from the menu bar to every enabled app at once. Starter profiles are added once, remain editable, and can be deleted.
- **Supported apps**

  | App | Config file | Keys written |
  |---|---|---|
  | VS Code | `~/Library/Application Support/Code/User/settings.json` | `editor.fontFamily`, `terminal.integrated.fontFamily`, `editor.fontSize` |
  | Cursor | `~/Library/Application Support/Cursor/User/settings.json` | same as VS Code |
  | Ghostty | `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` (or `config`, or `~/.config/ghostty/…`) | `font-family` (first line), `font-size` |
  | Herdr | `~/.config/herdr-app/settings.json` | `font`, `font_size` |
  | kitty | `~/.config/kitty/kitty.conf` | `font_family`, `font_size` |
  | Warp | `~/.warp/settings.toml` | `[appearance.text]` `font_name`, `font_size` |

- **Font management**: browse installed families (All / Monospaced / Favorites), live code preview, star favorites, install `.ttf/.otf/.ttc/.otc` by drag-and-drop or picker into `~/Library/Fonts`, and remove user-installed fonts (moved to Trash).
- **Appearance**: choose System, Light, or Dark in the sidebar. The choice applies to the window and menu bar panel and is remembered between launches.
- **Fresh Day**: optional daily random font. Once per local day (at launch, at midnight, or on wake), FontSwitcher picks a family and applies it to every enabled app. The pick comes from your favorites if you have at least two, otherwise from all monospaced fonts. The same day always gives the same pick, yesterday's font is never repeated, and **Reroll** picks another. It is off by default.

## Safety

- **Surgical edits**: only the font keys change. Comments, key order, indentation and trailing commas are preserved byte for byte. Fallback fonts are kept: only the first entry of a VS Code font list, or the first Ghostty `font-family` line, is replaced.
- **Backups + Undo**: before every switch, the originals are copied to `~/Library/Application Support/FontSwitcher/backups/` (the newest 20 switches are kept). **Undo** in the menu bar panel (⌘Z while it is open) restores them.
  - **Edited after the switch?** Apps rewrite their own settings files: changing any VS Code/Cursor setting, or Herdr saving its zoom, counts as an edit. Undo will not silently overwrite such a file. Instead it warns you which apps were *not* restored, and keeps their backups so you can choose:
    - **Restore Anyway** puts back the pre-switch file. Edits made since then are lost.
    - **Keep Current** leaves the file as it is. Set the font in the app or apply a profile.
- **Symlinks preserved**: dotfile-managed configs stay symlinks, and the write goes to the link's destination.
- A file that can't be parsed is never written; other apps still switch.

## How changes take effect

- VS Code, Cursor, Herdr and Warp watch their settings files and update live.
- kitty (`SIGUSR1`) and Ghostty (`SIGUSR2`) are signalled to reload if running. Ghostty applies font family changes to **new windows and tabs**.
- Herdr's `font_size` is in px at zoom 1, and a Herdr layout's own font overrides `settings.json`.

## Build & install

Requirements: macOS 15+, Swift 6 toolchain (Xcode 16+ or Command Line Tools).

```sh
scripts/bundle.sh                      # builds build/FontSwitcher.app (ad-hoc signed)
open build/FontSwitcher.app            # runs as a menu bar app ("Aa" icon)
cp -R build/FontSwitcher.app /Applications/
```

The app is not sandboxed (it must edit other apps' config files) and is not notarized; on first launch you may need to right-click → Open.

## Development

```sh
swift build
swift test                             # core logic: editors, switcher, backups, Fresh Day, fonts
```

`FONTSWITCHER_HOME=/some/dir` points the app at a fake home for both target configs and its own state. It's useful for trying it without touching your real settings. (Installing or removing fonts still uses the real `~/Library/Fonts`.)

`FONTSWITCHER_PREVIEW=1` opens the main window plus a "Panel Preview" window showing the menu bar panel at launch, for screenshots: `open -n --env FONTSWITCHER_HOME=/some/dir --env FONTSWITCHER_PREVIEW=1 build/FontSwitcher.app`.

Layout: `Sources/FontSwitcherCore` holds all logic and is unit-tested. `Sources/FontSwitcher` is the SwiftUI app.

## License

FontSwitcher is available under the MIT License. See [LICENSE](LICENSE).
