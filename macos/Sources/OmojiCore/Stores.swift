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
    let temporary = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + "." + UUID().uuidString)
    guard FileManager.default.createFile(atPath: temporary.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    if rename(temporary.path, url.path) != 0 {
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

public final class PreferencesStore {
  private struct Config: Codable {
    let version: Int
    let defaultAction: Action
  }

  let url: URL
  public private(set) var defaultAction = Action.paste
  public private(set) var error: String?

  public init(url: URL) {
    self.url = url
    reload()
  }

  /// Picks up edits made while the picker was closed.
  func reload() {
    do {
      try StateFile.prepare(url, initial: "{\"version\":1,\"defaultAction\":\"paste\"}\n")
      let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
      guard config.version == 1 else { throw EngineError(description: "Unsupported preferences") }
      defaultAction = config.defaultAction
      error = nil
    } catch {
      defaultAction = .copy
      self.error = String(describing: error)
    }
  }

  func choose(_ action: Action) -> Bool {
    guard error == nil else { return false }
    if action == defaultAction { return true }
    do {
      try StateFile.write("{\"version\":1,\"defaultAction\":\"\(action.rawValue)\"}\n", to: url)
      defaultAction = action
      return true
    } catch {
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
