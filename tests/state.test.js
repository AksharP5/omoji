const { test } = require("node:test")
const assert = require("node:assert/strict")
const { mkdtempSync, readFileSync, rmSync, statSync } = require("node:fs")
const { tmpdir } = require("node:os")
const { join } = require("node:path")
const { spawnSync } = require("node:child_process")

test("state files are created private with their initial contents", () => {
  const directory = mkdtempSync(join(tmpdir(), "omoji-state-test-"))
  try {
    const file = join(directory, "omoji/config.json")
    const result = spawnSync("bash", [join(__dirname, "../scripts/prepare-state"), file, '{"version":1}'])
    assert.equal(result.status, 0, result.stderr.toString())
    assert.equal(readFileSync(file, "utf8"), '{"version":1}\n')
    assert.equal(statSync(file).mode & 0o777, 0o600)
    assert.equal(statSync(join(directory, "omoji")).mode & 0o777, 0o700)
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
})
