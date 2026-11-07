#!/usr/bin/env python3
"""Run omoji without installing it or changing the user's shortcut."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def prepare_host(directory, omarchy_path):
    directory = Path(directory)
    for name in ["Commons", "Ui"]:
        (directory / name).symlink_to(Path(omarchy_path) / "shell" / name, target_is_directory=True)
    (directory / "plugin").symlink_to(ROOT, target_is_directory=True)
    return directory / "shell.qml"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--omarchy-path", default=os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
    parser.add_argument("--capture", type=Path, help="Save the picker card as a PNG and exit")
    parser.add_argument("--query", default="")
    parser.add_argument("--settings", action="store_true", help="Show the action settings view")
    parser.add_argument("--default-action", choices=["copy", "paste"], default="paste")
    parser.add_argument("--learn", help="Seed a sample choice by its English emoji name")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="omoji-preview-") as directory:
        state = Path(directory) / "state/history.json"
        if args.learn:
            catalog = json.loads((ROOT / "emojis.json").read_text())
            choice = next((item for item in catalog if item["n"] == args.learn), None)
            if not choice:
                parser.error("Unknown emoji name: " + args.learn)
            state.parent.mkdir()
            state.write_text(json.dumps({"version": 1, "choices": [
                {"query": " ".join(args.query.lower().split()), "emoji": choice["e"], "count": 1, "lastUsed": 1}
            ]}))
        preferences = Path(directory) / "config.json"
        preferences.write_text(json.dumps({"version": 1, "defaultAction": args.default_action}))
        host = prepare_host(directory, args.omarchy_path)
        host.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "plugin"
ShellRoot {
  property string capturePath: %s
  property string query: %s
  function findItem(item, name) {
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = findItem(children[i], name)
      if (found) return found
    }
    return null
  }
  Emojis {
    id: picker
    historyPath: %s
    preferencesPath: %s
    onOpenedChanged: if (!opened) Qt.callLater(function() { Qt.quit() })
  }
  Timer { interval: 300; running: true; onTriggered: picker.open("{}") }
  Timer {
    interval: 1000
    running: true
    onTriggered: {
      var panel = picker.data.find(function(item) { return item.objectName === "omoji-window" })
      var input = findItem(panel.contentItem, "emoji-search")
      input.text = query
      if (%s) picker.toggleSettings()
      if (!capturePath) return
      captureTimer.start()
    }
  }
  Timer {
    id: captureTimer
    interval: 200
    onTriggered: {
      var panel = picker.data.find(function(item) { return item.objectName === "omoji-window" })
      var card = findItem(panel.contentItem, "omoji-card")
      card.grabToImage(function(result) {
        if (!result.saveToFile(capturePath)) console.error("Could not save picker image")
        Qt.quit()
      })
    }
  }
}
''' % (json.dumps(str(args.capture.resolve()) if args.capture else ""), json.dumps(args.query),
       json.dumps(str(state)), json.dumps(str(preferences)), "true" if args.settings else "false"))
        subprocess.run(["quickshell", "--no-color", "--path", str(host)], check=True)


if __name__ == "__main__":
    main()
