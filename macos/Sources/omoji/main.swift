import AppKit
import Carbon.HIToolbox
import OmojiCore
import ServiceManagement
import SwiftUI

final class Model: ObservableObject {
  struct Option {
    let title: String
    let isOn: () -> Bool
    let set: (Bool) -> Void
  }

  let picker: OmojiCore.Picker
  var onHeight: (CGFloat) -> Void = { _ in }
  var options: [Option] = []
  var shortcut: () -> String = { "" }
  var changeShortcut: () -> Void = {}
  var needsAccess = false
  var allowAccess: () -> Void = {}
  var skipAccess: () -> Void = {}
  init(picker: OmojiCore.Picker) { self.picker = picker }
}

final class ColonModel: ObservableObject {
  let trigger: ColonTrigger
  var onHeight: (CGFloat) -> Void = { _ in }
  init(trigger: ColonTrigger) { self.trigger = trigger }
}

final class PickerPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var panel: PickerPanel!
  private var model: Model!
  private var statusItem: NSStatusItem!
  private var hotKey: EventHotKeyRef?
  private var openItem: NSMenuItem!
  private var cardItem: NSMenuItem!
  private var colonItem: NSMenuItem!
  private var loginItem: NSMenuItem!
  private var askedForAccess = false
  private var skippedAccess = false
  private var caret: NSRect?
  private var compactHeight: CGFloat = 300
  private var colonModel: ColonModel!
  private var colonPanel: NSPanel!
  private var colonCaret: NSRect?
  private var colonHeight: CGFloat = 100
  private var colonTap: CFMachPort?
  private var colonSource: CFRunLoopSource?
  private var colonApp: pid_t = 0
  private static let typedMark: Int64 = 0x6F6D6A69
  private static let terminals: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
    "net.kovidgoyal.kitty", "com.mitchellh.ghostty", "org.alacritty", "com.github.wez.wezterm"]

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
    picker.onChange = { [weak self] in
      guard let self else { return }
      self.model.needsAccess = self.accessNeeded()
      self.model.objectWillChange.send()
    }
    picker.onVisibilityChange = { [weak self] shown in shown ? self?.show() : self?.hide() }
    model.onHeight = { [weak self] height in
      guard let self, picker.card == .compact else { return }
      self.compactHeight = height
      if picker.opened { self.panel.setFrame(Self.place(NSSize(width: 420, height: height), near: self.caret), display: true) }
    }

    panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 484),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    let pickerHost = NSHostingView(rootView: PickerView(model: model))
    pickerHost.sizingOptions = []
    panel.contentView = pickerHost

    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === self.panel, let key = Self.key(for: event) else { return event }
      if self.model.needsAccess {
        if key == .escape { picker.dismiss() } else if key == .enter { self.model.allowAccess() }
        return nil
      }
      if key == .tab && !picker.settingsOpen { return nil }
      return picker.handle(key, Self.modifiers(for: event)) ? nil : event
    }
    setUpEditMenu()
    setUpColon(picker)
    setUpStatusItem()
    installHotKeyHandler()
    let saved = UserDefaults.standard
    if saved.object(forKey: "hotKeyCode") != nil, let key = saved.string(forKey: "hotKeyEquivalent") {
      setHotKey(UInt32(saved.integer(forKey: "hotKeyCode")), NSEvent.ModifierFlags(rawValue: UInt(saved.integer(forKey: "hotKeyModifiers"))), key)
    } else {
      setHotKey(UInt32(kVK_ANSI_E), [.control, .command], "e")
    }
    setUpSettings()
    if colonItem.state == .on && AXIsProcessTrusted() { startColon() }
    picker.open()
  }

  private func setUpSettings() {
    model.options = [
      .init(title: "Compact card", isOn: { [unowned self] in model.picker.card == .compact }, set: { [unowned self] in setCard($0) }),
      .init(title: "Type : to search emoji", isOn: { [unowned self] in colonItem.state == .on }, set: { [unowned self] in setColon($0) }),
      .init(title: "Open at login", isOn: { SMAppService.mainApp.status == .enabled }, set: { [unowned self] in setLogin($0) }),
    ]
    model.shortcut = { [unowned self] in
      let modifiers = openItem.keyEquivalentModifierMask
      let key = openItem.keyEquivalent == " " ? "Space" : openItem.keyEquivalent.uppercased()
      return [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        .filter { modifiers.contains($0.0) }.map(\.1).joined() + key
    }
    model.changeShortcut = { [unowned self] in
      model.picker.dismiss()
      changeShortcut()
    }
    model.allowAccess = { [unowned self] in
      // The first time, macOS's own prompt adds omoji to the Accessibility list; after that, open the list directly.
      if askedForAccess {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
      } else {
        askedForAccess = true
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
      }
    }
    model.skipAccess = { [unowned self] in
      skippedAccess = true
      model.needsAccess = false
      model.objectWillChange.send()
    }
    DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"),
                                                        object: nil, queue: .main) { [weak self] _ in
      // macOS sends this just before the new permission is readable.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.accessChanged() }
    }
  }

  private func accessNeeded() -> Bool {
    !skippedAccess && !AXIsProcessTrusted() && (model.picker.defaultAction == .paste || colonItem.state == .on)
  }

  private func accessChanged() {
    guard AXIsProcessTrusted() else { return }
    model.needsAccess = false
    model.objectWillChange.send()
    if colonItem.state == .on && colonTap == nil { startColon() }
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
            done(.failed)
            return
          }
          guard AXIsProcessTrusted() else {
            done(.needsAccess)
            return
          }
          let source = CGEventSource(stateID: .combinedSessionState)
          for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
          }
          done(.pasted)
        }
      })
  }

  private func show() {
    endColon()
    model.needsAccess = accessNeeded()
    if colonItem.state == .on && colonTap == nil && AXIsProcessTrusted() { startColon() }
    let compact = model.picker.card == .compact
    cardItem.state = compact ? .on : .off
    caret = compact ? Self.caretRect() : nil
    panel.setFrame(Self.place(compact ? NSSize(width: 420, height: compactHeight) : NSSize(width: 640, height: 484), near: caret), display: true)
    panel.makeKeyAndOrderFront(nil)
  }

  /// Puts a card just below the caret, or above it when there is no room, else where the full card opens.
  private static func place(_ size: NSSize, near caret: NSRect?) -> NSRect {
    let point = caret?.origin ?? NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    guard let frame = screen?.visibleFrame else { return NSRect(origin: .zero, size: size) }
    let size = NSSize(width: min(size.width, frame.width - 32), height: min(size.height, frame.height - 32))
    var origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY + min(484, frame.height - 32) / 2 + frame.height / 10 - size.height)
    if let caret {
      origin = NSPoint(x: caret.minX - 12, y: caret.minY - 4 - size.height)
      if origin.y < frame.minY { origin.y = caret.maxY + 4 }
    }
    origin.x = min(max(origin.x, frame.minX), frame.maxX - size.width)
    origin.y = min(max(origin.y, frame.minY), frame.maxY - size.height)
    return NSRect(origin: origin, size: size)
  }

  /// The focused app's text caret in AppKit screen coordinates, when it reports one.
  private static func caretRect() -> NSRect? {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.1)
    var focused: CFTypeRef?
    var range: CFTypeRef?
    var bounds: CFTypeRef?
    var rect = CGRect.zero
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID(),
          AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
          let range,
          AXUIElementCopyParameterizedAttributeValue(element as! AXUIElement, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                     range, &bounds) == .success,
          let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
          AXValueGetValue(bounds as! AXValue, .cgRect, &rect),
          // Chromium apps without a web accessibility tree report an empty box at the window edge.
          rect.height > 0, let primary = NSScreen.screens.first else { return nil }
    return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
  }

  /// The last character before the caret, "" at the start of a field, or nil when the focused app does not say.
  private static func textBeforeCaret() -> String? {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.1)
    var focused: CFTypeRef?
    var count: CFTypeRef?
    var range: CFTypeRef?
    var text: CFTypeRef?
    var selection = CFRange()
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
    let element = focused as! AXUIElement
    // Only text elements count characters; Chromium reports a caret on buttons too.
    guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
          AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
          let range, CFGetTypeID(range) == AXValueGetTypeID(),
          AXValueGetValue(range as! AXValue, .cfRange, &selection) else { return nil }
    guard selection.location > 0 else { return "" }
    // Two UTF-16 units, so an emoji before the caret is read whole.
    var before = CFRange(location: max(0, selection.location - 2), length: min(2, selection.location))
    guard let value = AXValueCreate(.cfRange, &before),
          AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, value, &text) == .success
    else { return nil }
    return (text as? String).map { $0.last.map(String.init) ?? "" }
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
    openItem = menu.addItem(withTitle: "Open omoji", action: #selector(openPicker), keyEquivalent: "")
    openItem.target = self
    menu.addItem(withTitle: "Change Shortcut…", action: #selector(changeShortcut), keyEquivalent: "").target = self
    cardItem = menu.addItem(withTitle: "Compact Card", action: #selector(toggleCard(_:)), keyEquivalent: "")
    cardItem.target = self
    cardItem.state = model.picker.card == .compact ? .on : .off
    colonItem = menu.addItem(withTitle: "Type : to Search Emoji", action: #selector(toggleColon(_:)), keyEquivalent: "")
    colonItem.target = self
    colonItem.state = UserDefaults.standard.bool(forKey: "colonTrigger") ? .on : .off
    loginItem = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
    loginItem.target = self
    loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit omoji", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusItem.menu = menu
  }

  @objc private func openPicker() { model.picker.open() }

  @objc private func toggleCard(_ item: NSMenuItem) {
    setCard(item.state != .on)
  }

  private func setCard(_ compact: Bool) {
    if (model.picker.card == .compact) != compact && !model.picker.toggleCard() { NSSound.beep() }
    cardItem.state = model.picker.card == .compact ? .on : .off
    if model.picker.opened { show() }
  }

  @objc private func toggleColon(_ item: NSMenuItem) {
    setColon(item.state != .on)
  }

  private func setColon(_ on: Bool) {
    guard on else { return stopColon() }
    colonItem.state = .on
    UserDefaults.standard.set(true, forKey: "colonTrigger")
    if AXIsProcessTrusted() { return startColon() }
    skippedAccess = false
    model.picker.closeSettings()
    model.picker.opened ? show() : model.picker.open()
  }

  @objc private func changeShortcut() {
    let old = (code: currentKeyCode, modifiers: openItem.keyEquivalentModifierMask, key: openItem.keyEquivalent)
    unregisterHotKey()
    let alert = NSAlert()
    alert.messageText = "Type the new shortcut"
    alert.informativeText = "Use Command, Control, or Option with a key. Press Escape to cancel."
    alert.addButton(withTitle: "Cancel")
    var recorded: NSEvent?
    let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if Int(event.keyCode) == kVK_Escape {
        NSApp.abortModal()
      } else if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
        recorded = event
        NSApp.stopModal()
      }
      return nil
    }
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
    if let monitor { NSEvent.removeMonitor(monitor) }
    guard let event = recorded, let key = event.characters(byApplyingModifiers: [])?.lowercased(), !key.isEmpty else {
      setHotKey(old.code, old.modifiers, old.key)
      return
    }
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    guard setHotKey(UInt32(event.keyCode), modifiers, key) else {
      let failed = NSAlert()
      failed.messageText = "That shortcut is not available"
      failed.informativeText = "Another app or macOS uses it. omoji keeps the old shortcut."
      failed.runModal()
      setHotKey(old.code, old.modifiers, old.key)
      return
    }
    UserDefaults.standard.set(Int(event.keyCode), forKey: "hotKeyCode")
    UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hotKeyModifiers")
    UserDefaults.standard.set(key, forKey: "hotKeyEquivalent")
  }

  @objc private func toggleLogin(_ item: NSMenuItem) {
    setLogin(SMAppService.mainApp.status != .enabled)
  }

  private func setLogin(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      NSLog("omoji: could not change Open at Login: %@", String(describing: error))
    }
    loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }

  private func installHotKeyHandler() {
    var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
      let delegate = Unmanaged<AppDelegate>.fromOpaque(data!).takeUnretainedValue()
      DispatchQueue.main.async { delegate.toggle() }
      return noErr
    }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
  }

  private var currentKeyCode: UInt32 = UInt32(kVK_ANSI_E)

  /// Registers the global shortcut and shows it on the menu item; returns false when another app holds it.
  @discardableResult
  private func setHotKey(_ code: UInt32, _ modifiers: NSEvent.ModifierFlags, _ key: String) -> Bool {
    unregisterHotKey()
    currentKeyCode = code
    openItem.keyEquivalent = key
    openItem.keyEquivalentModifierMask = modifiers
    var carbon = 0
    if modifiers.contains(.command) { carbon |= cmdKey }
    if modifiers.contains(.control) { carbon |= controlKey }
    if modifiers.contains(.option) { carbon |= optionKey }
    if modifiers.contains(.shift) { carbon |= shiftKey }
    let id = EventHotKeyID(signature: OSType(0x6F6D6A69), id: 1)
    let status = RegisterEventHotKey(code, UInt32(carbon), id, GetApplicationEventTarget(), 0, &hotKey)
    if status != noErr { NSLog("omoji: the shortcut is taken by another app (%d)", status) }
    return status == noErr
  }

  private func unregisterHotKey() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
  }

  private func setUpColon(_ picker: OmojiCore.Picker) {
    colonModel = ColonModel(trigger: ColonTrigger(search: { [weak picker] in picker?.search($0) ?? [] }, textBeforeCaret: Self.textBeforeCaret))
    colonPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    colonPanel.isOpaque = false
    colonPanel.backgroundColor = .clear
    colonPanel.hasShadow = true
    colonPanel.level = .popUpMenu
    colonPanel.ignoresMouseEvents = true
    colonPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    colonPanel.isReleasedWhenClosed = false
    let colonHost = NSHostingView(rootView: ColonView(model: colonModel))
    colonHost.sizingOptions = []
    colonPanel.contentView = colonHost
    colonModel.onHeight = { [weak self] height in
      guard let self else { return }
      self.colonHeight = height
      if self.colonModel.trigger.visible { self.colonPanel.setFrame(Self.place(NSSize(width: 320, height: height), near: self.colonCaret), display: true) }
    }
    // A swipe or Mission Control can switch apps without a key or click, so fix the text in the app the user left.
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                      object: nil, queue: .main) { [weak self] _ in self?.endColon() }
    // A Space switch inside one app moves focus to another window, where the held count means nothing.
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
      guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == self.colonApp else { return }
      self.colonModel.trigger.reset()
      self.refreshColon()
    }
  }

  /// Puts the real ":name" back in the app where the query started and stops following it.
  private func endColon() {
    if case let .replace(deleting, text, _) = colonModel.trigger.handle(.escape) {
      Self.type(text, deleting: deleting) { [app = colonApp] in $0.postToPid(app) }
    }
    colonModel.trigger.reset()
    refreshColon()
  }

  private func startColon() {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: CGEventMask(mask), callback: { proxy, type, event, data in
      Unmanaged<AppDelegate>.fromOpaque(data!).takeUnretainedValue().colonEvent(proxy, type, event)
    }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
      stopColon()
      let alert = NSAlert()
      alert.messageText = "omoji needs Accessibility"
      alert.informativeText = "Allow omoji in System Settings › Privacy & Security › Accessibility, then turn on Type : to Search Emoji again."
      alert.runModal()
      return
    }
    colonTap = tap
    colonSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), colonSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func stopColon() {
    colonItem.state = .off
    UserDefaults.standard.set(false, forKey: "colonTrigger")
    if let colonTap {
      CGEvent.tapEnable(tap: colonTap, enable: false)
      CFRunLoopRemoveSource(CFRunLoopGetMain(), colonSource, .commonModes)
      CFMachPortInvalidate(colonTap)
    }
    colonTap = nil
    colonSource = nil
    colonModel.trigger.reset()
    refreshColon()
  }

  private func colonEvent(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      colonModel.trigger.reset()
      refreshColon()
      if let colonTap { CGEvent.tapEnable(tap: colonTap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    guard event.getIntegerValueField(.eventSourceUserData) != Self.typedMark, !panel.isKeyWindow,
          app != Bundle.main.bundleIdentifier, !Self.terminals.contains(app) else { return Unmanaged.passUnretained(event) }
    let trigger = colonModel.trigger
    let tracking = trigger.query != nil
    // Press-and-hold drops letter repeats in the app, so counting them would delete text before the colon later.
    if tracking, type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
       case .text = Self.colonKey(event) { return nil }
    let action = trigger.handle(type == .keyDown ? Self.colonKey(event) : .other)
    if !tracking && trigger.query != nil { colonApp = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0 }
    if tracking || trigger.query != nil { DispatchQueue.main.async { self.refreshColon() } }
    switch action {
    case .pass: return Unmanaged.passUnretained(event)
    case .consume: return nil
    case let .insert(emoji, deleting, query):
      Self.type(emoji, deleting: deleting) { $0.tapPostEvent(proxy) }
      DispatchQueue.main.async { self.model.picker.remember(query, emoji) }
      return nil
    case let .replace(deleting, text, replay):
      // Hold this key back and send it again after the text, so it lands in order.
      Self.type(text, deleting: deleting) { $0.tapPostEvent(proxy) }
      if replay, let copy = event.copy() { copy.tapPostEvent(proxy) }
      return nil
    }
  }

  private func refreshColon() {
    colonModel.objectWillChange.send()
    guard colonModel.trigger.visible else {
      colonPanel.orderOut(nil)
      return
    }
    if !colonPanel.isVisible {
      colonCaret = Self.caretRect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
      colonPanel.setFrame(Self.place(NSSize(width: 320, height: colonHeight), near: colonCaret), display: true)
      colonPanel.orderFrontRegardless()
    }
  }

  private static func colonKey(_ event: CGEvent) -> ColonKey {
    let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskShift, .maskAlternate])
    if code == kVK_Delete {
      switch modifiers.subtracting(.maskShift) {
      case []: return .backspace
      case .maskAlternate: return .deleteWord
      default: return .other
      }
    }
    // Shift-Up, Command-Return and similar keep their normal meaning in the app.
    if [kVK_UpArrow, kVK_DownArrow, kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab].contains(code),
       !modifiers.isEmpty { return .other }
    switch code {
    case kVK_UpArrow: return .up
    case kVK_DownArrow: return .down
    case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
    case kVK_Tab: return .tab
    case kVK_Escape: return .escape
    default:
      guard event.flags.intersection([.maskCommand, .maskControl]).isEmpty,
            let characters = NSEvent(cgEvent: event)?.characters, characters.count == 1,
            // Arrow, Home, Page and F keys move the caret or do nothing; they are not text.
            !(0xF700...0xF8FF).contains(characters.unicodeScalars.first!.value) else { return .other }
      return .text(characters.first!)
    }
  }

  /// Deletes characters before the caret, then types text into the focused app without touching the clipboard.
  /// Posting through the tap puts the events ahead of keys the user already pressed.
  private static func type(_ text: String, deleting count: Int, post: (CGEvent) -> Void) {
    let source = CGEventSource(stateID: .privateState)
    for _ in 0..<count {
      for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: down) else { continue }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: typedMark)
        post(event)
      }
    }
    var chunk = ""
    // Some apps read at most 20 UTF-16 units from one key event.
    for character in text + "\u{0}" {
      guard character == "\u{0}" || chunk.utf16.count + character.utf16.count > 20 else {
        chunk.append(character)
        continue
      }
      let units = Array(chunk.utf16)
      for down in [true, false] where !units.isEmpty {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: down) else { continue }
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: typedMark)
        post(event)
      }
      chunk = String(character)
    }
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
