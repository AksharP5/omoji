import Foundation
import JavaScriptCore

public enum Action: String, Codable {
  case copy, paste
}

/// Creates a private state file once, like scripts/prepare-state, and writes it atomically.
enum StateFile {
  static func prepare(_ url: URL, initial: String) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    if !FileManager.default.fileExists(atPath: url.path) {
      let handle = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
      if handle < 0 { throw CocoaError(.fileWriteUnknown) }
      FileHandle(fileDescriptor: handle, closeOnDealloc: true).write(Data(initial.utf8))
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  static func write(_ text: String, to url: URL) throws {
    let destination = url.resolvingSymlinksInPath()
    let temporary = destination.deletingLastPathComponent().appendingPathComponent("." + destination.lastPathComponent + "." + UUID().uuidString)
    guard FileManager.default.createFile(atPath: temporary.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    if rename(temporary.path, destination.path) != 0 {
      try? FileManager.default.removeItem(at: temporary)
      throw CocoaError(.fileWriteUnknown)
    }
  }
}

public final class HistoryStore {
  let url: URL
  let engine: EmojiEngine
  var choices: JSValue
  public private(set) var error: String?

  public init(url: URL, engine: EmojiEngine) {
    self.url = url
    self.engine = engine
    choices = engine.emptyList()
    do {
      try StateFile.prepare(url, initial: "{\"version\":1,\"choices\":[]}\n")
      choices = try engine.call("parseHistory", [try String(contentsOf: url, encoding: .utf8)])
    } catch {
      self.error = String(describing: error)
      NSLog("omoji: keeping unreadable history untouched: %@ %@", url.path, self.error!)
    }
  }

  func remember(_ query: String, _ emoji: String) {
    guard error == nil else { return }
    do {
      choices = try engine.call("remember", [choices, query, emoji, (Date().timeIntervalSince1970 * 1000).rounded(.down)])
      try StateFile.write(engine.historyText(choices), to: url)
    } catch {
      self.error = "Cannot save history: \(error)"
      NSLog("omoji: %@ %@", self.error!, url.path)
    }
  }
}

public enum Card: String {
  case full, compact
}

public final class PreferencesStore {
  private struct Config: Codable {
    let version: Int
    let defaultAction: Action
  }

  let url: URL
  public private(set) var defaultAction = Action.paste
  public private(set) var card = Card.full
  public private(set) var error: String?
  private let json = JSContext()!

  public init(url: URL) {
    self.url = url
    reload()
  }

  /// Picks up edits made while the picker was closed.
  func reload() {
    do {
      try StateFile.prepare(url, initial: "{\"version\":1,\"defaultAction\":\"paste\"}\n")
      let data = try Data(contentsOf: url)
      let config = try JSONDecoder().decode(Config.self, from: data)
      guard config.version == 1 else { throw EngineError(description: "Unsupported preferences") }
      defaultAction = config.defaultAction
      card = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["card"] as? String == "compact" ? .compact : .full
      error = nil
    } catch {
      defaultAction = .copy
      card = .full
      self.error = String(describing: error)
    }
  }

  func choose(_ action: Action) -> Bool {
    reload()
    guard error == nil else { return false }
    if action == defaultAction { return true }
    guard save("defaultAction", action.rawValue) else { return false }
    defaultAction = action
    return true
  }

  public func choose(_ card: Card) -> Bool {
    guard error == nil else { return false }
    if card == self.card { return true }
    guard save("card", card.rawValue) else { return false }
    self.card = card
    return true
  }

  /// Rewrites only one key, so keys owned by the other platform or a newer version survive.
  private func save(_ key: String, _ value: String) -> Bool {
    do {
      let parser = json.objectForKeyedSubscript("JSON")!
      let config = parser.invokeMethod("parse", withArguments: [try String(contentsOf: url, encoding: .utf8)])!
      guard json.exception == nil, config.isObject, !config.isArray else { throw CocoaError(.fileReadCorruptFile) }
      config.setValue(value, forProperty: key)
      let text = parser.invokeMethod("stringify", withArguments: [config])!.toString()! + "\n"
      try StateFile.write(text, to: url)
      return true
    } catch {
      json.exception = nil
      self.error = "Cannot save preferences"
      return false
    }
  }
}

public struct Strings {
  private let table: [String: String]

  public init(json: Data) {
    table = (try? JSONDecoder().decode([String: String].self, from: json)) ?? [:]
  }

  public func t(_ key: String) -> String { table[key] ?? key }
}
