#!/usr/bin/env python3
"""Exercise the real QML, subprocess, and disk boundaries in an isolated host."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location("preview", Path(__file__).with_name("preview.py"))
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


def run_case(directory, state, phase, omarchy_path):
    case_dir = Path(directory) / phase
    case_dir.mkdir()
    host = preview.prepare_host(case_dir, omarchy_path)
    host.write_text('''import QtQuick
import Quickshell
import "plugin"
ShellRoot {
  id: test
  property int ticks: 0
  property bool started: false
  property bool finished: false
  property string phase: %s
  function fail(message) { console.error("NATIVE FAIL:", message); Qt.exit(1) }
  Emojis {
    id: picker
    historyPath: %s
    copyCommand: test.phase === "start-failure" ? ["/nonexistent/omoji-copy"]
      : test.phase === "reopen" ? ["bash", "-c", "sleep 0.3"]
      : [test.phase === "copy-failure" ? "false" : "true"]
    Component.onCompleted: {
      // Exercise lifecycle calls without taking the user's keyboard focus.
      var panel = picker.data.find(function(item) { return item.objectName === "omoji-window" })
      panel.shown = false
    }
    onCopied: function(emoji) {
      if (test.phase === "copy-failure" || test.phase === "start-failure") test.fail("failed copy was recorded")
      picker.rebuild()
      if (test.phase !== "corrupt" && test.phase !== "reopen" && picker.results[0].n !== "rose") test.fail("choice did not become first")
      test.finished = true
    }
  }
  Timer {
    interval: 25
    running: true
    repeat: true
    onTriggered: {
      if (++test.ticks > 160) { test.fail("timed out waiting for catalog/history"); return }
      if (test.finished) {
        if (test.phase === "reopen" && (!picker.opened || picker.filterText !== "heart")) {
          test.fail("old copy completion dismissed the new search"); return
        }
        console.log("NATIVE PASS:", test.phase); Qt.quit(); return
      }
      if (!picker.catalog.length || (!picker.historyReady && !picker.learningError) || test.started) return
      test.started = true
      if (test.phase === "reopen") picker.open("{}")
      picker.filterText = "flower"
      picker.rebuild()
      if (test.phase === "restart" && picker.results[0].n !== "rose") { test.fail("learning lost after restart"); return }
      if (test.phase === "corrupt" && !picker.learningError) { test.fail("corrupt state accepted"); return }
      var index = picker.results.findIndex(function(item) { return item.n === "rose" })
      if (index < 0) { test.fail("rose missing from flower results"); return }
      picker.activate(index)
    }
  }
  Timer {
    interval: 300
    running: test.started && (test.phase === "copy-failure" || test.phase === "start-failure")
    onTriggered: {
      if (!picker.error) test.fail("copy failure was hidden")
      else { console.log("NATIVE PASS:", test.phase); Qt.quit() }
    }
  }
  Timer {
    interval: 50
    running: test.started && test.phase === "reopen"
    onTriggered: { picker.dismiss(); picker.open("{}"); picker.filterText = "heart" }
  }
}
''' % (json.dumps(phase), json.dumps(str(state))))
    env = {**os.environ, "QT_QPA_PLATFORM": "wayland", "OMARCHY_PATH": str(omarchy_path)}
    result = subprocess.run(["quickshell", "--no-color", "--path", str(host)], env=env, capture_output=True, text=True, timeout=12)
    output = result.stdout + result.stderr
    if result.returncode or "NATIVE PASS:" not in output or re.search(
        r"ERROR:|ReferenceError|TypeError|Binding loop|Unable to assign|Cannot assign", output
    ):
        raise RuntimeError(output)
    print(f"PASS {phase}")


def main():
    omarchy_path = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
    with tempfile.TemporaryDirectory(prefix="omoji-native-") as directory:
        state = Path(directory) / "state/history.json"
        run_case(directory, state, "first-pick", omarchy_path)
        assert json.loads(state.read_text())["choices"][0]["count"] == 1
        assert state.stat().st_mode & 0o777 == 0o600
        assert state.parent.stat().st_mode & 0o777 == 0o700
        run_case(directory, state, "restart", omarchy_path)
        assert json.loads(state.read_text())["choices"][0]["count"] == 2
        failed_state = Path(directory) / "failed/history.json"
        run_case(directory, failed_state, "copy-failure", omarchy_path)
        assert json.loads(failed_state.read_text())["choices"] == []
        start_failed_state = Path(directory) / "start-failed/history.json"
        run_case(directory, start_failed_state, "start-failure", omarchy_path)
        assert json.loads(start_failed_state.read_text())["choices"] == []
        reopen_state = Path(directory) / "reopen-state/history.json"
        run_case(directory, reopen_state, "reopen", omarchy_path)
        assert json.loads(reopen_state.read_text())["choices"][0]["query"] == "flower"
        corrupt = Path(directory) / "corrupt-state/history.json"
        corrupt.parent.mkdir()
        corrupt.write_text("{invalid")
        run_case(directory, corrupt, "corrupt", omarchy_path)
        assert corrupt.read_text() == "{invalid"
        print("Native persistence, restart, permissions, copy failures, reopen lifecycle, and corruption checks passed")


if __name__ == "__main__":
    main()
