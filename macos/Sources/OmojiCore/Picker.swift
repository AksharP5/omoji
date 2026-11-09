import Foundation
import JavaScriptCore

public enum Key: Equatable {
  case escape, enter, up, down, pageUp, pageDown, tab, space
  case character(String)
}

public struct Modifiers: OptionSet {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let shift = Modifiers(rawValue: 1)
  public static let control = Modifiers(rawValue: 2)
  public static let command = Modifiers(rawValue: 4)
  public static let option = Modifiers(rawValue: 8)
}

public enum PasteResult {
  case pasted, failed, needsAccess
}

/// The picker's behavior, kept apart from AppKit so it can be tested without a window.
public final class Picker {
  public typealias Copy = (String) -> Bool
  public typealias Paste = (_ isCurrent: @escaping () -> Bool, _ done: @escaping (PasteResult) -> Void) -> Void

  let engine: EmojiEngine
  let history: HistoryStore
  let preferences: PreferencesStore
  public let strings: Strings
  private let copy: Copy
  private let paste: Paste
  private var catalog: JSValue?
  private var catalogError: String?
  private var opening = 0

  public private(set) var opened = false
  public private(set) var settingsOpen = false
  public private(set) var results: [Emoji] = []
  public private(set) var selectedIndex = -1
  public private(set) var settingsHighlight = Action.paste
  public private(set) var error: String?
  public var pageSize = 8
  public var onChange: () -> Void = {}
  public var onVisibilityChange: (Bool) -> Void = { _ in }

  public var query = "" {
    didSet {
      guard query != oldValue else { return }
      error = nil
      rebuild()
    }
  }

  public init(engine: EmojiEngine, catalog: String, history: HistoryStore, preferences: PreferencesStore,
              strings: Strings, copy: @escaping Copy, paste: @escaping Paste) {
    self.engine = engine
    self.history = history
    self.preferences = preferences
    self.strings = strings
    self.copy = copy
    self.paste = paste
    do {
      self.catalog = try engine.call("parseCatalog", [catalog])
    } catch {
      catalogError = strings.t("catalogFailed")
      NSLog("omoji: %@", String(describing: error))
    }
  }

  public var defaultAction: Action { preferences.error == nil ? preferences.defaultAction : .copy }
  public var card: Card { preferences.card }
  public var queryTooLong: Bool { query.utf16.count > EmojiEngine.queryLimit }
  public var choicesEnabled: Bool { preferences.error == nil }
  public var actionHint: String { strings.t("enterAction").replacingOccurrences(of: "%1", with: strings.t(defaultAction.rawValue)) }

  public var emptyText: String? {
    guard results.isEmpty else { return nil }
    return error ?? catalogError ?? strings.t(queryTooLong ? "searchTooLong" : "empty")
  }

  public var statusText: String? {
    if let error { return error }
    if preferences.error != nil { return strings.t("preferencesFailed") }
    if history.error != nil { return strings.t("learningFailed") }
    return nil
  }

  public func open() {
    opening += 1
    error = nil
    settingsOpen = false
    preferences.reload()
    opened = true
    if query.isEmpty { rebuild() } else { query = "" }
    onVisibilityChange(true)
    onChange()
  }

  public func dismiss() {
    settingsOpen = false
    guard opened else { return }
    opened = false
    onVisibilityChange(false)
    onChange()
  }

  func rebuild() {
    if let catalog, !queryTooLong {
      results = engine.search(catalog, query, history.choices)
    } else {
      results = []
    }
    selectedIndex = results.isEmpty ? -1 : 0
    onChange()
  }

  public func select(_ index: Int) {
    guard results.indices.contains(index), !settingsOpen else { return }
    selectedIndex = index
    onChange()
  }

  func moveSelection(_ delta: Int) {
    guard !results.isEmpty else { return }
    selectedIndex = ((selectedIndex + delta) % results.count + results.count) % results.count
    onChange()
  }

  public func activate(_ index: Int, _ action: Action? = nil) {
    guard opened, !settingsOpen, results.indices.contains(index) else { return }
    let action = action ?? defaultAction
    let query = self.query
    let emoji = results[index].e
    guard copy(emoji) else {
      error = strings.t("copyFailed")
      onChange()
      return
    }
    guard action == .paste else {
      history.remember(query, emoji)
      dismiss()
      return
    }
    let opening = self.opening
    dismiss()
    paste({ [weak self] in
      guard let self else { return false }
      return self.opening == opening && !self.opened
    }) { [weak self] result in
      guard let self else { return }
      if result == .pasted {
        self.history.remember(query, emoji)
      } else if self.opening == opening && !self.opened {
        self.opened = true
        self.error = self.strings.t(result == .needsAccess ? "pasteNeedsAccess" : "pasteFailed")
        self.onVisibilityChange(true)
        self.onChange()
      }
    }
  }

  /// Switches the card size; the picker draws it the next time it opens.
  public func toggleCard() -> Bool {
    let requested: Card = card == .compact ? .full : .compact
    preferences.reload()
    return preferences.choose(requested)
  }

  public func search(_ query: String) -> [Emoji] {
    guard let catalog else { return [] }
    return engine.search(catalog, query, history.choices)
  }

  public func remember(_ query: String, _ emoji: String) {
    history.remember(query, emoji)
  }

  public func toggleSettings() {
    settingsOpen.toggle()
    settingsHighlight = defaultAction
    onChange()
  }

  public func closeSettings() {
    settingsOpen = false
    onChange()
  }

  public func choose(_ action: Action) {
    guard settingsOpen, choicesEnabled else { return }
    if preferences.choose(action) { settingsOpen = false }
    onChange()
  }

  /// Returns true when the key was handled, so the search field should not see it.
  public func handle(_ key: Key, _ modifiers: Modifiers) -> Bool {
    let plain = modifiers.subtracting(.shift).isEmpty
    if key == .escape {
      if settingsOpen { closeSettings() } else if !query.isEmpty { query = "" } else { dismiss() }
      return true
    }
    if key == .character("?") || (key == .character(",") && (modifiers == .control || modifiers == .command)) {
      toggleSettings()
      return true
    }
    if settingsOpen {
      switch key {
      case .character("c") where plain: choose(.copy)
      case .character("p") where plain: choose(.paste)
      case .up, .down, .tab:
        settingsHighlight = settingsHighlight == .paste ? .copy : .paste
        onChange()
      case .enter where modifiers.isEmpty, .space: choose(settingsHighlight)
      default: break
      }
      return true
    }
    switch key {
    case .down where modifiers.isEmpty: moveSelection(1)
    case .up where modifiers.isEmpty: moveSelection(-1)
    case .character("n") where modifiers == .control: moveSelection(1)
    case .character("p") where modifiers == .control: moveSelection(-1)
    case .pageDown where modifiers.isEmpty: moveSelection(max(1, pageSize))
    case .pageUp where modifiers.isEmpty: moveSelection(-max(1, pageSize))
    case .enter:
      if !queryTooLong {
        activate(selectedIndex, modifiers.contains(.control) || modifiers.contains(.command)
          ? (defaultAction == .paste ? .copy : .paste) : defaultAction)
      }
    default: return false
    }
    return true
  }
}
