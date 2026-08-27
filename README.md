# Media Downloader (`io.github.adriano.media-downloader`)

Native Omarchy bar widget and interactive panel to search and download audio/video from YouTube and all platforms supported by `yt-dlp`.

---

## Features

- 🔍 **Universal Search & URL Detection**: Search YouTube directly by typing queries or paste any video/audio URL (YouTube, SoundCloud, Vimeo, etc.).
- 🖼️ **Rich Metadata Previews**: Instant thumbnail previews, video duration badges, and channel info.
- 🎛️ **Format & Quality Control**:
  - **Video**: MP4 format with selectable resolutions (`Best`, `1080p`, `720p`, `480p`).
  - **Audio**: Music extraction with codecs (`MP3`, `M4A/AAC`, `FLAC`, `Opus`).
- ⚡ **Live Download Progress**: Real-time progress bar with download speed (`MB/s`), ETA, downloaded/total size, and stream merging feedback.
- 📁 **Configurable Directories**: Downloads saved to `~/Downloads` (video) and `~/Music` (audio) with quick one-click "Open File" and "Show in Folder" buttons.
- 📜 **Download History**: Stores your latest downloads locally with quick launch actions.
- 🔔 **Desktop Notifications**: Native desktop notifications on completion.
- ⌨️ **IPC & Keyboard Shortcuts**: Full integration with Omarchy IPC (`omarchy-shell shell summon ...`).

---

## Requirements

Ensure you have `yt-dlp` and `ffmpeg` installed:

```bash
# Arch Linux
sudo pacman -S yt-dlp ffmpeg python
```

---

## Installation

### Method 1: Local Development / Manual Enable

1. Copy the plugin folder to your Omarchy plugins directory:

```bash
cp -r io.github.adriano.media-downloader ~/.config/omarchy/plugins/
```

2. Validate the plugin:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.adriano.media-downloader
```

3. Enable the plugin in the Omarchy bar (e.g., right section):

```bash
omarchy plugin enable io.github.adriano.media-downloader right
```

---

## Hyprland Keyboard Shortcut

To summon the Media Downloader directly from anywhere using `SUPER + SHIFT + D`, add this line to your Hyprland configuration (`~/.config/hypr/hyprland.conf` or `~/.config/hypr/binds.conf`):

```ini
bind = $mainMod SHIFT, D, exec, omarchy-shell shell summon io.github.adriano.media-downloader '{}'
```

---

## Architecture

- **`manifest.json`**: Plugin metadata and configuration schema.
- **`BarWidget.qml`**: Bar button with icon, click handlers, and IPC listener.
- **`Panel.qml`**: Quickshell UI panel with state management and animations.
- **`downloaderctl.py`**: Python backend interface to `yt-dlp` with structured JSON output and progress streaming.
- **`Model.js`**: Helpers for durations, byte formatting, and URL parsing.
