const { test } = require("node:test")
const assert = require("node:assert/strict")
const { readFileSync } = require("node:fs")
const { join } = require("node:path")
const { parseCatalog, parseHistory, remember, search, HISTORY_LIMIT } = require("../EmojiSearch.js")

const catalog = parseCatalog(readFileSync(join(__dirname, "../emojis.json"), "utf8"))
const rose = catalog.find(item => item.n === "rose").e
const tulip = catalog.find(item => item.n === "tulip").e

test("a choice becomes the first result for the same normalized search", () => {
  assert.notEqual(search(catalog, "flower", [])[0].e, rose)
  const choices = remember([], " Flower  ", rose, 100)
  assert.equal(search(catalog, "FLOWER", choices)[0].e, rose)
  assert.deepEqual(search(catalog, "rose", choices), search(catalog, "rose", []))
})

test("frequency wins, with recency breaking ties", () => {
  let choices = remember([], "flower", rose, 100)
  choices = remember(choices, "flower", tulip, 200)
  assert.equal(search(catalog, "flower", choices)[0].e, tulip)
  choices = remember(choices, "flower", rose, 300)
  choices = remember(choices, "flower", rose, 400)
  choices = remember(choices, "flower", tulip, 500)
  assert.equal(search(catalog, "flower", choices)[0].e, rose)
})

test("history survives serialization and empty searches show recent picks", () => {
  const choices = remember(remember([], "flower", rose, 100), "tulip", tulip, 200)
  const restored = parseHistory(JSON.stringify({ version: 1, choices }))
  assert.equal(search(catalog, "flower", restored)[0].e, rose)
  assert.equal(search(catalog, "", restored)[0].e, tulip)
})

test("multiword searches match keywords regardless of word order", () => {
  assert.equal(search(catalog, "blossom cherry", [])[0].n, "cherry blossom")
  assert.deepEqual(search(catalog, "no-such-emoji-name", []), [])
  assert.deepEqual(search(catalog, "<img src=x>", []), [])
  assert.equal(search(catalog, "", [], 3).length, 3)
})

test("learned terms still find an emoji when catalog keywords change", () => {
  const choices = remember([], "flower", rose, 100)
  const changed = catalog.map(item => item.e === rose ? { ...item, search: "rose" } : item)
  assert.equal(search(changed, "flower", choices)[0].e, rose)
})

test("old learning is bounded without mutating the previous snapshot", () => {
  const choices = Array.from({ length: HISTORY_LIMIT }, (_, i) => ({ query: `query ${i}`, emoji: rose, count: 1, lastUsed: i }))
  const next = remember(choices, "flower", tulip, HISTORY_LIMIT)
  assert.equal(next.length, HISTORY_LIMIT)
  assert.equal(next[0].emoji, tulip)
  assert.equal(next.some(row => row.query === "query 0"), false)
  assert.equal(choices[0].query, "query 0")
})

test("unreadable and future history is rejected instead of overwritten", () => {
  for (const raw of ["{", "[]", '{"version":2,"choices":[]}', '{"version":1,"choices":[{"query":"flower"}]}']) {
    assert.throws(() => parseHistory(raw))
  }
  const choice = { query: "flower", emoji: rose, count: 1, lastUsed: 100 }
  assert.throws(() => parseHistory(JSON.stringify({ version: 1, choices: [choice, choice] })))
  assert.throws(() => parseHistory(JSON.stringify({ version: 1, choices: [{ ...choice, count: -1 }] })))
  assert.throws(() => parseCatalog('[{"e":"x","n":"x","k":1}]'))
})
