#!/usr/bin/env python3
"""
Ableton Live Auto-Version & Audio Export Tool
goodvibrations HQ — Producer Toolkit

Workflow:
1. Single-instance lock: ensures duplicate F1 presses do not launch concurrent scripts.
2. Detects the currently open Ableton Live project set and folder (using instant Spotlight mdfind).
3. Checks if an audio export (.wav, .mp3, etc.) already exists for the CURRENT version:
   - If an export ALREADY exists:
       Increments to the next version number (e.g., Project_2 -> Project_3),
       triggers "Save Live Set As..." with the new version name,
       and exports audio with the matching new version name into the project folder.
   - If NO export exists yet for this version:
       Exports audio with the current version name into the project folder.
4. Executes a single atomic, fast AppleScript (under 3 seconds) that works on both
   single-screen and multi-monitor setups.
5. Posts a native macOS notification.
"""

from __future__ import annotations

import os
import re
import sys
import glob
import time
import fcntl
import subprocess
from pathlib import Path

AUDIO_EXTENSIONS = {".wav", ".mp3", ".aif", ".aiff", ".flac", ".m4a"}

# Single-instance file lock
LOCK_PATH = "/tmp/gv_ableton_export.lock"


def acquire_lock():
    try:
        lock_file = open(LOCK_PATH, "w")
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return lock_file
    except (IOError, BlockingIOError):
        print("⏳ Export is already running.", file=sys.stderr)
        sys.exit(0)


def get_latest_ableton_log() -> Path | None:
    """Finds the most recently modified Ableton Live Log.txt."""
    home = Path.home()
    pref_dir = home / "Library" / "Preferences" / "Ableton"
    if not pref_dir.exists():
        return None

    log_files = list(pref_dir.glob("Live */Log.txt"))
    if not log_files:
        return None

    return max(log_files, key=lambda p: p.stat().st_mtime)


def is_template_path(path: Path | None) -> bool:
    """Checks whether the file path points to an Ableton template, autosave, or factory default."""
    if not path:
        return False
    p_lower = str(path).lower()
    if "/templates/" in p_lower or "creating tracks" in p_lower:
        return True
    if "/factory packs/" in p_lower or "/core library/" in p_lower or "/app-resources/" in p_lower:
        return True
    if "/basefiles/" in p_lower or "/preferences/ableton/" in p_lower or "/crash/" in p_lower or "/undo/" in p_lower:
        return True
    return False


def find_project_by_name(project_name: str) -> Path | None:
    """Instantly finds a project's .als file using Spotlight mdfind (runs in milliseconds)."""
    if not project_name:
        return None
    try:
        escaped = project_name.replace("'", "\\'")
        res = subprocess.run(
            ["mdfind", f"kMDItemFSName == '{escaped}.als'"],
            capture_output=True, text=True, timeout=2.0
        )
        for line in res.stdout.splitlines():
            p = Path(line.strip())
            if p.exists() and not is_template_path(p):
                return p
    except Exception:
        pass

    candidates = [
        Path.home() / "Documents" / "Music Projects",
        Path.home() / "Music",
    ]
    for c in candidates:
        if c.exists():
            direct = list(c.glob(f"**/{project_name}.als"))
            for p in direct:
                if not is_template_path(p):
                    return p
    return None


def is_untitled_name(name: str | None) -> bool:
    """Checks if a track/project name is an unsaved default like 'Untitled'."""
    if not name:
        return True
    s = name.strip().lower()
    if s.endswith(".als"):
        s = s[:-4].strip()
    return (
        s == "untitled"
        or s.startswith("untitled")
        or s == "sans titre"
        or s.startswith("sans titre")
        or s == "ohne titel"
        or s.startswith("ohne titel")
    )


def is_plugin_window_title(title: str) -> bool:
    """Detects plugin editor windows which follow 'Plugin Name/Track Name' format."""
    return "/" in title or "\\" in title


def show_untitled_warning(win_title: str | None = None):
    """Alerts the producer that the active project is Untitled and must be saved with a name first."""
    title = "Save Track With a Name"
    msg = (
        "This Live set is Untitled.\n\n"
        "Please save your track with a name first before auto-exporting:\n"
        "File → Save Live Set As..."
    )
    notify("goodvibrations HQ", "⚠️ Track is Untitled: Please save your track with a name first.")

    escaped_title = title.replace('"', '\\"')
    escaped_msg = msg.replace('"', '\\"').replace("\n", "\\n")
    alert_script = f'''
    try
        tell application "System Events"
            activate
            display alert "{escaped_title}" message "{escaped_msg}" as warning buttons {{"OK"}} default button "OK" giving up after 20
        end tell
    on error
        try
            display alert "{escaped_title}" message "{escaped_msg}" as warning buttons {{"OK"}} default button "OK" giving up after 20
        end try
    end try
    '''
    subprocess.run(["osascript", "-e", alert_script])


