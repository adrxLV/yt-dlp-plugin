#!/usr/bin/env python3
"""
downloaderctl.py - Backend helper for Omarchy Media Downloader plugin.
Interfaces with yt-dlp, ffmpeg, and manages history/downloads.
"""

import sys
import os
import json
import subprocess
import argparse
import time
import shutil
import re
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "omarchy" / "media-downloader"
HISTORY_FILE = CONFIG_DIR / "history.json"
MAX_OUTPUT_BYTES = 10 * 1024 * 1024  # 10 MB ceiling for json metadata
DEFAULT_TIMEOUT = 30  # 30s timeout for search and info subprocess calls


def ensure_config_dir():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)


def format_duration(seconds):
    if not seconds or seconds <= 0:
        return "--:--"
    try:
        s = int(seconds)
        m, s = divmod(s, 60)
        h, m = divmod(m, 60)
        if h > 0:
            return f"{h}:{m:02d}:{s:02d}"
        return f"{m}:{s:02d}"
    except Exception:
        return "--:--"


def load_history():
    ensure_config_dir()
    if not HISTORY_FILE.exists():
        return []
    try:
        with open(HISTORY_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


def save_history(entry):
    ensure_config_dir()
    history = load_history()
    # Deduplicate by url/path
    history = [h for h in history if h.get("url") != entry.get("url") or h.get("path") != entry.get("path")]
    history.insert(0, entry)
    history = history[:50]  # keep latest 50
    try:
        with open(HISTORY_FILE, "w", encoding="utf-8") as f:
            json.dump(history, f, indent=2, ensure_ascii=False)
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to save history: {e}\n")


def send_notification(title, message, icon="media-playback-start"):
    if shutil.which("notify-send"):
        try:
            subprocess.run(
                ["notify-send", "-a", "Media Downloader", "-i", icon, title, message],
                capture_output=True,
                check=False
            )
        except Exception:
            pass


def get_best_thumbnail(entry):
    thumbs = entry.get("thumbnails")
    if thumbs and isinstance(thumbs, list):
        # Pick the largest/latest thumbnail
        for t in reversed(thumbs):
            url = t.get("url")
            if url:
                return url
    return entry.get("thumbnail") or ""


def cmd_search(query, limit=15):
    query = (query or "").strip()
    if not query:
        print(json.dumps({"status": "error", "message": "Empty query"}))
        return 1

    search_target = f"ytsearch{limit}:{query}"
    cmd = [
        "yt-dlp",
        search_target,
        "--flat-playlist",
        "--dump-single-json",
        "--no-warnings",
        "--ignore-errors"
    ]

    try:
        res = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=DEFAULT_TIMEOUT
        )
        if res.returncode != 0 and not res.stdout.strip():
            print(json.dumps({"status": "error", "message": res.stderr.strip() or "Search failed"}))
            return 1

        stdout_content = res.stdout
        if len(stdout_content) > MAX_OUTPUT_BYTES:
            print(json.dumps({"status": "error", "message": "Search output exceeded maximum allowed size"}))
            return 1

        data = json.loads(stdout_content) if stdout_content.strip() else {}
        raw_entries = data.get("entries", [])
        results = []

        for e in raw_entries:
            if not e:
                continue
            video_id = e.get("id") or ""
            video_url = e.get("url") or ""
            if not video_id and not video_url:
                continue
            if video_id and not video_url.startswith("http"):
                video_url = f"https://www.youtube.com/watch?v={video_id}"
            elif not video_url.startswith("http"):
                continue

            dur = e.get("duration")
            results.append({
                "id": video_id,
                "title": e.get("title") or "Unknown Title",
                "channel": e.get("channel") or e.get("uploader") or "YouTube",
                "duration": dur or 0,
                "duration_str": format_duration(dur),
                "thumbnail": get_best_thumbnail(e),
                "url": video_url
            })

        print(json.dumps({
            "status": "ok",
            "type": "search",
            "query": query,
            "count": len(results),
            "results": results
        }, ensure_ascii=False))
        return 0
    except subprocess.TimeoutExpired:
        print(json.dumps({"status": "error", "message": "Search timed out"}))
        return 1
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}))
        return 1


