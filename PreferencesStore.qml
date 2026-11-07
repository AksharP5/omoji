import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: store

  property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omoji/config.json"
  property string defaultAction: "paste"
  property bool ready: false
  property string error: ""

  function choose(action) {
    if (!store.ready || store.error || (action !== "copy" && action !== "paste")) return false
    if (action === store.defaultAction) return true
    preferencesFile.setText(JSON.stringify({ version: 1, defaultAction: action }) + "\n")
    if (store.error) return false
    store.defaultAction = action
    return true
  }

  Process {
    running: true
    command: ["bash", decodeURIComponent(String(Qt.resolvedUrl("scripts/prepare-state")).replace(/^file:\/\//, "")),
      store.path, JSON.stringify({ version: 1, defaultAction: "paste" })]
    onExited: function(code) {
      if (code === 0) preferencesFile.path = store.path
      else store.error = "Cannot prepare preferences"
    }
  }

  FileView {
    id: preferencesFile
    blockLoading: true
    blockWrites: true
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var config = JSON.parse(text())
        if (!config || config.version !== 1 || (config.defaultAction !== "copy" && config.defaultAction !== "paste"))
          throw new Error("Invalid preferences")
        store.defaultAction = config.defaultAction
        store.error = ""
        store.ready = true
      } catch (failure) {
        store.defaultAction = "copy"
        store.error = String(failure)
      }
    }
    onLoadFailed: store.error = "Cannot read preferences"
    onSaveFailed: store.error = "Cannot save preferences"
  }
}
