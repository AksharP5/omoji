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
  property string historyPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omoji/history.json"
  property string preferencesPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omoji/config.json"
  readonly property string defaultAction: preferences.error ? "copy" : preferences.defaultAction
  property alias preferencesReady: preferences.ready
  property alias preferencesError: preferences.error
  property bool settingsOpen: false
  property var pasteCommand: ["wtype", "-M", "shift", "-k", "Insert", "-m", "shift"]
  property var copyCommand: ["wl-copy", "--type", "text/plain"]
  readonly property bool historyReady: history.ready
  readonly property string learningError: history.error
  readonly property int selectedIndex: resultList.currentIndex
  readonly property int rowHeight: Math.max(Style.space(52), Style.font.title + Style.spacing.md * 2)
  readonly property int padding: Style.spacing.panelPadding

  signal copied(string emoji)
  signal pasted(string emoji)

  function open(payloadJson) {
    root.opening += 1
    root.error = ""
    root.settingsOpen = false
    searchInput.text = ""
    root.opened = true
    root.rebuild()
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell) root.shell.hide(root.manifest ? root.manifest.id : "akshar.omoji")
  }

  function rebuild() {
    root.results = EmojiSearch.search(root.catalog, root.filterText, history.choices)
    resultList.currentIndex = root.results.length ? 0 : -1
    pointerGate.reset()
    resultList.positionViewAtBeginning()
  }

  function moveSelection(delta) {
    if (!root.results.length) return
    resultList.currentIndex = (resultList.currentIndex + delta + root.results.length) % root.results.length
    resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
    pointerGate.reset()
  }

  function activate(index, action) {
    if (copyProcess.running || pasteDelay.running || pasteProcess.running || (!preferences.ready && !preferences.error) || (!history.ready && !history.error) || index < 0 || index >= root.results.length) return
    copyProcess.action = action === "copy" ? "copy" : root.defaultAction
    copyProcess.query = root.filterText
    copyProcess.emoji = root.results[index].e
    copyProcess.opening = root.opening
    // Bash reports an unavailable clipboard command as an exit code; Process
    // itself has no QML signal for a command that fails to start.
    copyProcess.command = ["bash", "-c", 'exec "$@"', "omoji-copy"].concat(root.copyCommand, [copyProcess.emoji])
    copyProcess.running = true
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (root.settingsOpen) {
        root.settingsOpen = false
        searchInput.forceActiveFocus()
      } else if (searchInput.text) searchInput.clear()
      else root.dismiss()
    } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_Comma) {
      root.settingsOpen = !root.settingsOpen
      if (root.settingsOpen) actionOptions.forceActiveFocus()
      else searchInput.forceActiveFocus()
    } else if (event.key === Qt.Key_Down || (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_N)) {
      root.moveSelection(1)
    } else if (event.key === Qt.Key_Up || (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_P)) {
      root.moveSelection(-1)
    } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
      root.moveSelection((event.key === Qt.Key_PageDown ? 1 : -1) * Math.max(1, Math.floor(resultList.height / root.rowHeight)))
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activate(resultList.currentIndex, event.modifiers & Qt.ControlModifier ? "copy" : root.defaultAction)
    } else {
      return
    }
    event.accepted = true
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

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
        if (root.opened) root.rebuild()
      } catch (failure) {
        root.error = strings.t("catalogFailed")
        console.warn("omoji:", failure)
      }
    }
    onLoadFailed: root.error = strings.t("catalogFailed")
  }

  Process {
    id: copyProcess
    property string action: "copy"
    property string query: ""
    property string emoji: ""
    property int opening: 0
    onExited: function(code) {
      if (code !== 0) {
        if (copyProcess.opening === root.opening) root.error = strings.t("copyFailed")
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
        root.opened = true
        root.error = strings.t("pasteFailed")
        Qt.callLater(function() { searchInput.forceActiveFocus() })
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
      onActivated: root.activate(resultList.currentIndex, "copy")
    }

    Rectangle { anchors.fill: parent; color: Commons.Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      objectName: "omoji-card"
      width: Math.min(Style.space(640), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(484), panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
      padding: root.padding

      MouseArea { anchors.fill: parent; onClicked: searchInput.forceActiveFocus() }

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
          height: Style.space(54)

          TextInput {
            id: searchInput
            objectName: "emoji-search"
            anchors.left: parent.left
            anchors.right: settingsButton.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            verticalAlignment: TextInput.AlignVCenter
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            color: Commons.Color.menu.text
            selectionColor: Commons.Color.menu.selectedBackground
            selectedTextColor: Commons.Color.menu.selectedText
            maximumLength: 160
            clip: true
            focus: true
            Accessible.name: strings.t("search")
            onTextChanged: {
              root.error = ""
              root.rebuild()
            }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) { root.handleKey(event) }

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: !searchInput.text && !searchInput.preeditText
              text: strings.t("search")
              textFormat: Text.PlainText
              color: Commons.Color.menu.text
              opacity: 0.55
              font: searchInput.font
            }
          }
          Button {
            id: settingsButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("settings")
            tooltipText: strings.t("settingsShortcut")
            fontSize: Style.font.caption
            fontFamily: Style.font.menuFamily
            foreground: Commons.Color.menu.text
            focusable: true
            selected: root.settingsOpen
            onClicked: {
              root.settingsOpen = !root.settingsOpen
              if (root.settingsOpen) actionOptions.forceActiveFocus()
              else searchInput.forceActiveFocus()
            }
          }
        }

        Item {
          id: settingsRow
          visible: root.settingsOpen
          width: parent.width
          height: visible ? Style.space(48) : 0
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("defaultAction")
            textFormat: Text.PlainText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            color: Commons.Color.menu.text
          }
          ButtonGroup {
            id: actionOptions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: [{ value: "copy", label: strings.t("copy") }, { value: "paste", label: strings.t("paste") }]
            value: root.defaultAction
            enabled: preferences.ready && !preferences.error
            onChanged: function(value) { preferences.choose(value) }
            Keys.onEscapePressed: {
              root.settingsOpen = false
              searchInput.forceActiveFocus()
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Commons.Color.menu.border; opacity: 0.35 }

        Item {
          width: parent.width
          height: parent.height - searchHeader.height - settingsRow.height - status.height - 1
            - parent.spacing * (2 + (settingsRow.visible ? 1 : 0) + (status.visible ? 1 : 0))

          ListView {
            id: resultList
            objectName: "emoji-results"
            anchors.fill: parent
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
                width: Style.space(36)
                horizontalAlignment: Text.AlignHCenter
                text: modelData.e
                textFormat: Text.PlainText
                font.family: "Noto Color Emoji"
                font.pixelSize: Style.space(27)
              }

              Text {
                id: actionHint
                visible: parent.selected
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("enterAction").arg(strings.t(root.defaultAction))
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
            anchors.centerIn: parent
            visible: !root.results.length
            text: root.error || strings.t("empty")
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
            text: root.error || (preferences.error ? strings.t("preferencesFailed") : history.error ? strings.t("learningFailed") : "")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Commons.Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
