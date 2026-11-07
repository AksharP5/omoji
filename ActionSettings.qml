import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

FocusScope {
  id: root

  property var strings
  property string value: "paste"
  signal changed(string value)
  signal closed()

  function choose(action) {
    root.changed(action)
    choices.itemAt(action === "copy" ? 0 : 1).forceActiveFocus()
  }

  function focusChoice() {
    var choice = choices.itemAt(root.value === "copy" ? 0 : 1)
    choice.forceActiveFocus()
    viewport.contentY = 0
  }

  Keys.onEscapePressed: root.closed()

  Flickable {
    id: viewport
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: content
      width: viewport.width
      spacing: Style.spacing.md
      topPadding: Style.spacing.md
      bottomPadding: Style.spacing.md

      Text {
        width: parent.width
        text: root.strings.t("defaultAction")
        textFormat: Text.PlainText
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.heading
        color: Commons.Color.menu.text
      }
      Text {
        width: parent.width
        text: root.strings.t("defaultActionHelp")
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        color: Commons.Color.menu.text
        opacity: 0.65
      }

      Repeater {
        id: choices
        model: ["copy", "paste"]
        delegate: Button {
          id: choice
          required property string modelData
          required property int index
          objectName: "omoji-action-" + modelData
          width: content.width
          height: Math.max(Style.space(84), labels.implicitHeight + Style.spacing.md * 2)
          selected: root.value === modelData
          focusable: true
          foreground: Commons.Color.menu.text
          Accessible.role: Accessible.RadioButton
          Accessible.name: root.strings.t(modelData)
          Accessible.description: root.strings.t(modelData + "Description")
          Accessible.checked: selected
          onClicked: root.choose(modelData)
          onActiveFocusChanged: if (activeFocus) {
            viewport.contentY = Math.max(0, Math.min(y, viewport.contentHeight - viewport.height))
          }
          Keys.onUpPressed: choices.itemAt(Math.max(0, index - 1)).forceActiveFocus()
          Keys.onDownPressed: choices.itemAt(Math.min(1, index + 1)).forceActiveFocus()

          Rectangle {
            id: choiceKey
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            height: width
            radius: Math.min(Style.cornerRadius, Style.space(4))
            color: "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: choice.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.border
            Text {
              anchors.centerIn: parent
              text: choice.modelData === "copy" ? "C" : "P"
              textFormat: Text.PlainText
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              color: choice.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
            }
          }

          Column {
            id: labels
            anchors.left: choiceKey.right
            anchors.right: indicator.left
            anchors.leftMargin: Style.spacing.md
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm
            Text {
              width: parent.width
              text: root.strings.t(choice.modelData)
              textFormat: Text.PlainText
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
              color: choice.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
            }
            Text {
              width: parent.width
              text: root.strings.t(choice.modelData + "Description")
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              color: Commons.Color.menu.text
              opacity: 0.65
            }
          }
          Rectangle {
            id: indicator
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: choice.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.border
            Rectangle {
              anchors.centerIn: parent
              width: Style.space(8)
              height: width
              radius: width / 2
              visible: choice.selected
              color: Commons.Color.menu.selectedText
            }
          }
        }
      }

      Item { width: 1; height: Style.spacing.sm }
      Rectangle { width: parent.width; height: 1; color: Commons.Color.menu.border; opacity: 0.35 }
      Repeater {
        model: ["Enter", "Ctrl+Enter"]
        delegate: Item {
          required property string modelData
          required property int index
          width: content.width
          height: Style.space(26)
          Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: keyLabel.implicitWidth + Style.spacing.md * 2
            height: Style.space(24)
            radius: Math.min(Style.cornerRadius, Style.space(4))
            color: "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: Commons.Color.menu.border
            Text {
              id: keyLabel
              anchors.centerIn: parent
              text: modelData
              textFormat: Text.PlainText
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              color: Commons.Color.menu.text
            }
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.strings.t(index === 0 ? root.value : root.value === "paste" ? "copy" : "paste")
            textFormat: Text.PlainText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            color: Commons.Color.menu.text
          }
        }
      }
      Text {
        width: parent.width
        text: root.strings.t("settingsHelp")
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        color: Commons.Color.menu.text
        opacity: 0.75
      }
      Text {
        width: parent.width
        text: root.strings.t("savedAutomatically")
        textFormat: Text.PlainText
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        color: Commons.Color.menu.text
        opacity: 0.65
      }
    }
  }
}
