import AppKit
import Carbon.HIToolbox
import OmojiCore
import ServiceManagement
import SwiftUI

final class Model: ObservableObject {
  let picker: OmojiCore.Picker
  init(picker: OmojiCore.Picker) { self.picker = picker }
}

final class PickerPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var panel: PickerPanel!
  private var model: Model!
  private var statusItem: NSStatusItem!
  private var hotKey: EventHotKeyRef?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let picker: OmojiCore.Picker
    do {
      picker = try makePicker()
    } catch {
      let alert = NSAlert()
      alert.messageText = "omoji could not start"
      alert.informativeText = String(describing: error)
      alert.runModal()
      NSApp.terminate(nil)
      return
    }
    model = Model(picker: picker)
    picker.onChange = { [weak self] in self?.model.objectWillChange.send() }
    picker.onVisibilityChange = { [weak self] shown in shown ? self?.show() : self?.hide() }

    panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 484),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    panel.contentView = NSHostingView(rootView: PickerView(model: model))

    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === self.panel, let key = Self.key(for: event) else { return event }
      if key == .tab && !picker.settingsOpen { return nil }
      return picker.handle(key, Self.modifiers(for: event)) ? nil : event
    }
    setUpEditMenu()
    setUpStatusItem()
    registerHotKey()
    picker.open()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    model?.picker.open()
    return false
  }

  func windowDidResignKey(_ notification: Notification) {
    model.picker.dismiss()
  }

  private func makePicker() throws -> OmojiCore.Picker {
    guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
    let read = { (name: String) in try String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8) }
    let environment = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let config = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config"
    let state = environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.local/state"
    let engine = try EmojiEngine(script: try read("EmojiSearch.js"))
    return OmojiCore.Picker(
      engine: engine,
      catalog: (try? read("emojis.json")) ?? "",
      history: HistoryStore(url: URL(fileURLWithPath: state + "/omoji/history.json"), engine: engine),
      preferences: PreferencesStore(url: URL(fileURLWithPath: config + "/omoji/config.json")),
      strings: Strings(json: (try? Data(contentsOf: resources.appendingPathComponent("en.json"))) ?? Data()),
      copy: { emoji in
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(emoji, forType: .string)
      },
      paste: { isCurrent, done in
        // Let the previous app take focus back before Command-V, as Omarchy waits before Shift+Insert.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          guard isCurrent() else {
            done(false)
            return
          }
          guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else {
            done(false)
            return
          }
          let source = CGEventSource(stateID: .combinedSessionState)
          for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
          }
          done(true)
        }
      })
  }

  private func show() {
    let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    if let frame = screen?.visibleFrame {
      let size = NSSize(width: min(640, frame.width - 32), height: min(484, frame.height - 32))
      panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height / 10,
                            width: size.width, height: size.height), display: true)
    }
    panel.makeKeyAndOrderFront(nil)
  }

  private func hide() {
    panel.orderOut(nil)
    // Opening from Finder or `open` activates omoji; give focus back so paste reaches the previous app.
    if NSApp.isActive { NSApp.hide(nil) }
  }

  private func setUpEditMenu() {
    // Text fields get Command-X/C/V/A/Z only through menu key equivalents.
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let main = NSMenu()
    main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
    NSApp.mainMenu = main
  }

  private func setUpStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "omoji")
    let menu = NSMenu()
    let open = menu.addItem(withTitle: "Open omoji", action: #selector(openPicker), keyEquivalent: "e")
    open.keyEquivalentModifierMask = [.control, .command]
    open.target = self
    let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
    login.target = self
    login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit omoji", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusItem.menu = menu
  }

  @objc private func openPicker() { model.picker.open() }

  @objc private func toggleLogin(_ item: NSMenuItem) {
    do {
      if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
    } catch {
      NSLog("omoji: could not change Open at Login: %@", String(describing: error))
    }
    item.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }

  private func registerHotKey() {
    var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
      let delegate = Unmanaged<AppDelegate>.fromOpaque(data!).takeUnretainedValue()
      DispatchQueue.main.async { delegate.toggle() }
      return noErr
    }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
    let id = EventHotKeyID(signature: OSType(0x6F6D6A69), id: 1)
    let status = RegisterEventHotKey(UInt32(kVK_ANSI_E), UInt32(controlKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
    if status != noErr { NSLog("omoji: Control-Command-E is taken by another app (%d)", status) }
  }

  private func toggle() {
    model.picker.opened ? model.picker.dismiss() : model.picker.open()
  }

  static func key(for event: NSEvent) -> Key? {
    switch Int(event.keyCode) {
    case kVK_Escape: return .escape
    case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
    case kVK_UpArrow: return .up
    case kVK_DownArrow: return .down
    case kVK_PageUp: return .pageUp
    case kVK_PageDown: return .pageDown
    case kVK_Tab: return .tab
    case kVK_Space: return .space
    default:
      guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else { return nil }
      return .character(characters)
    }
  }

  static func modifiers(for event: NSEvent) -> Modifiers {
    var modifiers: Modifiers = []
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.option) { modifiers.insert(.option) }
    return modifiers
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