def cmd_info(url):
    url = (url or "").strip()
    if not url:
        print(json.dumps({"status": "error", "message": "Empty URL"}))
        return 1

    cmd = [
        "yt-dlp",
        url,
        "--dump-single-json",
        "--no-playlist",
        "--no-warnings",
        "--ignore-errors"
    ]

    try:
        res = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=DEFAULT_TIMEOUT
        )
        if res.returncode != 0 and not res.stdout.strip():
            print(json.dumps({"status": "error", "message": res.stderr.strip() or "Failed to fetch metadata"}))
            return 1

        stdout_content = res.stdout
        if len(stdout_content) > MAX_OUTPUT_BYTES:
            print(json.dumps({"status": "error", "message": "Metadata output exceeded maximum allowed size"}))
            return 1

        data = json.loads(stdout_content)
        dur = data.get("duration")
        result = {
            "id": data.get("id") or "",
            "title": data.get("title") or "Unknown Title",
            "channel": data.get("channel") or data.get("uploader") or "Online Media",
            "duration": dur or 0,
            "duration_str": format_duration(dur),
            "thumbnail": get_best_thumbnail(data),
            "url": data.get("webpage_url") or url,
            "extractor": data.get("extractor_key") or data.get("extractor") or "Media"
        }

        print(json.dumps({
            "status": "ok",
            "type": "info",
            "result": result
        }, ensure_ascii=False))
        return 0
    except subprocess.TimeoutExpired:
        print(json.dumps({"status": "error", "message": "Metadata request timed out"}))
        return 1
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}))
        return 1


def cmd_download(args):
    url = args.url.strip()
    mode = args.mode.lower()
    quality = args.quality.lower()
    audio_format = args.audio_format.lower()
    out_dir = os.path.expanduser(args.out_dir)

    os.makedirs(out_dir, exist_ok=True)

    # Output template
    output_template = os.path.join(out_dir, "%(title)s.%(ext)s")

    cmd = [
        "yt-dlp",
        "--newline",
        "--no-playlist",
        "--progress",
        "--output", output_template
    ]

    if mode == "audio":
        cmd += [
            "-x",
            "--audio-format", audio_format,
            "--audio-quality", "0"
        ]
    else:  # video
        if quality == "1080":
            cmd += ["--format", "bv*[height<=1080]+ba/b[height<=1080]/best"]
        elif quality == "720":
            cmd += ["--format", "bv*[height<=720]+ba/b[height<=720]/best"]
        elif quality == "480":
            cmd += ["--format", "bv*[height<=480]+ba/b[height<=480]/best"]
        else:  # best
            cmd += ["--format", "bv*+ba/b"]
        cmd += ["--merge-output-format", "mp4"]

    # Custom progress template (using download: prefix to avoid suppressing other stages)
    progress_tpl = 'download:PROGRESS:{"percent":"%(progress._percent_str)s","downloaded":"%(progress._downloaded_bytes_str)s","total":"%(progress._total_bytes_str)s","speed":"%(progress._speed_str)s","eta":"%(progress._eta_str)s","status":"%(progress.status)s"}'
    cmd += [
        "--progress-template", progress_tpl,
        "--exec", "after_move:echo FINAL_PATH:{}"
    ]
    cmd.append(url)

    final_path = ""
    final_title = ""

    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )

        for line in process.stdout:
            line_str = line.strip()
            if not line_str:
                continue

            # Strip ANSI escape codes
            clean_line = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', line_str).strip()

            if "PROGRESS:" in clean_line:
                idx = clean_line.find("PROGRESS:")
                json_part = clean_line[idx + len("PROGRESS:"):].strip()
                try:
                    pdata = json.loads(json_part)
                    percent_raw = str(pdata.get("percent", "")).strip()
                    speed_raw = str(pdata.get("speed", "")).strip()
                    eta_raw = str(pdata.get("eta", "")).strip()
                    dl_raw = str(pdata.get("downloaded", "")).strip()
                    tot_raw = str(pdata.get("total", "")).strip()
                    status_raw = str(pdata.get("status", "")).strip()

                    clean_obj = {
                        "percent": percent_raw if percent_raw != "NA" else "100%",
                        "speed": speed_raw if speed_raw not in ("NA", "Unknown", "Unknown B/s") else "—",
                        "eta": eta_raw if eta_raw not in ("NA", "Unknown") else "—",
                        "downloaded": dl_raw if dl_raw != "NA" else "",
                        "total": tot_raw if tot_raw != "NA" else "",
                        "status": status_raw if status_raw != "NA" else "downloading"
                    }
                    print(f"PROGRESS:{json.dumps(clean_obj)}", flush=True)
                except Exception:
                    pass
            elif clean_line.startswith("FINAL_PATH:"):
                extracted = clean_line[len("FINAL_PATH:"):].strip().strip("'\"")
                if extracted:
                    final_path = extracted
            elif "[Merger] Merging formats into " in clean_line:
                m = re.search(r'\[Merger\] Merging formats into ["\'](.*?)["\']', clean_line)
                if m:
                    final_path = m.group(1).strip()
                print(f'PROGRESS:{json.dumps({"percent": "100%", "speed": "—", "eta": "—", "downloaded": "", "total": "", "status": "Merging streams…"})}', flush=True)
            elif "[ExtractAudio] Destination: " in clean_line:
                dest = clean_line.split("[ExtractAudio] Destination: ", 1)[1].strip()
                final_path = dest
                print(f'PROGRESS:{json.dumps({"percent": "100%", "speed": "—", "eta": "—", "downloaded": "", "total": "", "status": "Extracting audio…"})}', flush=True)
            elif "has already been downloaded" in clean_line:
                m = re.search(r'\[download\] (.*?) has already been downloaded', clean_line)
                if m:
                    final_path = m.group(1).strip()
                print(f'PROGRESS:{json.dumps({"percent": "100%", "speed": "—", "eta": "—", "downloaded": "", "total": "", "status": "Already downloaded"})}', flush=True)
            elif clean_line.startswith("[download] Destination: ") and not final_path:
                cand = clean_line.split("[download] Destination: ", 1)[1].strip()
                if not any(cand.endswith(x) for x in [".f137", ".f248", ".f399", ".f395", ".f251", ".part"]):
                    final_path = cand

        process.wait()

        if process.returncode != 0:
            stderr_out = process.stderr.read()
            err_msg = stderr_out.strip() or "Download failed"
            print(f"ERROR:{json.dumps({'message': err_msg})}", flush=True)
            return process.returncode

        # If final_path not caught by print template, check output directory
        if not final_title:
            final_title = os.path.basename(final_path) if final_path else "Media Download"

        filesize_str = ""
        if final_path and os.path.exists(final_path):
            try:
                sz = os.path.getsize(final_path)
                if sz > 1024 * 1024 * 1024:
                    filesize_str = f"{sz / (1024*1024*1024):.1f} GB"
                elif sz > 1024 * 1024:
                    filesize_str = f"{sz / (1024*1024):.1f} MB"
                else:
                    filesize_str = f"{sz / 1024:.1f} KB"
            except Exception:
                pass

        history_entry = {
            "title": final_title,
            "path": final_path,
            "filename": os.path.basename(final_path) if final_path else final_title,
            "size": filesize_str,
            "mode": mode,
            "url": url,
            "timestamp": int(time.time()),
            "time_str": time.strftime("%Y-%m-%d %H:%M")
        }

        save_history(history_entry)

        complete_json = json.dumps(history_entry, ensure_ascii=False)
        print(f"COMPLETE:{complete_json}", flush=True)

        send_notification("Download Complete", f"{final_title}\nSaved to {final_path or out_dir}")
        return 0

    except Exception as e:
        print(f"ERROR:{json.dumps({'message': str(e)})}", flush=True)
        return 1