def get_ableton_window_titles() -> list[str]:
    """Uses AppleScript / System Events to get all window titles of Ableton Live."""
    script = '''
    tell application "System Events"
        if exists (first process whose name contains "Live" and background only is false) then
            set abletonProc to (first process whose name contains "Live" and background only is false)
            try
                return name of every window of abletonProc
            on error
                return {}
            end try
        end if
    end tell
    return {}
    '''
    res = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if res.returncode != 0 or not res.stdout.strip():
        return []

    titles = [t.strip() for t in res.stdout.strip().split(",") if t.strip()]
    return titles


def find_main_ableton_window_title(titles: list[str]) -> str | None:
    """
    Finds the main Live project window title among all open windows.
    Filters out floating VST/AU plugin windows (which contain '/') and utility dialogs.
    """
    for title in titles:
        t_clean = title.strip()
        if not is_plugin_window_title(t_clean):
            if "[Arrangement]" in t_clean or "[Session]" in t_clean or t_clean.lower().endswith(".als"):
                return t_clean

    ignored = {"live", "second window", "export audio/video", "preferences", "save", "save as"}
    for title in titles:
        t_clean = title.strip()
        if not is_plugin_window_title(t_clean) and t_clean.lower() not in ignored and t_clean:
            return t_clean

    non_plugins = [t.strip() for t in titles if not is_plugin_window_title(t.strip()) and t.strip()]
    if non_plugins:
        return non_plugins[0]

    return titles[0] if titles else None


def clean_project_name_from_title(title: str | None) -> str | None:
    """Extracts project stem name from Ableton window title."""
    if not title:
        return None
    s = title.strip()
    s = re.sub(r"\s*\[(Arrangement|Session)\]\s*", "", s, flags=re.IGNORECASE)
    s = s.rstrip("*").strip()
    if s.lower().endswith(".als"):
        s = s[:-4].strip()
    return s if s else None


def get_active_project_path() -> tuple[Path | None, bool]:
    """
    Parses Ableton's active Log.txt and window titles to find the currently open .als project.
    Returns (als_path, is_untitled_or_template).
    """
    log_path = get_latest_ableton_log()
    last_doc: Path | None = None
    is_template = False

    if log_path and log_path.exists():
        file_size = log_path.stat().st_size
        bytes_to_read = min(file_size, 5 * 1024 * 1024)

        with open(log_path, "rb") as f:
            f.seek(max(0, file_size - bytes_to_read))
            content = f.read().decode("utf-8", errors="ignore")

        template_marker = "TryToLoadTemplate:"
        doc_markers = [
            ': info: Loading document "',
            ': info: Saving document "',
            'Loading document "',
            'Saving document "',
            ': info: Document "',
        ]

        for line in content.splitlines():
            if template_marker in line:
                is_template = True
            for marker in doc_markers:
                if marker in line:
                    start = line.find(marker) + len(marker)
                    end = line.find('"', start)
                    if end != -1:
                        path_str = line[start:end]
                        if path_str.endswith(".als"):
                            cand = Path(path_str)
                            if is_template_path(cand):
                                is_template = True
                                last_doc = cand
                            else:
                                is_template = False
                                last_doc = cand
                    break

    win_titles = get_ableton_window_titles()
    main_title = find_main_ableton_window_title(win_titles)
    project_name = clean_project_name_from_title(main_title)

    # 1. If window title points to a saved project, find it instantly via Spotlight (runs in ~80ms)
    if project_name and not is_untitled_name(project_name):
        spotlight_hit = find_project_by_name(project_name)
        if spotlight_hit and spotlight_hit.exists():
            return spotlight_hit, False

        # Check adjacent to last_doc
        if last_doc and last_doc.parent.exists():
            direct_cand = last_doc.parent / f"{project_name}.als"
            if direct_cand.exists() and not is_template_path(direct_cand):
                return direct_cand, False

    # 2. Check last_doc from Log.txt
    if last_doc and not is_template and last_doc.exists() and not is_untitled_name(last_doc.stem):
        return last_doc, False

    if is_template or not last_doc:
        return last_doc, True

    if is_untitled_name(last_doc.stem):
        return last_doc, True

    return last_doc, False


