var HISTORY_LIMIT = 2000
var QUERY_LIMIT = 160

function normalizeQuery(query) {
  return query.trim().toLowerCase().replace(/\s+/g, " ")
}

function parseCatalog(raw) {
  var data = JSON.parse(raw)
  if (!Array.isArray(data) || data.length > 10000) throw new Error("Invalid emoji catalog")
  var seen = Object.create(null)
  return data.map(function(item) {
    if (!item || typeof item.e !== "string" || !item.e || item.e.length > 32
        || typeof item.n !== "string" || !item.n || item.n.length > 200
        || typeof item.k !== "string" || item.k.length > 2000 || seen[item.e])
      throw new Error("Invalid or duplicate emoji")
    seen[item.e] = true
    return { e: item.e, n: item.n, search: normalizeQuery(item.n + " " + item.k.replace(/_/g, " ")) }
  })
}

function parseHistory(raw) {
  if (raw.length > 1000000) throw new Error("History is too large")
  var data = JSON.parse(raw)
  if (!data || data.version !== 1 || !Array.isArray(data.choices) || data.choices.length > HISTORY_LIMIT)
    throw new Error("Unsupported history format")
  var seen = Object.create(null)
  return data.choices.map(function(row) {
    if (!row || typeof row.query !== "string" || row.query.length > QUERY_LIMIT
        || normalizeQuery(row.query) !== row.query
        || typeof row.emoji !== "string" || !row.emoji || row.emoji.length > 32
        || !Number.isSafeInteger(row.count) || row.count < 1
        || !Number.isSafeInteger(row.lastUsed) || row.lastUsed < 0)
      throw new Error("Invalid history entry")
    var key = row.query + "\u0000" + row.emoji
    if (seen[key]) throw new Error("Duplicate history entry")
    seen[key] = true
    return { query: row.query, emoji: row.emoji, count: row.count, lastUsed: row.lastUsed }
  })
}

function remember(choices, query, emoji, now) {
  var needle = normalizeQuery(query)
  var previous = choices.find(function(row) { return row.query === needle && row.emoji === emoji })
  var next = choices.filter(function(row) { return row !== previous })
  next.push({ query: needle, emoji: emoji, count: previous ? Math.min(Number.MAX_SAFE_INTEGER, previous.count + 1) : 1, lastUsed: now })
  next.sort(function(a, b) { return b.lastUsed - a.lastUsed })
  return next.slice(0, HISTORY_LIMIT)
}

function search(catalog, query, choices, limit) {
  var needle = normalizeQuery(query)
  var words = needle.split(" ")
  var learned = Object.create(null)
  choices.forEach(function(row) {
    if (needle && row.query !== needle) return
    var usage = learned[row.emoji] || { count: 0, lastUsed: 0 }
    usage.count += row.count
    usage.lastUsed = Math.max(usage.lastUsed, row.lastUsed)
    learned[row.emoji] = usage
  })
  var matches = []
  catalog.forEach(function(item, index) {
    var usage = learned[item.e]
    if (needle && !usage && !words.every(function(word) { return item.search.indexOf(word) !== -1 })) return
    var name = normalizeQuery(item.n)
    matches.push({ e: item.e, n: item.n, count: usage ? usage.count : 0, lastUsed: usage ? usage.lastUsed : 0,
      relevance: name === needle ? 0 : name.indexOf(needle) === 0 ? 1 : 2, order: index })
  })
  matches.sort(function(a, b) {
    if (!needle) return b.lastUsed - a.lastUsed || b.count - a.count || a.order - b.order
    return b.count - a.count || b.lastUsed - a.lastUsed || a.relevance - b.relevance || a.order - b.order
  })
  return matches.slice(0, limit === undefined ? 1000 : limit)
}

if (typeof module !== "undefined") module.exports = { HISTORY_LIMIT: HISTORY_LIMIT, normalizeQuery: normalizeQuery,
  parseCatalog: parseCatalog, parseHistory: parseHistory, remember: remember, search: search }
