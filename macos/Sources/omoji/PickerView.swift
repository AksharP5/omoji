import AppKit
import OmojiCore
import SwiftUI

struct PickerView: View {
  @ObservedObject var model: Model
  @FocusState private var searchFocused: Bool
  @State private var pointerOrigin = NSEvent.mouseLocation
  private let rowHeight: CGFloat = 52

  private var picker: OmojiCore.Picker { model.picker }

  var body: some View {
    let query = Binding(get: { picker.query }, set: { picker.query = $0 })
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField(picker.strings.t("search"), text: query)
          .textFieldStyle(.plain)
          .font(.system(size: 22))
          .focused($searchFocused)
          .disabled(picker.settingsOpen)
          .accessibilityLabel(picker.strings.t("search"))
        Button { picker.toggleSettings() } label: { Image(systemName: "gearshape") }
          .buttonStyle(.borderless)
          .focusable(false)
          .help(picker.strings.t("settingsShortcut").replacingOccurrences(of: "Ctrl+,", with: "⌘,"))
          .accessibilityLabel(picker.strings.t("settings"))
      }
      .frame(height: 54)
      Divider()
      GeometryReader { geometry in
        ZStack {
          results
          if let text = picker.emptyText {
            Text(text).font(.title3).foregroundStyle(.secondary)
          }
        }
        .onAppear { picker.pageSize = max(1, Int(geometry.size.height / rowHeight)) }
        .onChange(of: geometry.size.height) { picker.pageSize = max(1, Int($0 / rowHeight)) }
      }
      .opacity(picker.settingsOpen ? 0.65 : 1)
      if let status = picker.statusText {
        Text(status).font(.callout).fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .overlay(alignment: .topTrailing) {
      if picker.settingsOpen {
        ZStack(alignment: .topTrailing) {
          Color.clear.contentShape(Rectangle()).onTapGesture { picker.closeSettings() }
          SettingsView(model: model).padding(.top, 62).padding(.trailing, 16)
        }
      }
    }
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
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
      ScrollView {
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
    return HStack(spacing: 12) {
      Text(emoji.e).font(.system(size: 27)).frame(width: 36)
      Text(emoji.n).font(.system(size: 17)).lineLimit(1).truncationMode(.tail)
      Spacer()
      if selected {
        Text(picker.actionHint).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: rowHeight)
    .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
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
    }
    .padding(8)
    .frame(width: 280)
    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
  }
}
