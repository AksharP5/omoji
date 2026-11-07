# Development

Read `docs/development.md` before running UI tests.

- Run keyboard, pointer, and clipboard probes only in a separate Wayland compositor with a private D-Bus session and temporary preferences/history.
- A hidden test window still shares the desktop's clipboard, services, and crash dialogs. Hiding it does not isolate it.
- Use normal compositor input and the existing QML components. Do not load experimental native Qt plugins or reparent Quickshell-owned items to fabricate focus.
- Keep crash reports local. Never upload process memory or personal desktop state.
