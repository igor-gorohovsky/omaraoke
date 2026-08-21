.pragma library

// LRC → LyricsTimeline: sorted [{t: ms, text}] entries, line-level only.
// P3's word timings extend these entries; nothing here precludes that seam.

function parseLrc(text) {
  var lines = String(text).split(/\r?\n/)
  var out = []
  var offset = 0
  var tagRe = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g

  for (var li = 0; li < lines.length; li++) {
    var line = lines[li]

    var meta = line.match(/^\[offset:\s*([+-]?\d+)\s*\]\s*$/i)
    if (meta) {
      offset = parseInt(meta[1], 10) || 0
      continue
    }

    // leading, contiguous timestamp tags (a line may carry several)
    var times = []
    var m
    var lastEnd = 0
    tagRe.lastIndex = 0
    while ((m = tagRe.exec(line)) !== null) {
      if (m.index !== lastEnd)
        break
      var frac = m[3] || ""
      var ms = frac.length === 1 ? Number(frac) * 100
             : frac.length === 2 ? Number(frac) * 10
             : frac.length === 3 ? Number(frac)
             : 0
      times.push(Number(m[1]) * 60000 + Number(m[2]) * 1000 + ms)
      lastEnd = tagRe.lastIndex
    }
    if (times.length === 0)
      continue

    var txt = line.slice(lastEnd).trim()
    for (var t = 0; t < times.length; t++)
      out.push({ t: times[t] - offset, text: txt })
  }

  out.sort(function (a, b) { return a.t - b.t })
  return out
}

// Plain text fallback for Static Mode when only syncedLyrics exist.
function stripLrc(text) {
  var parsed = parseLrc(text)
  var out = []
  for (var i = 0; i < parsed.length; i++)
    out.push(parsed[i].text)
  return out.join("\n").replace(/\n{3,}/g, "\n\n").trim()
}
