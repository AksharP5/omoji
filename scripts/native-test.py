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
    preferences = state.with_name("config.json")
    if phase in ["first-pick", "restart", "copy-failure", "start-failure", "reopen", "corrupt"]:
        preferences.parent.mkdir(parents=True, exist_ok=True)
        preferences.write_text(json.dumps({"version": 1, "defaultAction": "copy"}))
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
    preferencesPath: %s
    pasteCommand: test.phase === "paste-failure" ? ["false"]
      : test.phase === "paste-start-failure" ? ["/nonexistent/omoji-paste"]
      : ["bash", "-c", 'printf paste > "$1"', "test", %s]
    copyCommand: test.phase === "start-failure" ? ["/nonexistent/omoji-copy"]
      : test.phase === "reopen" ? ["bash", "-c", "sleep 0.3"]
      : [test.phase === "copy-failure" ? "false" : "true"]
    Component.onCompleted: {
      // Exercise lifecycle calls without taking the user's keyboard focus.
      var panel = picker.data.find(function(item) { return item.objectName === "omoji-window" })
      panel.shown = false
    }
    onPasted: function(emoji) {
      if (test.phase !== "paste") { test.fail("unexpected paste"); return }
      if (picker.opened) { test.fail("paste ran before dismissal"); return }
      picker.rebuild()
      if (picker.results[0].n !== "rose") { test.fail("paste did not teach preference"); return }
      test.finished = true
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
      if ((!picker.preferencesReady && !picker.preferencesError) || !picker.catalog.length || (!picker.historyReady && !picker.learningError) || test.started) return
      test.started = true
      if (test.phase === "choose-default") {
        if (picker.defaultAction !== "paste") { test.fail("fresh default was not paste"); return }
        picker.handleKey({ key: Qt.Key_Comma, modifiers: Qt.ControlModifier })
        if (!picker.settingsOpen) { test.fail("settings shortcut failed"); return }
        picker.data.find(function(item) { return item.objectName === "omoji-preferences" }).choose("copy")
        if (picker.defaultAction !== "copy") { test.fail("default did not change"); return }
        picker.handleKey({ key: Qt.Key_Escape, modifiers: Qt.NoModifier })
        if (picker.settingsOpen) { test.fail("settings did not close"); return }
        test.finished = true
        return
      }
      if (test.phase === "preference-restart" && picker.defaultAction !== "copy") { test.fail("default lost on restart"); return }
      if (test.phase === "invalid-preferences" && (!picker.preferencesError || picker.defaultAction !== "copy")) { test.fail("invalid preferences did not safely fall back"); return }
      if (["reopen", "paste", "ctrl-copy", "paste-failure", "paste-start-failure", "paste-reopen"].indexOf(test.phase) !== -1) picker.open("{}")
      picker.filterText = "flower"
      picker.rebuild()
      if (test.phase === "restart" && picker.results[0].n !== "rose") { test.fail("learning lost after restart"); return }
      if (test.phase === "corrupt" && !picker.learningError) { test.fail("corrupt state accepted"); return }
      var index = picker.results.findIndex(function(item) { return item.n === "rose" })
      if (index < 0) { test.fail("rose missing from flower results"); return }
      if (test.phase === "ctrl-copy") {
        picker.moveSelection(index)
        picker.handleKey({ key: Qt.Key_Return, modifiers: Qt.ControlModifier })
        if (picker.defaultAction !== "paste") test.fail("Ctrl+Enter changed default")
      } else picker.activate(index)
    }
  }
  Timer {
    interval: 300
    running: test.started && (["copy-failure", "start-failure", "paste-failure", "paste-start-failure"].indexOf(test.phase) !== -1)
    onTriggered: {
      if (!picker.error) test.fail("action failure was hidden")
      else if (test.phase.indexOf("paste-") === 0 && !picker.opened) test.fail("paste failure did not restore picker")
      else { console.log("NATIVE PASS:", test.phase); Qt.quit() }
    }
  }
  Timer {
    interval: 450
    running: test.started && test.phase === "paste-reopen"
    onTriggered: { test.finished = true }
  }
  Timer {
    interval: 50
    running: test.started && (test.phase === "reopen" || test.phase === "paste-reopen")
    onTriggered: { picker.dismiss(); picker.open("{}"); picker.filterText = "heart" }
  }
}
''' % (json.dumps(phase), json.dumps(str(state)), json.dumps(str(preferences)), json.dumps(str(case_dir / "paste-request"))))
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
        for phase in ["paste", "ctrl-copy", "paste-failure", "paste-start-failure", "paste-reopen"]:
            action_state = Path(directory) / phase / "history.json"
            run_case(directory, action_state, phase, omarchy_path)
            choices = json.loads(action_state.read_text())["choices"]
            assert bool(choices) == (phase in ["paste", "ctrl-copy"]), phase
            assert (Path(directory) / phase / "paste-request").exists() == (phase == "paste"), phase
        preference_state = Path(directory) / "preference-state/history.json"
        run_case(directory, preference_state, "choose-default", omarchy_path)
        assert json.loads(preference_state.with_name("config.json").read_text())["defaultAction"] == "copy"
        run_case(directory, preference_state, "preference-restart", omarchy_path)
        invalid_state = Path(directory) / "invalid-preferences-state/history.json"
        invalid_state.parent.mkdir()
        invalid_config = invalid_state.with_name("config.json")
        invalid_config.write_text('{"version":1,"defaultAction":"execute"}')
        run_case(directory, invalid_state, "invalid-preferences", omarchy_path)
        assert json.loads(invalid_config.read_text())["defaultAction"] == "execute"
        print("Native learning, action defaults, copy/paste, failures, cancellation, persistence and corruption checks passed")


if __name__ == "__main__":
    main()
