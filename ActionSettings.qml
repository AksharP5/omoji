import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

FocusScope {
  id: root

  property var strings
  property string value: "paste"
  property bool choicesEnabled: true
  signal changed(string value)
  signal closed()
  implicitWidth: Style.space(280)
  implicitHeight: content.implicitHeight + Style.spacing.sm * 2 + 2

  function choose(action) { root.changed(action) }
  function focusChoice() {
    if (root.choicesEnabled) choices.itemAt(root.value === "paste" ? 0 : 1).forceActiveFocus()
    else root.forceActiveFocus()
  }
  onChoicesEnabledChanged: if (visible) root.focusChoice()

  Keys.onEscapePressed: root.closed()

  BorderSurface {
    anchors.fill: parent
    color: Commons.Color.menu.background
    radius: Style.cornerRadius
    borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(1)))
  }
  MouseArea { anchors.fill: parent; onClicked: root.focusChoice() }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.sm + 1
    spacing: Style.spacing.sm

    Text {
      width: parent.width - Style.spacing.md * 2
      x: Style.spacing.md
      height: implicitHeight + Style.spacing.md
      verticalAlignment: Text.AlignVCenter
      text: root.strings.t("defaultAction")
      textFormat: Text.PlainText
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
      color: Commons.Color.menu.text
      opacity: 0.7
    }
    Repeater {
      id: choices
      model: ["paste", "copy"]
      delegate: Button {
        id: choice
        required property string modelData
        required property int index
        objectName: "omoji-action-" + modelData
        width: content.width
        height: Math.max(Style.space(58), labels.implicitHeight + Style.spacing.md * 2)
        selected: root.value === modelData
        enabled: root.choicesEnabled
        focusable: true
        foreground: Commons.Color.menu.text
        Accessible.role: Accessible.RadioButton
        Accessible.name: root.strings.t(modelData)
        Accessible.description: root.strings.t(modelData + "Description")
        Accessible.checked: selected
        onClicked: root.choose(modelData)
        Keys.onUpPressed: choices.itemAt((index + 1) % 2).forceActiveFocus()
        Keys.onDownPressed: choices.itemAt((index + 1) % 2).forceActiveFocus()
        Keys.onTabPressed: choices.itemAt((index + 1) % 2).forceActiveFocus()
        Keys.onBacktabPressed: choices.itemAt((index + 1) % 2).forceActiveFocus()

        Text {
          id: check
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(16)
          text: choice.selected ? "\u2713" : ""
          textFormat: Text.PlainText
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          color: Commons.Color.menu.selectedText
        }
        Column {
          id: labels
          anchors.left: check.right
          anchors.leftMargin: Style.spacing.sm
          anchors.right: shortcut.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm
          Text {
            width: parent.width
            text: root.strings.t(choice.modelData)
            textFormat: Text.PlainText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            color: Commons.Color.menu.text
          }
          Text {
            width: parent.width
            text: root.strings.t(choice.modelData + "Description")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            color: Commons.Color.menu.text
            opacity: 0.7
          }
        }
        Text {
          id: shortcut
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          text: choice.modelData === "copy" ? "C" : "P"
          textFormat: Text.PlainText
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          color: Commons.Color.menu.text
          opacity: 0.6
        }
      }
    }
  }
}
