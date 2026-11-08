import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "EmojiSearch.js" as EmojiSearch

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property int opening: 0
  property alias filterText: searchInput.text
  property var catalog: []
  property var results: []
  property string error: ""
  property string catalogError: ""
  property string historyPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omoji/history.json"
  property string preferencesPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omoji/config.json"
  readonly property string defaultAction: preferences.error ? "copy" : preferences.defaultAction
  readonly property string alternateAction: root.defaultAction === "paste" ? "copy" : "paste"
  readonly property bool queryTooLong: searchInput.length > EmojiSearch.QUERY_LIMIT
  property alias preferencesReady: preferences.ready
  property alias preferencesError: preferences.error
  property bool settingsOpen: false
  property string payloadCard: ""
  readonly property bool compact: (root.payloadCard || preferences.card) === "compact"
  readonly property int compactRows: root.settingsOpen ? 6 : Math.max(1, Math.min(6, root.results.length))
  property var pasteCommand: ["wtype", "-M", "shift", "-k", "Insert", "-m", "shift"]
  property var copyCommand: ["wl-copy", "--type", "text/plain"]
  readonly property bool historyReady: history.ready
  readonly property string learningError: history.error
  readonly property int selectedIndex: resultList.currentIndex
  readonly property int rowHeight: Math.max(Style.space(root.compact ? 40 : 52), Style.font.title + Style.spacing.md * 2)
  readonly property int padding: Style.spacing.panelPadding

  signal copied(string emoji)
  signal pasted(string emoji)

  function open(payloadJson) {
    root.opening += 1
    root.error = ""
    root.settingsOpen = false
    root.payloadCard = ""
    try {
      var requested = JSON.parse(payloadJson).card
      if (requested === "compact" || requested === "full") root.payloadCard = requested
    } catch (failure) {}
    searchInput.text = ""
    root.opened = true
    root.rebuild()
    Qt.callLater(function() { if (!root.settingsOpen) searchInput.forceActiveFocus() })
  }

  function close() {
    root.settingsOpen = false
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell) root.shell.hide(root.manifest ? root.manifest.id : "akshar.omoji")
  }

  function rebuild() {
    var query = root.filterText
    // Derived QML bindings can update after the text-change handler.
    root.results = query.length > EmojiSearch.QUERY_LIMIT ? [] : EmojiSearch.search(root.catalog, query, history.choices)
    resultList.currentIndex = root.results.length ? 0 : -1
    pointerGate.reset()
    resultList.positionViewAtBeginning()
  }

  function moveSelection(delta) {
    if (!root.results.length) return
    resultList.currentIndex = (resultList.currentIndex + (delta % root.results.length) + root.results.length) % root.results.length
    resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
    pointerGate.reset()
  }

  function activate(index, action) {
    if (root.settingsOpen || searchPaste.running || copyProcess.running || pasteDelay.running || pasteProcess.running || (!preferences.ready && !preferences.error) || (!history.ready && !history.error) || index < 0 || index >= root.results.length) return
    copyProcess.action = action === "copy" || action === "paste" ? action : root.defaultAction
    copyProcess.query = root.filterText
    copyProcess.emoji = root.results[index].e
    copyProcess.opening = root.opening
    // Bash reports an unavailable clipboard command as an exit code; Process
    // itself has no QML signal for a command that fails to start.
    copyProcess.command = ["bash", "-c", 'exec "$@"', "omoji-copy"].concat(root.copyCommand, [copyProcess.emoji])
    copyProcess.running = true
  }

  function toggleSettings() {
    root.settingsOpen = !root.settingsOpen
    if (root.settingsOpen) Qt.callLater(function() { if (root.settingsOpen) actionSettings.focusChoice() })
    else root.closeSettings()
  }

  function closeSettings() {
    root.settingsOpen = false
    pointerGate.reset()
    Qt.callLater(function() { if (root.opened && !root.settingsOpen) searchInput.forceActiveFocus() })
  }

  function pasteSearch(primary) {
    if (!root.opened || root.settingsOpen || searchPaste.running) return
    root.error = ""
    searchInput.forceActiveFocus()
    searchPaste.opening = root.opening
    searchPaste.query = searchInput.text
    searchPaste.start = searchInput.selectionStart
    searchPaste.end = searchInput.selectionEnd
    searchPaste.command = ["bash", decodeURIComponent(String(Qt.resolvedUrl("scripts/read-clipboard")).replace(/^file:\/\//, ""))]
      .concat(primary ? ["--primary"] : [])
    searchPaste.running = true
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (root.settingsOpen) {
        root.closeSettings()
      } else if (searchInput.text) searchInput.clear()
      else root.dismiss()
    } else if (event.key === Qt.Key_Question || (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_Comma)) {
      root.toggleSettings()
    } else if (event.key === Qt.Key_Down || (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_N)) {
      root.moveSelection(1)
    } else if (event.key === Qt.Key_Up || (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_P)) {
      root.moveSelection(-1)
    } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
      root.moveSelection((event.key === Qt.Key_PageDown ? 1 : -1) * Math.max(1, Math.floor(resultList.height / root.rowHeight)))
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activate(resultList.currentIndex, event.modifiers & Qt.ControlModifier ? root.alternateAction : root.defaultAction)
    } else {
      return
    }
    event.accepted = true
  }

  Commons.Translations { id: translations; directory: Qt.resolvedUrl("i18n") }

  HistoryStore {
    id: history
    path: root.historyPath
    onChoicesChanged: if (root.opened) root.rebuild()
  }

  PreferencesStore { id: preferences; objectName: "omoji-preferences"; path: root.preferencesPath }

  FileView {
    path: Qt.resolvedUrl("emojis.json")
    onLoaded: {
      try {
        root.catalog = EmojiSearch.parseCatalog(text())
        root.catalogError = ""
        if (root.opened) root.rebuild()
      } catch (failure) {
        root.catalogError = translations.t("catalogFailed")
        console.warn("omoji:", failure)
      }
    }
    onLoadFailed: root.catalogError = translations.t("catalogFailed")
  }

  Process {
    id: searchPaste
    property int opening: 0
    property string query: ""
    property int start: 0
    property int end: 0
    stdout: StdioCollector { id: searchPasteOutput; waitForEnd: true }
    onExited: function(code) {
      if (!root.opened || root.settingsOpen || !searchInput.activeFocus || searchPaste.opening !== root.opening
          || searchInput.text !== searchPaste.query || searchInput.selectionStart !== searchPaste.start || searchInput.selectionEnd !== searchPaste.end) return
      var raw = searchPasteOutput.text
      var text = raw.replace(/[\r\n\u2028\u2029]+/g, " ")
      if (code !== 0 || raw.length > EmojiSearch.QUERY_LIMIT
          || text.length + searchInput.length - (searchPaste.end - searchPaste.start) > EmojiSearch.QUERY_LIMIT) {
        root.error = translations.t("searchPasteFailed")
        return
      }
      if (!text) return
      searchInput.cursorSelection.text = text
      searchInput.cursorPosition = searchPaste.start + text.length
    }
  }

  Process {
    id: copyProcess
    property string action: "copy"
    property string query: ""
    property string emoji: ""
    property int opening: 0
    onExited: function(code) {
      if (code !== 0) {
        if (copyProcess.opening === root.opening) root.error = translations.t("copyFailed")
        return
      }
      if (copyProcess.action === "copy") {
        history.remember(copyProcess.query, copyProcess.emoji)
        root.copied(copyProcess.emoji)
        if (root.opened && copyProcess.opening === root.opening) root.dismiss()
        return
      }
      // Never send an old selection into a newly opened picker or application.
      if (!root.opened || copyProcess.opening !== root.opening) return
      pasteProcess.query = copyProcess.query
      pasteProcess.emoji = copyProcess.emoji
      pasteProcess.opening = copyProcess.opening
      root.dismiss()
      pasteDelay.start()
    }
  }

  Timer {
    id: pasteDelay
    interval: 150
    onTriggered: {
      if (root.opened || pasteProcess.opening !== root.opening) return
      pasteProcess.command = ["bash", "-c", 'exec "$@"', "omoji-paste"].concat(root.pasteCommand)
      pasteProcess.running = true
    }
  }

  Process {
    id: pasteProcess
    property string query: ""
    property string emoji: ""
    property int opening: 0
    onExited: function(code) {
      if (code === 0) {
        history.remember(pasteProcess.query, pasteProcess.emoji)
        root.pasted(pasteProcess.emoji)
      } else if (pasteProcess.opening === root.opening && !root.opened) {
        root.settingsOpen = false
        root.opened = true
        root.error = translations.t("pasteFailed")
        Qt.callLater(function() { if (!root.settingsOpen) searchInput.forceActiveFocus() })
      }
    }
  }

  PointerMoveGate { id: pointerGate; referenceItem: card }

  OverlayWindow {
    id: panel
    objectName: "omoji-window"
    shown: root.opened
    WlrLayershell.namespace: "omarchy-emojis"

    Shortcut {
      sequences: ["Ctrl+Return", "Ctrl+Enter"]
      enabled: root.opened
      // Consume Ctrl+Enter in settings too, so a focused Button cannot treat
      // it as plain Enter. activate() only acts on the visible results view.
      onActivated: root.activate(resultList.currentIndex, root.alternateAction)
    }

    Shortcut {
      sequences: ["Ctrl+,", "?"]
      enabled: root.opened
      onActivated: root.toggleSettings()
    }

    Shortcut {
      sequence: "C"
      enabled: root.opened && root.settingsOpen && preferences.ready && !preferences.error
      onActivated: actionSettings.choose("copy")
    }
    Shortcut {
      sequence: "P"
      enabled: root.opened && root.settingsOpen && preferences.ready && !preferences.error
      onActivated: actionSettings.choose("paste")
    }

    Rectangle { anchors.fill: parent; color: Commons.Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.settingsOpen ? root.closeSettings() : root.dismiss() }

    BorderSurface {
      id: card
      objectName: "omoji-card"
      readonly property real maxHeight: panel.height - Style.gapsOut * 2
      readonly property real compactChrome: Math.ceil(contentTopInset + contentBottomInset + searchHeader.height + 1
        + Style.spacing.sm * (2 + (status.visible ? 1 : 0)) + status.height)
      width: Math.min(Style.space(root.compact ? 420 : 640), panel.width - Style.gapsOut * 2)
      height: root.compact ? Math.min(compactChrome + root.compactRows * root.rowHeight, maxHeight) : Math.min(Style.space(484), maxHeight)
      anchors.centerIn: parent
      // Keep the compact card's top still while its height follows the results.
      anchors.verticalCenterOffset: root.compact ? (height - Math.min(compactChrome + 6 * root.rowHeight, maxHeight)) / 2 : 0
      radius: Style.cornerRadius
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
      padding: root.padding

      MouseArea {
        objectName: "omoji-card-background"
        anchors.fill: parent
        onClicked: if (!root.settingsOpen) searchInput.forceActiveFocus()
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.sm

        Item {
          id: searchHeader
          width: parent.width
          height: Style.space(root.compact ? 40 : 54)

          Flickable {
            id: searchViewport
            objectName: "emoji-search-viewport"
            anchors.left: parent.left
            anchors.right: settingsButton.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            contentWidth: searchInput.width + searchInput.cursorRectangle.width
            contentHeight: searchInput.height
            clip: true
            interactive: false
            onWidthChanged: revealCursor()
            onContentWidthChanged: revealCursor()
            function revealCursor() {
              var rect = searchInput.cursorRectangle
              contentX = Math.max(0, Math.min(contentX, rect.x, contentWidth - width))
              if (contentX + width < rect.x + rect.width) contentX = rect.x + rect.width - width
              contentY = Math.max(0, Math.min(contentY, rect.y, contentHeight - height))
              if (contentY + height < rect.y + rect.height) contentY = rect.y + rect.height - height
            }
            TextEdit {
              id: searchInput
              enabled: !root.settingsOpen
              objectName: "emoji-search"
              width: Math.max(searchViewport.width, implicitWidth)
              height: Math.max(searchViewport.height, implicitHeight)
              verticalAlignment: TextEdit.AlignVCenter
              textFormat: TextEdit.PlainText
              wrapMode: TextEdit.NoWrap
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
              color: Commons.Color.menu.text
              selectionColor: Commons.Color.menu.selectedBackground
              selectedTextColor: Commons.Color.menu.selectedText
              focus: true
              activeFocusOnTab: true
              Accessible.name: translations.t("search")
              onCursorRectangleChanged: searchViewport.revealCursor()
              onTextChanged: {
                root.error = ""
                root.rebuild()
              }
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                  settingsButton.forceActiveFocus()
                  event.accepted = true
                } else if (event.matches(StandardKey.Paste)) {
                  root.pasteSearch(false)
                  event.accepted = true
                } else root.handleKey(event)
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton
                onClicked: function(mouse) {
                  searchInput.cursorPosition = searchInput.positionAt(mouse.x, mouse.y)
                  root.pasteSearch(true)
                }
              }

              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: !searchInput.text && !searchInput.preeditText
                text: translations.t("search")
                textFormat: Text.PlainText
                color: Commons.Color.menu.text
                opacity: 0.55
                font: searchInput.font
              }
            }
          }
          Button {
            id: settingsButton
            objectName: "omoji-settings-toggle"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "?"
            iconText: "\uf013"
            tooltipText: translations.t("settingsShortcut")
            Accessible.name: translations.t("settings")
            fontSize: Style.font.caption
            iconSize: Style.font.title
            foreground: Commons.Color.menu.text
            focusable: true
            onClicked: root.toggleSettings()
            Keys.onEscapePressed: function(event) {
              root.handleKey(event)
              if (root.opened && !root.settingsOpen) searchInput.forceActiveFocus()
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Commons.Color.menu.border; opacity: 0.35 }

        Item {
          width: parent.width
          height: parent.height - searchHeader.height - status.height - 1
            - parent.spacing * (2 + (status.visible ? 1 : 0))

          ListView {
            id: resultList
            enabled: !root.settingsOpen && !searchPaste.running
            opacity: root.settingsOpen ? 0.65 : 1
            objectName: "emoji-results"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.floor(parent.height / root.rowHeight) * root.rowHeight
            clip: true
            model: root.results
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: -1

            delegate: Rectangle {
              required property int index
              required property var modelData
              readonly property bool selected: index === resultList.currentIndex
              width: resultList.width
              height: root.rowHeight
              radius: Style.cornerRadius
              color: selected ? Commons.Color.menu.selectedBackground : "transparent"
              Accessible.role: Accessible.ListItem
              Accessible.name: modelData.n
              Accessible.selected: selected

              Text {
                id: glyph
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(root.compact ? 28 : 36)
                horizontalAlignment: Text.AlignHCenter
                text: modelData.e
                textFormat: Text.PlainText
                font.family: "Noto Color Emoji"
                font.pixelSize: Style.space(root.compact ? 20 : 27)
              }

              Text {
                id: actionHint
                visible: parent.selected
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: translations.t("enterAction").arg(translations.t(root.defaultAction))
                textFormat: Text.PlainText
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                color: Commons.Color.menu.text
                opacity: 0.7
              }

              Text {
                anchors.left: glyph.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: actionHint.visible ? actionHint.left : parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.n
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.title
                color: parent.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  if (pointerGate.moved(this, mouse)) resultList.currentIndex = index
                }
                onClicked: root.activate(index)
              }
            }
          }

          Text {
            objectName: "emoji-empty"
            anchors.centerIn: parent
            visible: !root.results.length
            text: root.error || root.catalogError || (root.queryTooLong ? translations.t("searchTooLong") : translations.t("empty"))
            textFormat: Text.PlainText
            color: Commons.Color.menu.text
            opacity: 0.6
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
          }
        }

        Item {
          id: status
          width: parent.width
          visible: statusText.text !== ""
          height: visible ? statusText.implicitHeight : 0
          Text {
            id: statusText
            width: parent.width
            text: root.error || (searchPaste.running ? translations.t("searchPasting") : preferences.error ? translations.t("preferencesFailed") : history.error ? translations.t("learningFailed") : "")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Commons.Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      MouseArea {
        objectName: "omoji-menu-dismiss-area"
        z: 1
        anchors.fill: parent
        visible: root.settingsOpen
        onClicked: root.closeSettings()
      }
      ActionSettings {
        id: actionSettings
        objectName: "omoji-action-settings"
        z: 2
        x: card.width - card.contentRightInset - width
        y: card.contentTopInset + searchHeader.height - Style.spacing.sm
        width: Math.min(implicitWidth, card.width - card.contentLeftInset - card.contentRightInset)
        visible: root.settingsOpen
        enabled: root.settingsOpen
        choicesEnabled: preferences.ready && !preferences.error
        strings: translations
        value: root.defaultAction
        onChanged: function(value) {
          if (preferences.choose(value)) root.closeSettings()
        }
        onClosed: root.closeSettings()
      }
    }
  }
}