def cmd_history():
    history = load_history()
    print(json.dumps({"status": "ok", "history": history}, ensure_ascii=False))
    return 0


def cmd_clear_history():
    ensure_config_dir()
    try:
        with open(HISTORY_FILE, "w", encoding="utf-8") as f:
            json.dump([], f)
        print(json.dumps({"status": "ok"}))
        return 0
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}))
        return 1


def main():
    parser = argparse.ArgumentParser(description="Media downloader controller")
    subparsers = parser.add_subparsers(dest="command")

    # Search
    search_p = subparsers.add_parser("search")
    search_p.add_argument("query", help="Search query string")
    search_p.add_argument("--limit", type=int, default=15, help="Number of results (default: 15)")

    # Info
    info_p = subparsers.add_parser("info")
    info_p.add_argument("url", help="Media URL")

    # Download
    dl_p = subparsers.add_parser("download")
    dl_p.add_argument("--url", required=True, help="Media URL to download")
    dl_p.add_argument("--mode", default="video", choices=["video", "audio"], help="Download mode")
    dl_p.add_argument("--quality", default="best", choices=["best", "1080", "720", "480"], help="Video quality")
    dl_p.add_argument("--audio-format", default="mp3", choices=["mp3", "m4a", "opus", "flac", "wav"], help="Audio format")
    dl_p.add_argument("--out-dir", default="~/Downloads", help="Save directory")

    # History
    subparsers.add_parser("history")
    subparsers.add_parser("clear-history")

    args = parser.parse_args()

    if args.command == "search":
        sys.exit(cmd_search(args.query, args.limit))
    elif args.command == "info":
        sys.exit(cmd_info(args.url))
    elif args.command == "download":
        sys.exit(cmd_download(args))
    elif args.command == "history":
        sys.exit(cmd_history())
    elif args.command == "clear-history":
        sys.exit(cmd_clear_history())
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
