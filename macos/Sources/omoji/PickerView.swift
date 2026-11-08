import AppKit
import OmojiCore
import SwiftUI

struct PickerView: View {
  @ObservedObject var model: Model
  @FocusState private var searchFocused: Bool
  @State private var pointerOrigin = NSEvent.mouseLocation

  private var picker: OmojiCore.Picker { model.picker }
  private var compact: Bool { picker.card == .compact }
  private var rowHeight: CGFloat { compact ? 40 : 52 }
  private var padding: CGFloat { compact ? 12 : 16 }
  private var headerHeight: CGFloat { compact ? 22 : 30 }

  var body: some View {
    let query = Binding(get: { picker.query }, set: { picker.query = $0 })
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField(picker.strings.t("search"), text: query)
          .textFieldStyle(.plain)
          .font(.system(size: compact ? 16 : 22))
          .focused($searchFocused)
          .disabled(picker.settingsOpen)
          .accessibilityLabel(picker.strings.t("search"))
        Button { picker.toggleSettings() } label: { Image(systemName: "gearshape") }
          .buttonStyle(.borderless)
          .focusable(false)
          .help(picker.strings.t("settingsShortcut").replacingOccurrences(of: "Ctrl+,", with: "⌘,"))
          .accessibilityLabel(picker.strings.t("settings"))
      }
      .frame(height: headerHeight)
      Divider()
      GeometryReader { geometry in
        ZStack {
          results
          if let text = picker.emptyText {
            Text(text).font(compact ? .body : .title3).foregroundStyle(.secondary)
          }
        }
        .onAppear { picker.pageSize = max(1, Int(geometry.size.height / rowHeight)) }
        .onChange(of: geometry.size.height) { picker.pageSize = max(1, Int($0 / rowHeight)) }
      }
      .frame(height: compact ? CGFloat(picker.settingsOpen || model.needsAccess ? 9 : min(6, max(1, picker.results.count))) * rowHeight : nil)
      .opacity(picker.settingsOpen ? 0.65 : 1)
      if let status = picker.statusText {
        Text(status).font(.callout).fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(padding)
    .overlay(alignment: .topTrailing) {
      if picker.settingsOpen {
        ZStack(alignment: .topTrailing) {
          Color.clear.contentShape(Rectangle()).onTapGesture { picker.closeSettings() }
          SettingsView(model: model).padding(.top, padding + headerHeight + 6).padding(.trailing, padding)
        }
      }
    }
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      if model.needsAccess {
        AccessView(model: model).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
      }
    }
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
    .fixedSize(horizontal: false, vertical: compact)
    .reportHeight(model.onHeight)
    .frame(maxHeight: .infinity, alignment: .top)
    .onChange(of: picker.opened) { if $0 { searchFocused = true } }
    .onChange(of: picker.settingsOpen) {
      guard !$0 else { return }
      searchFocused = true
      // Focus selects all text in an AppKit field; keep the query and put the cursor after it, as on Omarchy.
      DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil) }
    }
    .onAppear { searchFocused = true }
  }

  private var results: some View {
    ScrollViewReader { proxy in
      ScrollView(showsIndicators: false) {
        LazyVStack(spacing: 0) {
          ForEach(Array(picker.results.enumerated()), id: \.offset) { index, emoji in
            row(index, emoji)
          }
        }
      }
      .onChange(of: picker.selectedIndex) { proxy.scrollTo($0) }
      .onChange(of: picker.results) { _ in
        pointerOrigin = NSEvent.mouseLocation
        proxy.scrollTo(picker.selectedIndex)
      }
      .onChange(of: picker.query) { _ in proxy.scrollTo(picker.selectedIndex) }
      .disabled(picker.settingsOpen)
    }
  }

  private func row(_ index: Int, _ emoji: Emoji) -> some View {
    let selected = index == picker.selectedIndex
    return EmojiRow(emoji: emoji, selected: selected, hint: picker.actionHint, compact: compact)
      .contentShape(Rectangle())
      .onContinuousHover {
        // Only a pointer that moves picks a row, so results never jump under a resting pointer.
        guard case .active = $0, NSEvent.mouseLocation != pointerOrigin else { return }
        pointerOrigin = NSEvent.mouseLocation
        picker.select(index)
      }
      .onTapGesture { picker.activate(index) }
      .id(index)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(emoji.n)
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

struct EmojiRow: View {
  let emoji: Emoji
  let selected: Bool
  let hint: String
  let compact: Bool

  var body: some View {
    HStack(spacing: compact ? 8 : 12) {
      Text(emoji.e).font(.system(size: compact ? 20 : 27)).frame(width: compact ? 28 : 36)
      Text(emoji.n).font(.system(size: compact ? 14 : 17)).lineLimit(1).truncationMode(.tail)
      Spacer()
      if selected {
        Text(hint).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, compact ? 8 : 12)
    .frame(height: compact ? 40 : 52)
    .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
  }
}

struct ColonView: View {
  @ObservedObject var model: ColonModel

  private var trigger: ColonTrigger { model.trigger }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(":" + (trigger.query ?? "")).font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 8)
      ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
          LazyVStack(spacing: 0) {
            ForEach(Array(trigger.results.enumerated()), id: \.offset) { index, emoji in
              EmojiRow(emoji: emoji, selected: index == trigger.selectedIndex, hint: "↵", compact: true)
                .id(index)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(emoji.n)
            }
          }
        }
        .frame(height: CGFloat(min(6, trigger.results.count)) * 40)
        .onChange(of: trigger.selectedIndex) { proxy.scrollTo($0) }
        .onChange(of: trigger.results) { _ in proxy.scrollTo(0) }
      }
    }
    .padding(8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    .fixedSize(horizontal: false, vertical: true)
    .reportHeight(model.onHeight)
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

extension View {
  func reportHeight(_ report: @escaping (CGFloat) -> Void) -> some View {
    background(GeometryReader { geometry in
      Color.clear.onAppear { report(geometry.size.height) }.onChange(of: geometry.size.height) { report($0) }
    })
  }
}

struct SettingsView: View {
  @ObservedObject var model: Model

  private var picker: OmojiCore.Picker { model.picker }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(picker.strings.t("defaultAction")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
      ForEach([Action.paste, Action.copy], id: \.self) { action in
        Button { picker.choose(action) } label: {
          HStack(spacing: 8) {
            Text(picker.defaultAction == action ? "✓" : "").frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
              Text(picker.strings.t(action.rawValue))
              Text(picker.strings.t(action.rawValue + "Description")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(action == .copy ? "C" : "P").font(.caption).foregroundStyle(.secondary)
          }
          .padding(12)
          .contentShape(Rectangle())
          .background(picker.settingsHighlight == action ? Color.accentColor.opacity(0.2) : .clear,
                      in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!picker.choicesEnabled)
        .accessibilityAddTraits(picker.defaultAction == action ? .isSelected : [])
      }
      Divider().padding(.horizontal, 12)
      ForEach(model.options, id: \.title) { option in
        Toggle(isOn: Binding(get: option.isOn, set: {
          option.set($0)
          model.objectWillChange.send()
        })) {
          Text(option.title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
      }
      HStack {
        Text("Shortcut")
        Spacer()
        Button { model.changeShortcut() } label: {
          Text(model.shortcut())
            .font(.system(.callout, design: .rounded).weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Change shortcut")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 2)
      .padding(.bottom, 4)
    }
    .padding(8)
    .frame(width: 280)
    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
  }
}

struct AccessView: View {
  @ObservedObject var model: Model

  var body: some View {
    VStack(spacing: 12) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
      Text("Allow omoji to type for you").font(.title3.weight(.semibold))
      Text("To paste emoji into your apps, macOS needs you to turn on omoji in System Settings › Privacy & Security › Accessibility. If omoji is already on there, remove it with − and add it again. macOS does this after each update.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Not Now") { model.skipAccess() }
        Button("Open Settings") { model.allowAccess() }.buttonStyle(.borderedProminent)
      }
    }
    .controlSize(.large)
    .frame(maxWidth: 360)
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
  }
}
