# Development

```sh
git clone https://github.com/AksharP5/omoji
cd omoji
node --test tests/search.test.js
omarchy plugin validate .
python scripts/native-test.py
```

Node and Python are development tools only. The picker runs in Omarchy's Quickshell shell.

The native tests require a running Omarchy Wayland session. They use temporary history and preferences, replace clipboard and paste commands, and suppress the picker window. They cover both default actions, the opposite shortcut, saved preferences, learning across restarts, failed commands, cancellation when reopening, and corrupt files.

To check another Omarchy checkout:

```sh
OMARCHY_PATH=/path/to/omarchy python scripts/native-test.py
```

The supported targets are Omarchy v4.5.0 and 4.0.0.r7396.g526fe64-1 with Quickshell 0.3.2.r7. Real keyboard and paste checks should run in an isolated desktop so they do not alter personal history or the system clipboard.

## Native screenshots

These previews use the actual QML with temporary data. They do not install the plugin or replace your shortcut.

```sh
python scripts/preview.py --query flower --capture /tmp/before.png
python scripts/preview.py --query flower --learn 'wilted flower' --capture /tmp/learned.png
python scripts/preview.py --settings --capture /tmp/settings.png
python scripts/preview.py --settings --default-action copy --capture /tmp/settings-copy.png
```

Run `python scripts/preview.py` for an interactive preview. New QML types may require restarting the Omarchy shell when updating an installed plugin because Quickshell caches modules.

## Emoji data

`python scripts/update-data.py` rebuilds the bundled 1,870-emoji catalog from pinned Omarchy v4.5.0 and Unicode CLDR 48 data. This development command downloads public data; the picker itself works offline.