def has_existing_export(folder: Path, current_name: str) -> bool:
    """
    Checks if an audio export (.wav, .mp3, etc.) already exists for current_name
    in the project folder or any common export subfolder (e.g., Exports/).
    """
    stem_target = current_name.lower()

    search_dirs = [folder]
    for sub in ["Exports", "exports", "Bounces", "bounces", "Demos", "demos"]:
        sub_dir = folder / sub
        if sub_dir.is_dir():
            search_dirs.append(sub_dir)

    for directory in search_dirs:
        try:
            for item in directory.iterdir():
                if item.is_file() and item.suffix.lower() in AUDIO_EXTENSIONS:
                    if item.stem.lower() == stem_target:
                        return True
        except Exception:
            pass

    return False


def extract_base_and_versions(folder: Path, current_name: str) -> tuple[str, int]:
    """
    Determines the project's base name and highest existing version number
    by scanning all .als files and audio exports in the folder and export subfolders.
    """
    name = current_name[:-4] if current_name.lower().endswith(".als") else current_name

    version_match = re.search(r"^(.*?)(?:[_\s]+v?(\d+))$", name, re.IGNORECASE)
    if version_match:
        base_name = version_match.group(1).strip()
        current_num = int(version_match.group(2))
    else:
        base_name = name.strip()
        current_num = 1

    highest_version = max(current_num, 1)

    escaped_base = re.escape(base_name)
    pattern = re.compile(
        rf"^{escaped_base}(?:[_\s]+v?(\d+))?\.(als|wav|mp3|aif|aiff|flac|m4a)$",
        re.IGNORECASE
    )

    search_dirs = [folder]
    for sub in ["Exports", "exports", "Bounces", "bounces", "Demos", "demos"]:
        sub_dir = folder / sub
        if sub_dir.is_dir():
            search_dirs.append(sub_dir)

    for directory in search_dirs:
        try:
            for entry in directory.iterdir():
                if entry.is_file():
                    m = pattern.match(entry.name)
                    if m:
                        num_str = m.group(1)
                        if num_str:
                            highest_version = max(highest_version, int(num_str))
                        else:
                            highest_version = max(highest_version, 1)
        except Exception as e:
            print(f"Warning scanning folder {directory}: {e}", file=sys.stderr)

    return base_name, highest_version


def notify(title: str, message: str):
    """Sends a native macOS notification."""
    escaped_title = title.replace('"', '\\"')
    escaped_msg = message.replace('"', '\\"')
    subprocess.run([
        "osascript", "-e",
        f'display notification "{escaped_msg}" with title "{escaped_title}"'
    ])


def automate_ableton(folder_path: str, target_name: str, create_new_version: bool) -> bool:
    """
    Executes a single, fast, atomic AppleScript automation.
    Completes in ~2.5 - 3.5 seconds total with zero subprocess polling lag.
    Navigates the Save dialog directly to folder_path using Cmd+Shift+G so exports
    always land in the correct project folder.
    Works identically on single-screen and dual-screen configurations.
    """
    escaped_folder = folder_path.replace('"', '\\"')
    escaped_target = target_name.replace('"', '\\"')

    save_as_part = f'''
    -- Save Live Set As... (Shift + Cmd + S)
    tell process "Live"
        keystroke "s" using {{command down, shift down}}
    end tell
    delay 0.5

    set the clipboard to "{escaped_target}"
    tell process "Live"
        keystroke "a" using {{command down}}
        delay 0.05
        keystroke "v" using {{command down}}
        delay 0.15
        key code 36 -- Return to save new set
    end tell
    delay 1.0
    ''' if create_new_version else '''
    delay 0.2
    '''

    atomic_script = f'''
    tell application "Live" to activate
    tell application "System Events"
        set frontmost of process "Live" to true
        repeat 20 times
            if frontmost of process "Live" then exit repeat
            delay 0.04
        end repeat

        -- 1. Raise real project window (ignoring floating plugin windows with "/")
        tell process "Live"
            set mainWin to missing value
            repeat with w in (every window)
                try
                    set wName to name of w
                    if wName does not contain "/" and wName is not "" and wName is not "Live" then
                        set mainWin to w
                        exit repeat
                    end if
                end try
            end repeat
            if mainWin is not missing value then
                perform action "AXRaise" of mainWin
            end if
        end tell
        delay 0.2

        {save_as_part}

        -- 2. Open Export Audio/Video (Shift + Cmd + R)
        tell process "Live"
            keystroke "r" using {{command down, shift down}}
        end tell
        delay 0.5

        -- 3. Confirm Export settings dialog (Return clicks 'Export' and opens Save dialog)
        repeat 10 times
            tell process "Live" to key code 36
            delay 0.2
            tell process "Live"
                if exists (first window whose name is "Save") then exit repeat
            end tell
        end repeat

        -- 4. Navigate Save panel to project folder and set export filename
        set the clipboard to "{escaped_folder}"
        tell process "Live"
            if exists (first window whose name is "Save") then
                -- Drop "Go to the folder:" sheet via Cmd+Shift+G
                keystroke "g" using {{command down, shift down}}
                delay 0.35
                -- Paste target folder path and navigate
                keystroke "v" using {{command down}}
                delay 0.15
                key code 36
                delay 0.35

                -- Set target filename
                set the clipboard to "{escaped_target}"
                keystroke "a" using {{command down}}
                delay 0.05
                keystroke "v" using {{command down}}
                delay 0.15

                try
                    set s to window "Save"
                    set sg to first UI element of s whose role is "AXSplitGroup"
                    click (first button of sg whose name is "Save" or title is "Save")
                on error
                    key code 36
                end try
            else
                key code 36
            end if
        end tell

        delay 0.5
        -- 5. Auto-confirm Replace if file already exists
        tell process "Live"
            try
                if exists (first window whose name is "Save") then
                    click (first button of (first sheet of window "Save") whose name is "Replace")
                end if
            end try
        end tell
    end tell
    '''

    res = subprocess.run(["osascript", "-e", atomic_script], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"AppleScript error: {res.stderr.strip()}", file=sys.stderr)
        return False
    return True


