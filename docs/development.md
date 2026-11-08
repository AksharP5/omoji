# Development

```sh
git clone https://github.com/AksharP5/omoji
cd omoji
node --test tests/*.test.js
omarchy plugin validate .
python3 scripts/native-test.py
```

Node and Python are development tools only. The picker runs in Omarchy's Quickshell shell.

On macOS, the Node tests also need GNU `timeout`, which Omarchy includes: `brew install coreutils`. Quickshell tests and previews need an Omarchy Wayland session, so they do not run on macOS.

## macOS app

The macOS app in `macos/` runs the same `EmojiSearch.js`, `emojis.json`, and `i18n/en.json` through JavaScriptCore, so search and learning stay identical on both platforms. `OmojiCore` holds the picker behavior without AppKit; the `omoji` target adds the window, menu bar item, global shortcut, clipboard, and paste.

```sh
cd macos
swift test
./build-app.sh
```

The tests use temporary preferences and history and replace copy and paste, so they do not touch the clipboard or type into other apps. Delayed-paste checks cover reopening and dismissing the picker and making another selection before a pending paste completes.

## Omarchy native checks

The native tests require a running Omarchy Wayland session. They use temporary history and preferences, replace clipboard and paste commands, and suppress the picker window. They cover both default actions, the opposite shortcut, saved preferences, learning across restarts, failed commands, cancellation when reopening, and corrupt files. Catalog failures stay visible after opening, typing, and reopening the picker. Search editing checks cover query limits without losing text or undo history, and keep the cursor visible in long queries.

To check another Omarchy checkout:

```sh
OMARCHY_PATH=/path/to/omarchy python3 scripts/native-test.py
```

The supported targets are Omarchy v4.5.0 and 4.0.0.r7396.g526fe64-1 with Quickshell 0.3.2.r7. Real keyboard and paste checks should run in an isolated desktop so they do not alter personal history or the system clipboard.

## Keyboard regression checks

Use a separate Wayland compositor and private D-Bus session with temporary state. A hidden window does not isolate crash dialogs or clipboard access. Use normal keyboard input; do not load experimental native Qt plugins or move shell-owned items into another window to simulate focus.

1. Open the picker and type a query. Press Tab to focus the gear, then Esc. The query clears and typing returns to search.
2. With an empty query, focus the gear and press Esc. The picker closes.
3. Open settings with `?`, then press Esc. The original query stays intact and search regains focus.

## Native screenshots

These previews use the actual QML with temporary data. They do not install the plugin or replace your shortcut.

```sh
python3 scripts/preview.py --query flower --capture /tmp/before.png
python3 scripts/preview.py --query flower --learn 'wilted flower' --capture /tmp/learned.png
python3 scripts/preview.py --settings --capture /tmp/settings.png
python3 scripts/preview.py --settings --default-action copy --capture /tmp/settings-copy.png
```

Run `python3 scripts/preview.py` for an interactive preview. New QML types may require restarting the Omarchy shell when updating an installed plugin because Quickshell caches modules.

## Emoji data

`python3 scripts/update-data.py` rebuilds the bundled 1,870-emoji catalog from pinned Omarchy v4.5.0 and Unicode CLDR 48 data. This development command downloads public data; the picker itself works offline.
