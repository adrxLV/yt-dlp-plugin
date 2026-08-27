// Model.js - Helper functions and state management for Media Downloader plugin

.pragma library

function defaultIcon() {
  return "󰗃"
}

function emptyState() {
  return {
    results: [],
    history: [],
    busy: false,
    statusText: "",
    errorText: ""
  }
}

function isUrl(input) {
  if (!input || typeof input !== "string") return false
  var s = input.trim()
  if (s.indexOf("http://") === 0 || s.indexOf("https://") === 0) return true
  
  var patterns = [
    "youtube.com/",
    "youtu.be/",
    "music.youtube.com/",
    "soundcloud.com/",
    "vimeo.com/",
    "twitch.tv/",
    "tiktok.com/",
    "twitter.com/",
    "x.com/",
    "instagram.com/",
    "bilibili.com/"
  ]
  for (var i = 0; i < patterns.length; i++) {
    if (s.indexOf(patterns[i]) !== -1) return true
  }
  return false
}

function formatDuration(seconds) {
  if (!seconds || seconds <= 0 || isNaN(seconds)) return "--:--"
  var s = Math.floor(seconds)
  var m = Math.floor(s / 60)
  var h = Math.floor(m / 60)
  s = s % 60
  m = m % 60
  if (h > 0) {
    return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
  }
  return m + ":" + (s < 10 ? "0" : "") + s
}

function formatBytes(bytes) {
  if (!bytes || bytes <= 0 || isNaN(bytes)) return "0 B"
  if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
  if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB"
  if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KB"
  return bytes + " B"
}

function parseJsonSafe(text, fallback) {
  if (!text || typeof text !== "string") return fallback
  try {
    return JSON.parse(text)
  } catch (e) {
    return fallback
  }
}

function formatTimeAgo(timestamp) {
  if (!timestamp) return ""
  var now = Math.floor(Date.now() / 1000)
  var diff = Math.max(0, now - timestamp)
  if (diff < 60) return "Just now"
  if (diff < 3600) return Math.floor(diff / 60) + "m ago"
  if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
  var days = Math.floor(diff / 86400)
  if (days === 1) return "Yesterday"
  return days + "d ago"
}

function parseProgressLine(line) {
  if (!line || typeof line !== "string") return null
  var prefix = "PROGRESS:"
  var idx = line.indexOf(prefix)
  if (idx === -1) return null
  var jsonStr = line.substring(idx + prefix.length).trim()
  try {
    return JSON.parse(jsonStr)
  } catch (e) {
    return null
  }
}

function parseCompleteLine(line) {
  if (!line || typeof line !== "string") return null
  var prefix = "COMPLETE:"
  var idx = line.indexOf(prefix)
  if (idx === -1) return null
  var jsonStr = line.substring(idx + prefix.length).trim()
  try {
    return JSON.parse(jsonStr)
  } catch (e) {
    return null
  }
}

function parseErrorLine(line) {
  if (!line || typeof line !== "string") return null
  var prefix = "ERROR:"
  var idx = line.indexOf(prefix)
  if (idx === -1) return null
  var jsonStr = line.substring(idx + prefix.length).trim()
  try {
    return JSON.parse(jsonStr)
  } catch (e) {
    return { message: jsonStr }
  }
}
