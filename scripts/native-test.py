#!/usr/bin/env python3
"""Exercise the real QML, subprocess, and disk boundaries in an isolated host."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location("preview", Path(__file__).with_name("preview.py"))
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


def run_case(directory, state, phase, omarchy_path):
    case_dir = Path(directory) / phase
    case_dir.mkdir()
    host = preview.prepare_host(case_dir, omarchy_path)
    if phase == "catalog-failure":
        broken_plugin = case_dir / "broken-plugin"
        shutil.copytree(preview.ROOT, broken_plugin, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        (broken_plugin / "emojis.json").write_text("{invalid")
        (case_dir / "plugin").unlink()
        (case_dir / "plugin").symlink_to(broken_plugin, target_is_directory=True)
    preferences = state.with_name("config.json")
    if phase in ["first-pick", "restart", "copy-failure", "start-failure", "reopen", "corrupt", "ctrl-paste"]:
        preferences.parent.mkdir(parents=True, exist_ok=True)
        preferences.write_text(json.dumps({"version": 1, "defaultAction": "copy"}))
    host.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "plugin"
ShellRoot {
  id: test
  property int ticks: 0
  property bool started: false
  property bool finished: false
  property string phase: %s
  function fail(message) { console.error("NATIVE FAIL:", message); Qt.exit(1) }
  function find(item, name) {
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) { var result = find(children[i], name); if (result) return result }
    return null
  }
  Process {
    id: denyWrites
    command: ["chmod", "500", %s]
    onExited: function(code) {
      if (code !== 0) { test.fail("could not simulate read-only preferences"); return }
      var panel = picker.data.find(function(item) { return item.objectName === "omoji-window" })
      var menu = test.find(panel.contentItem, "omoji-action-settings")
      menu.choose("copy")
      if (!picker.preferencesError || !picker.settingsOpen || !menu.enabled || menu.choicesEnabled) {
        test.fail("failed save disabled menu dismissal or hid the error"); return
      }
      picker.handleKey({ key: Qt.Key_Escape, modifiers: Qt.NoModifier })
      if (picker.settingsOpen || !picker.opened || picker.filterText !== "flower") {
        test.fail("failed save did not retain the search and Escape route"); return
      }
      test.finished = true
    }
  }
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
      if (["paste", "ctrl-paste"].indexOf(test.phase) === -1) { test.fail("unexpected paste"); return }
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
      if (test.phase === "catalog-failure") {
        if (test.ticks < 8) return
        picker.open("{}")
        picker.filterText = "flower"
        var panel = picker.data.find(function(item) { return item.objectName === "omoji-window" })
        var message = test.find(panel.contentItem, "emoji-empty")
        if (!message.visible || message.text !== "Could not load emoji") {
          test.fail("catalog failure disappeared when opening or searching"); return
        }
        picker.dismiss()
        picker.open("{}")
        if (message.text !== "Could not load emoji") { test.fail("catalog failure disappeared when reopening"); return }
        test.finished = true
        return
      }
      if ((!picker.preferencesReady && !picker.preferencesError) || !picker.catalog.length || (!picker.historyReady && !picker.learningError) || test.started) return
      test.started = true
      if (test.phase === "page-navigation") {
        picker.open("{}")
        picker.filterText = "rocket"
        picker.moveSelection(-picker.results.length - 1)
        if (picker.selectedIndex !== picker.results.length - 1) {
          test.fail("moving back more than the result count lost the selection"); return
        }
        picker.moveSelection(picker.results.length + 1)
        if (picker.selectedIndex !== 0) { test.fail("moving forward did not wrap to the first result"); return }
        test.finished = true
        return
      }
      if (test.phase === "search-editing") {
        picker.open("{}")
        var panel = picker.data.find(function(item) { return item.objectName === "omoji-window" })
        var input = test.find(panel.contentItem, "emoji-search")
        input.text = "flower" + " ".repeat(155)
        if (picker.results.length) { test.fail("over-limit queries could select a result"); return }
        var original = "a".repeat(159) + "z"
        input.text = original
        input.cursorPosition = 0
        input.insert(0, "X")
        if (input.text !== "X" + original || picker.results.length) {
          test.fail("over-limit editing removed existing text or allowed a result"); return
        }
        input.undo()
        if (input.text !== original) { test.fail("query limit handling damaged undo"); return }
        input.cursorPosition = input.length
        Qt.callLater(function() {
          var viewport = test.find(panel.contentItem, "emoji-search-viewport")
          var cursor = input.cursorRectangle
          if (cursor.x < viewport.contentX - 1 || cursor.x + cursor.width > viewport.contentX + viewport.width + 1) {
            test.fail("long query cursor was clipped"); return
          }
          test.finished = true
        })
        return
      }
      if (test.phase === "preferences-save-failure") {
        picker.open("{}")
        picker.filterText = "flower"
        picker.toggleSettings()
        denyWrites.running = true
        return
      }
      if (test.phase === "choose-default") {
        if (picker.defaultAction !== "paste") { test.fail("fresh default was not paste"); return }
        picker.open("{}")
        picker.filterText = "flower"
        picker.moveSelection(2)
        var selected = picker.selectedIndex
        picker.handleKey({ key: Qt.Key_Question, modifiers: Qt.ShiftModifier })
        if (!picker.settingsOpen) { test.fail("settings shortcut failed"); return }
        var panel = picker.data.find(function(item) { return item.objectName === "omoji-window" })
        test.find(panel.contentItem, "omoji-action-settings").choose("copy")
        if (picker.defaultAction !== "copy") { test.fail("default did not change"); return }
        if (picker.settingsOpen || !picker.opened || picker.filterText !== "flower" || picker.selectedIndex !== selected) {
          test.fail("applying preference did not return to the preserved search"); return
        }
        test.finished = true
        return
      }
      if (test.phase === "preference-restart" && picker.defaultAction !== "copy") { test.fail("default lost on restart"); return }
      if (test.phase === "invalid-preferences" && (!picker.preferencesError || picker.defaultAction !== "copy")) { test.fail("invalid preferences did not safely fall back"); return }
      if (["reopen", "paste", "ctrl-copy", "ctrl-paste", "paste-failure", "settings-no-activation", "paste-start-failure", "paste-reopen"].indexOf(test.phase) !== -1) picker.open("{}")
      picker.filterText = "flower"
      picker.rebuild()
      if (test.phase === "restart" && picker.results[0].n !== "rose") { test.fail("learning lost after restart"); return }
      if (test.phase === "corrupt" && !picker.learningError) { test.fail("corrupt state accepted"); return }
      var index = picker.results.findIndex(function(item) { return item.n === "rose" })
      if (index < 0) { test.fail("rose missing from flower results"); return }
      if ((test.phase === "ctrl-copy" || test.phase === "ctrl-paste")) {
        picker.moveSelection(index)
        picker.handleKey({ key: Qt.Key_Return, modifiers: Qt.ControlModifier })
        if (picker.defaultAction !== (test.phase === "ctrl-copy" ? "paste" : "copy")) test.fail("Ctrl+Enter changed default")
      } else {
        if (test.phase === "settings-no-activation") {
          picker.toggleSettings()
          picker.handleKey({ key: Qt.Key_Return, modifiers: Qt.ControlModifier })
        } else picker.activate(index)
      }
    }
  }
  Timer {
    interval: 300
    running: test.started && (["copy-failure", "start-failure", "paste-failure", "paste-start-failure"].indexOf(test.phase) !== -1)
    onTriggered: {
      if (!picker.error) test.fail("action failure was hidden")
      else if (test.phase.indexOf("paste-") === 0 && (!picker.opened || picker.settingsOpen)) test.fail("paste failure did not restore search")
      else { console.log("NATIVE PASS:", test.phase); Qt.quit() }
    }
  }
  Timer {
    interval: 300
    running: test.started && test.phase === "settings-no-activation"
    onTriggered: {
      if (!picker.opened || !picker.settingsOpen || picker.error) test.fail("settings action leaked to picker")
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
''' % (json.dumps(phase), json.dumps(str(preferences.parent)), json.dumps(str(state)), json.dumps(str(preferences)), json.dumps(str(case_dir / "paste-request"))))
    env = {**os.environ, "QT_QPA_PLATFORM": "wayland", "OMARCHY_PATH": str(omarchy_path)}
    try:
        result = subprocess.run(["quickshell", "--no-color", "--path", str(host)], env=env, capture_output=True, text=True, timeout=12)
    finally:
        if phase == "preferences-save-failure":
            preferences.parent.chmod(0o700)
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
        for phase in ["paste", "ctrl-copy", "ctrl-paste", "paste-failure", "settings-no-activation", "paste-start-failure", "paste-reopen"]:
            action_state = Path(directory) / phase / "history.json"
            run_case(directory, action_state, phase, omarchy_path)
            choices = json.loads(action_state.read_text())["choices"]
            assert bool(choices) == (phase in ["paste", "ctrl-copy", "ctrl-paste"]), phase
            assert (Path(directory) / phase / "paste-request").exists() == (phase in ["paste", "ctrl-paste"]), phase
        preference_state = Path(directory) / "preference-state/history.json"
        run_case(directory, preference_state, "choose-default", omarchy_path)
        assert json.loads(preference_state.with_name("config.json").read_text())["defaultAction"] == "copy"
        run_case(directory, preference_state, "preference-restart", omarchy_path)
        failed_preferences_state = Path(directory) / "preferences-save-failure-state/history.json"
        run_case(directory, failed_preferences_state, "preferences-save-failure", omarchy_path)
        assert json.loads(failed_preferences_state.with_name("config.json").read_text())["defaultAction"] == "paste"
        invalid_state = Path(directory) / "invalid-preferences-state/history.json"
        invalid_state.parent.mkdir()
        invalid_config = invalid_state.with_name("config.json")
        invalid_config.write_text('{"version":1,"defaultAction":"execute"}')
        run_case(directory, invalid_state, "invalid-preferences", omarchy_path)
        assert json.loads(invalid_config.read_text())["defaultAction"] == "execute"
        run_case(directory, Path(directory) / "catalog-failure-state/history.json", "catalog-failure", omarchy_path)
        run_case(directory, Path(directory) / "search-editing-state/history.json", "search-editing", omarchy_path)
        run_case(directory, Path(directory) / "page-navigation-state/history.json", "page-navigation", omarchy_path)
        print("Native learning, action defaults, copy/paste, failures, cancellation, persistence and corruption checks passed")


if __name__ == "__main__":
    main()
