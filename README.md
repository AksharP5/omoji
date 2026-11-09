# omoji

An emoji picker for [Omarchy](https://omarchy.org) that learns your choices.

Type `flower`, choose wilted flower, and it comes first the next time you search `flower`. No aliases to set up. Just pick what you mean.

| Your first search | The next time |
| --- | --- |
| ![Flower results before choosing wilted flower](docs/screenshots/before.png) | ![Wilted flower ranked first for the same search](docs/screenshots/learned.png) |

- **Learns each search.** Your choice for `flower` stays separate from your choice for `heart`.
- **Remembers recent picks.** Open it without typing to find the emojis you used last.
- **Copies or pastes.** Choose what Enter does. Ctrl+Enter does the other action.
- **Fits your desktop.** Native Quickshell UI, your Omarchy theme, and no extra background service.

[Raycast](https://www.raycast.com/)-style emoji search for Omarchy, inspired by [Omacast](https://github.com/typecraft-dev/oma-cast).

## Install

[View omoji in the plugin marketplace](https://plugins.omarchy.org/plugin.html?id=akshar.omoji), or install it directly:

```sh
omarchy plugin add https://github.com/AksharP5/omoji --enable
```

Press **Ctrl+Super+E**, type a search, and press **Enter** to use the selected emoji.
Use **Up/Down** to move through results, or click one.

The existing emoji shortcut and Omarchy menu action open omoji automatically. If you already use another replacement for `omarchy.emojis`, disable that plugin first with `omarchy plugin disable <its-id>`.

To use another key, add it to `~/.config/hypr/bindings.lua`. This moves the picker to Super+Period:

```lua
hl.unbind("SUPER + CTRL + E")
o.bind("SUPER + PERIOD", "Emojis", { panel = "omarchy.emojis" })
```

To open the smaller card from its own key, whatever your card setting is:

```lua
o.bind("SUPER + ALT + E", "Compact emojis", [[omarchy-shell shell toggle omarchy.emojis '{"card":"compact"}']])
```

Tested on Omarchy **4.5.0** and **4.0.0.r7396.g526fe64-1**. Uses the Quickshell, Bash, `wl-copy`, `wl-paste`, coreutils, and `wtype` that Omarchy includes. No build step or additional packages.

## macOS

omoji also runs as a small menu bar app on macOS 13 or later. It uses the same emoji catalog, search, and learning as the Omarchy plugin.

Tagged releases will provide [omoji.dmg](https://github.com/AksharP5/omoji/releases/latest/download/omoji.dmg). Open the DMG and drag omoji to Applications. The app is not notarized, so macOS blocks the first launch. Open omoji once, then go to System Settings › Privacy & Security and click **Open Anyway**. Until the first release is published, build it yourself with the Xcode command line tools:

```sh
git clone https://github.com/AksharP5/omoji
cd omoji/macos
./build-app.sh
cp -R build/omoji.app /Applications/
open /Applications/omoji.app
```

Press **Control-Command-E** to open the picker. The keys are the same as on Omarchy, with **Command-,** for settings and **Command-Return** as well as Control-Return for the other action. The gear in the picker and the menu bar icon both have these options:

- **Change Shortcut…** records a new key combination for the picker.
- **Compact Card** uses a smaller card that opens at the text cursor when the app reports one.
- **Type : to Search Emoji** works in any app: type `:` and at least two letters, such as `:rose`. Up and Down select, Return or Tab inserts the emoji, Escape closes the list, and a closing `:` inserts the highlighted result. Terminal apps are skipped. omoji keeps only the current `:` word in memory, never other typing.
- **Open at Login** starts omoji when you log in.

The `:` trigger keeps your literal text until you choose an emoji. Switching apps or Spaces cancels the list without editing either document. Apps with their own `:` completion may show both menus; turn this option off to use the app's menu alone.

Paste and Type : need Accessibility permission (System Settings › Privacy & Security › Accessibility). Until you allow it, the picker shows a short guide with an **Open Settings** button before the emoji list. If you choose **Not Now**, a pasted emoji stays on the clipboard and the picker tells you what to do. Copy works without any permission.

Preferences and learning use the same files as on Omarchy. Edits to the preferences file apply the next time the picker opens. To reset learning, quit omoji from the menu bar before you rename the history file. A new version of an app that is not notarized can ask for Accessibility permission again.

## Make Enter work your way

Press **?** or click the **gear** beside search. Click **Copy** or **Paste**, or press **C** or **P**. Your choice saves immediately and the menu closes, returning you to the same search.

<img src="docs/screenshots/settings.png" alt="Compact gear menu with Copy and Paste options and subtle keyboard shortcuts" width="640">

| Default | Enter or click | Ctrl+Enter |
| --- | --- | --- |
| Paste | Paste into the app you came from | Copy to clipboard |
| Copy | Copy to clipboard | Paste into the app you came from |

Paste is the initial default. **Esc**, **?**, or a click outside the menu closes it without changing your preference.

Pasting sends **Shift+Insert** after the picker closes, as Omarchy does. The emoji also stays on the clipboard. If your app does not accept Shift+Insert, use Copy and your app's paste shortcut instead.

## Keyboard

| Key | Action |
| --- | --- |
| Ctrl+Super+E | Open the picker |
| Type | Search English names and keywords |
| Up / Down | Select a result |
| Ctrl+N / Ctrl+P | Next / previous result |
| Page Up / Page Down | Move a page |
| Enter | Use your default action |
| Ctrl+Enter | Use the opposite action for this pick |
| ? / Ctrl+, | Open or close settings |
| Esc | Leave settings, clear the search, then close |

On macOS, arrow and page keys with modifiers keep the search field's normal editing behavior.

In settings, **C** selects Copy and **P** selects Paste and returns to the picker. You can also use **Up/Down** or **Tab**, then **Enter** or **Space** to apply the highlighted choice and return. Emoji actions are suspended while the menu is open.

## Learning and privacy

The choice you use most for a search comes first. Your most recent choice breaks a tie. Searches ignore case and repeated spaces. Browsing results or closing the picker does not teach it a preference.

`us flag` favors U.S. flags over countries whose names merely contain `us`. Partial matches remain available, and learned choices still come first.

Everything stays on your machine. No account, telemetry, or runtime network requests. Emoji names and keywords are English; interface text follows Omarchy's language fallback.

Search accepts up to 160 characters. Longer queries remain editable; shorten them to select a result. Clipboard text is read only when you paste, in a separate process with a one-second timeout and a 641-byte transfer limit. Oversized or stalled pastes leave your search unchanged and show a warning.

<details>
<summary>Local files and manual configuration</summary>

Preferences: `${XDG_CONFIG_HOME:-~/.config}/omoji/config.json`

```json
{ "version": 1, "defaultAction": "paste" }
```

Use `"copy"` for a copy default. Add `"card": "compact"` for the smaller card. Changes are picked up automatically. Invalid preferences are left untouched; omoji falls back to copying and shows a warning.

Learning: `${XDG_STATE_HOME:-~/.local/state}/omoji/history.json`

The history keeps the 2,000 most recent search/emoji pairs. Files use mode `0600`, directories `0700`, and writes are atomic. Unreadable history is preserved and disables learning while copy and paste keep working. To reset learning, close the picker, rename the history file, and restart the Omarchy shell.

Only completed copy or paste commands teach the picker. It cannot detect whether an application accepts Shift+Insert. If a paste command fails, the picker returns with an error and the emoji remains on the clipboard.

</details>

## Update or remove

```sh
omarchy plugin update akshar.omoji
```

If the shell retains an older interface after updating, run `omarchy restart shell`.

```sh
omarchy plugin remove akshar.omoji
```

Omarchy restores its built-in picker. Your preferences and learning history are kept. If you disabled another replacement yourself, re-enable it to return to that picker.

## Contributing

See [the development guide](docs/development.md) for tests, isolated previews, and compatibility checks.

## License

[MIT](LICENSE). Built on [Omarchy](https://github.com/omacom/omarchy), copyright David Heinemeier Hansson, under [its MIT license](LICENSE-OMARCHY). English names and keywords come from [Unicode CLDR](https://github.com/unicode-org/cldr-json) under the [Unicode license](LICENSE-UNICODE).
