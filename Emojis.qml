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
  property alias filterText: searchInput.text
  property var catalog: []
  property var results: []
  property string error: ""
  property string historyPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/oma-emoji/history.json"
  property var copyCommand: ["wl-copy", "--type", "text/plain"]
  readonly property bool historyReady: history.ready
  readonly property string learningError: history.error
  readonly property int selectedIndex: resultList.currentIndex
  readonly property int rowHeight: Math.max(Style.space(52), Style.font.title + Style.spacing.md * 2)
  readonly property int padding: Style.spacing.panelPadding

  signal copied(string emoji)

  function open(payloadJson) {
    root.error = ""
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
    if (root.shell) root.shell.hide(root.manifest ? root.manifest.id : "akshar.oma-emoji")
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

  function activate(index) {
    if (copyProcess.running || (!history.ready && !history.error) || index < 0 || index >= root.results.length) return
    copyProcess.query = root.filterText
    copyProcess.emoji = root.results[index].e
    copyProcess.command = root.copyCommand.concat([copyProcess.emoji])
    copyProcess.running = true
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (searchInput.text) searchInput.clear()
      else root.dismiss()
    } else if (event.key === Qt.Key_Down || (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_N)) {
      root.moveSelection(1)
    } else if (event.key === Qt.Key_Up || (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_P)) {
      root.moveSelection(-1)
    } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
      root.moveSelection((event.key === Qt.Key_PageDown ? 1 : -1) * Math.max(1, Math.floor(resultList.height / root.rowHeight)))
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activate(resultList.currentIndex)
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

  FileView {
    path: Qt.resolvedUrl("emojis.json")
    onLoaded: {
      try {
        root.catalog = EmojiSearch.parseCatalog(text())
        if (root.opened) root.rebuild()
      } catch (failure) {
        root.error = strings.t("catalogFailed")
        console.warn("Oma Emoji:", failure)
      }
    }
    onLoadFailed: root.error = strings.t("catalogFailed")
  }

  Process {
    id: copyProcess
    property string query: ""
    property string emoji: ""
    onExited: function(code) {
      if (code !== 0) {
        root.error = strings.t("copyFailed")
        return
      }
      history.remember(copyProcess.query, copyProcess.emoji)
      root.copied(copyProcess.emoji)
      root.dismiss()
    }
  }

  PointerMoveGate { id: pointerGate; referenceItem: card }

  OverlayWindow {
    id: panel
    objectName: "oma-emoji-window"
    shown: root.opened
    WlrLayershell.namespace: "oma-emoji"

    Rectangle { anchors.fill: parent; color: Commons.Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      objectName: "oma-emoji-card"
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
          width: parent.width
          height: Style.space(54)

          TextInput {
            id: searchInput
            objectName: "emoji-search"
            anchors.fill: parent
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
        }

        Rectangle { width: parent.width; height: 1; color: Commons.Color.menu.border; opacity: 0.35 }

        Item {
          width: parent.width
          height: parent.height - Style.space(54) - Style.space(30) - 2 - parent.spacing * 4

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
                anchors.left: glyph.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: parent.right
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

        Rectangle { width: parent.width; height: 1; color: Commons.Color.menu.border; opacity: 0.35 }

        Item {
          width: parent.width
          height: Style.space(30)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.error || (history.error ? strings.t("learningFailed") : "Oma Emoji")
            textFormat: Text.PlainText
            color: Commons.Color.menu.text
            opacity: 0.6
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("copy")
            textFormat: Text.PlainText
            color: Commons.Color.menu.text
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
