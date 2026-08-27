# Media Downloader (`adrxlv.yt-dlp-plugin`)

[![Omarchy Plugin](https://img.shields.io/badge/Omarchy-Quattro%20Plugin-blue)](https://omarchyplugins.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![yt-dlp](https://img.shields.io/badge/backend-yt--dlp-red)](https://github.com/yt-dlp/yt-dlp)

A native **Omarchy** shell plugin (`bar-widget` + `panel`) to search, stream info, and download audio & video from YouTube and all platforms supported by `yt-dlp`.

---

## ✨ Features

- 🔍 **YouTube Search & URL Detection**: Search YouTube queries (showing up to 15 scrollable results) or paste direct URLs from YouTube, SoundCloud, Vimeo, and more.
- 🖼️ **Rich Previews**: Real-time thumbnail previews, duration badges, and channel metadata.
- 🎛️ **Format & Codec Selector**:
  - **Video**: MP4 container with selectable resolutions (`Best Available`, `1080p`, `720p`, `480p`).
  - **Audio**: Direct audio extraction with codecs (`MP3`, `M4A / AAC`, `FLAC`, `Opus`).
- ⚡ **Live Download Progress**: Real-time progress bar, download speed (`MB/s`), ETA, downloaded/total file size, and post-processing status.
- 📜 **Scrollable History**: Local download log with quick "Open File" and "Show in Folder" actions.
- 🔔 **Native Notifications**: Desktop completion alerts.
- ⌨️ **Keyboard Navigation**: Interactive Quickshell list with mouse wheel and trackpad scroll.

---

## 📋 Requirements & Dependencies

This plugin requires `yt-dlp`, `ffmpeg`, and `python3`:

```bash
# Arch Linux / Omarchy
sudo pacman -S yt-dlp ffmpeg python
```

---

## 📦 Installation

To install this plugin via the official Omarchy CLI:

```bash
omarchy plugin add https://github.com/adrxlv/yt-dlp-plugin --enable
```

Or for local development:

```bash
# 1. Clone or copy to plugins folder
cp -r adrxlv.yt-dlp-plugin ~/.config/omarchy/plugins/

# 2. Validate manifest
omarchy plugin validate ~/.config/omarchy/plugins/adrxlv.yt-dlp-plugin

# 3. Enable in bar (right section)
omarchy plugin enable adrxlv.yt-dlp-plugin right
```

---

## 🗑️ Removal

To safely remove the plugin from your Omarchy installation:

```bash
omarchy plugin remove adrxlv.yt-dlp-plugin
```

---

## ⚙️ Configuration

You can customize the widget icon and default save locations via your Omarchy configuration or directly in `~/.config/omarchy/shell.json`:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icon` | `string` | `"󰗃"` | Nerd Font glyph shown on the top bar |
| `defaultAudioDir` | `string` | `"~/Music"` | Destination directory for audio downloads |
| `defaultVideoDir` | `string` | `"~/Downloads"` | Destination directory for video downloads |

---

## 🏛️ Architecture

- **`manifest.json`**: Plugin metadata conforming to Omarchy Schema Version 1.
- **`BarWidget.qml`**: Bar widget button with click handlers, tooltips, and IPC listener.
- **`Panel.qml`**: Quickshell layer-shell popup panel with state transitions, scrollable list, and animations.
- **`downloaderctl.py`**: Python backend handling queries, URL extraction, progress streaming, and history.
- **`Model.js`**: Pure JavaScript helper library for duration calculations, byte sizes, and URL detection.

---

## 📄 License

Distributed under the [MIT License](LICENSE).
