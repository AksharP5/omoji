import QtQuick
import Quickshell
import Quickshell.Io
import "EmojiSearch.js" as EmojiSearch

Item {
  id: store

  property string path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omoji/history.json"
  property var choices: []
  property bool ready: false
  property string error: ""

  function ingest(raw) {
    try {
      store.choices = EmojiSearch.parseHistory(raw)
      store.ready = true
    } catch (failure) {
      store.error = String(failure)
      console.warn("omoji: keeping unreadable history untouched:", store.path, store.error)
    }
  }

  function remember(query, emoji) {
    if (!store.ready || store.error) return
    store.choices = EmojiSearch.remember(store.choices, query, emoji, Date.now())
    historyFile.setText(JSON.stringify({ version: 1, choices: store.choices }) + "\n")
  }

  Process {
    running: true
    command: ["bash", decodeURIComponent(String(Qt.resolvedUrl("scripts/prepare-state")).replace(/^file:\/\//, "")), store.path]
    onExited: function(code) {
      if (code === 0) historyFile.path = store.path
      else {
        store.error = "Cannot prepare history file"
        console.warn("omoji:", store.error, store.path)
      }
    }
  }

  FileView {
    id: historyFile
    blockLoading: true
    blockWrites: true
    atomicWrites: true
    printErrors: false
    onLoaded: store.ingest(text())
    onLoadFailed: function(error) {
      store.error = "Cannot read history: " + FileViewError.toString(error)
      console.warn("omoji:", store.error, store.path)
    }
    onSaveFailed: function(error) {
      store.error = "Cannot save history: " + FileViewError.toString(error)
      console.warn("omoji:", store.error, store.path)
    }
  }
}