def main():
    lock_file = acquire_lock()

    print("🔍 Inspecting active Ableton Live session...")
    win_titles = get_ableton_window_titles()
    main_win = find_main_ableton_window_title(win_titles)

    if main_win:
        main_stem = clean_project_name_from_title(main_win)
        if is_untitled_name(main_stem):
            print(f"⚠️ Active Ableton window is Untitled: '{main_win}'.", file=sys.stderr)
            show_untitled_warning(main_win)
            sys.exit(2)

    als_path, is_untitled_or_template = get_active_project_path()

    if is_untitled_or_template or not als_path or not als_path.exists() or is_untitled_name(als_path.stem):
        print(f"⚠️ Active project is Untitled or a template (Path: '{als_path}', Window: '{main_win}').", file=sys.stderr)
        show_untitled_warning(main_win)
        sys.exit(2)

    project_folder = als_path.parent
    current_set_name = als_path.stem

    print(f"📂 Project Folder: {project_folder}")
    print(f"🎵 Active Set:     {current_set_name}")

    already_exported = has_existing_export(project_folder, current_set_name)

    if already_exported:
        base_name, highest_version = extract_base_and_versions(project_folder, current_set_name)
        next_version = highest_version + 1
        target_name = f"{base_name}_{next_version}"
        create_new_version = True
        print(f"📦 Found existing export for '{current_set_name}'.")
        print(f"✨ Incrementing to new version: '{target_name}'.")
        notify("goodvibrations HQ", f"Saving as {target_name} & exporting...")
    else:
        target_name = current_set_name
        create_new_version = False
        print(f"🆕 No export found for '{current_set_name}' yet.")
        print(f"🎵 Exporting as '{target_name}'.")
        notify("goodvibrations HQ", f"Exporting: {target_name}...")

    success = automate_ableton(str(project_folder), target_name, create_new_version=create_new_version)

    if success:
        action_desc = "New version saved and exporting" if create_new_version else "Exporting"
        notify("goodvibrations HQ", f"{action_desc}: {target_name}")
        print(f"✅ Successfully initiated export for '{target_name}'.")

        # Background watcher ensures the rendered file lands in project_folder
        escaped_proj = str(project_folder).replace('"', '\\"')
        escaped_target = target_name.replace('"', '\\"')
        relocate_script = f"""
import time, shutil, subprocess
from pathlib import Path

target_stem = "{escaped_target}"
dst_dir = Path("{escaped_proj}")
now = time.time()

for _ in range(180):
    time.sleep(1)
    try:
        if any(f.stem == target_stem and f.suffix.lower() in {{".wav", ".mp3", ".aif", ".flac"}} for f in dst_dir.iterdir() if f.is_file()):
            break
        # Instant Spotlight search for rendered file
        res = subprocess.run(["mdfind", f'kMDItemFSName == "{{target_stem}}.*" && kMDItemFSContentChangeDate >= $time.now(-300)'], capture_output=True, text=True)
        found = None
        for line in res.stdout.strip().splitlines():
            cand = Path(line.strip())
            if cand.is_file() and cand.suffix.lower() in {{".wav", ".mp3", ".aif", ".flac"}} and cand.parent != dst_dir:
                found = cand
                break
        if found:
            try:
                shutil.move(str(found), str(dst_dir / found.name))
            except Exception:
                pass
            break
    except Exception:
        pass
"""
        subprocess.Popen(
            [sys.executable, "-c", relocate_script],
            close_fds=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    else:
        notify("goodvibrations HQ", "Export automation encountered an issue.")
        print("❌ Automation failed.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
