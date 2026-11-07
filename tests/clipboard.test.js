const { test } = require("node:test")
const assert = require("node:assert/strict")
const { mkdtempSync, writeFileSync, rmSync } = require("node:fs")
const { tmpdir } = require("node:os")
const { join } = require("node:path")
const { spawnSync } = require("node:child_process")

function readClipboard(source, args = []) {
  const directory = mkdtempSync(join(tmpdir(), "omoji-clipboard-test-"))
  try {
    writeFileSync(join(directory, "wl-paste"), "#!/usr/bin/env bash\n" + source, { mode: 0o700 })
    return spawnSync("bash", [join(__dirname, "../scripts/read-clipboard"), ...args], {
      env: { ...process.env, PATH: directory + ":" + process.env.PATH },
      timeout: 3000
    })
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
}

test("search clipboard reads preserve text and forward primary-selection requests", () => {
  const result = readClipboard('[[ " $* " == *" --primary "* ]] || exit 1\nprintf %s "café search"', ["--primary"])
  assert.ifError(result.error)
  assert.equal(result.status, 0)
  assert.equal(result.stdout.toString(), "café search")
})

test("oversized clipboard offers cannot write more than 641 bytes into the shell", () => {
  const result = readClipboard("printf '%5000s' '' | tr ' ' x")
  assert.ifError(result.error)
  assert.equal(result.stdout.length, 641)
})

test("a clipboard owner that never produces text times out", () => {
  const result = readClipboard("exec sleep 5")
  assert.ifError(result.error)
  assert.equal(result.status, 124)
  assert.equal(result.stdout.length, 0)
})
