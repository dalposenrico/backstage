#!/usr/bin/env python3
"""
Ableton Live Auto-Version & Audio Export Tool
goodvibrations HQ — Producer Toolkit

Workflow:
1. Detects the currently open Ableton Live project set and folder.
2. Checks if an audio export (.wav, .mp3, etc.) already exists for the CURRENT version:
   - If an export ALREADY exists:
       Increments to the next version number (e.g., Project_2 -> Project_3),
       triggers "Save Live Set As..." with the new version name,
       and exports audio with the matching new version name into the project folder.
   - If NO export exists yet for this version:
       Simply saves the current set (Cmd+S),
       and exports audio with the current version name into the project folder.
3. Posts a native macOS notification.
"""

from __future__ import annotations

import os
import re
import sys
import glob
import time
import subprocess
from pathlib import Path

AUDIO_EXTENSIONS = {".wav", ".mp3", ".aif", ".aiff", ".flac", ".m4a"}


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
    """Checks whether the file path points to an Ableton template or factory default."""
    if not path:
        return False
    p_lower = str(path).lower()
    if "/templates/" in p_lower or "creating tracks" in p_lower:
        return True
    if "/factory packs/" in p_lower or "/core library/" in p_lower or "/app-resources/" in p_lower:
        return True
    return False


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


def show_untitled_warning(win_title: str | None = None):
    """
    Alerts the producer that the active project is Untitled and must be saved with a name first.
    Presents both a native macOS notification and an alert dialog.
    """
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


def get_active_project_path() -> tuple[Path | None, bool]:
    """
    Parses Ableton's active Log.txt to find the currently open .als project.
    Returns (als_path, is_untitled_or_template).
    """
    log_path = get_latest_ableton_log()
    if not log_path or not log_path.exists():
        return None, True

    file_size = log_path.stat().st_size
    bytes_to_read = min(file_size, 1024 * 1024)

    with open(log_path, "rb") as f:
        f.seek(max(0, file_size - bytes_to_read))
        content = f.read().decode("utf-8", errors="ignore")

    doc_marker = ': info: Loading document "'
    template_marker = "TryToLoadTemplate:"

    last_doc: Path | None = None
    is_template = False

    for line in content.splitlines():
        if template_marker in line:
            is_template = True
        elif doc_marker in line:
            start = line.find(doc_marker) + len(doc_marker)
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

    if is_template or not last_doc:
        return last_doc, True

    if is_untitled_name(last_doc.stem):
        return last_doc, True

    return last_doc, False


def get_ableton_window_title() -> str | None:
    """Uses AppleScript / System Events to get the front window title of Ableton Live."""
    script = '''
    tell application "System Events"
        if exists (first process whose name contains "Live" and background only is false) then
            set abletonProc to (first process whose name contains "Live" and background only is false)
            try
                return name of front window of abletonProc
            on error
                return ""
            end try
        end if
    end tell
    return ""
    '''
    res = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    title = res.stdout.strip()
    return title if title else None


def has_existing_export(folder: Path, current_name: str) -> bool:
    """
    Checks if an audio export (.wav, .mp3, etc.) already exists for current_name
    in the project folder or any common export subfolder (e.g., Exports/).
    """
    stem_target = current_name.lower()

    # Search directly in the project folder and in common export subdirectories
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
    by scanning all .als files and audio exports in the folder.
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

    try:
        for entry in folder.iterdir():
            if entry.is_file():
                m = pattern.match(entry.name)
                if m:
                    num_str = m.group(1)
                    if num_str:
                        highest_version = max(highest_version, int(num_str))
                    else:
                        highest_version = max(highest_version, 1)
    except Exception as e:
        print(f"Warning scanning folder: {e}", file=sys.stderr)

    return base_name, highest_version


def run_applescript(script: str) -> bool:
    """Executes AppleScript code via osascript."""
    res = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"AppleScript error: {res.stderr.strip()}", file=sys.stderr)
        return False
    return True


def notify(title: str, message: str):
    """Sends a native macOS notification."""
    escaped_title = title.replace('"', '\\"')
    escaped_msg = message.replace('"', '\\"')
    subprocess.run([
        "osascript", "-e",
        f'display notification "{escaped_msg}" with title "{escaped_title}"'
    ])


def automate_ableton(folder_path: str, target_name: str, create_new_version: bool):
    """
    Automates Ableton Live:
    - If `create_new_version` is True:
        Runs 'Save Live Set As...' with `target_name`.
    - If `create_new_version` is False:
        Runs standard 'Save' (Cmd+S) to preserve changes without renaming.
    - Runs 'Export Audio/Video...' navigating to `folder_path` with `target_name`.
    """
    save_as_logic = f'''
    -- Save Live Set As... (Shift + Cmd + S)
    tell application "System Events"
        keystroke "s" using {{command down, shift down}}
    end tell
    delay 0.8

    tell application "System Events"
        set the clipboard to targetName
        keystroke "a" using {{command down}}
        delay 0.1
        keystroke "v" using {{command down}}
        delay 0.2
        key code 36 -- Return / Enter
    end tell
    delay 1.0
    ''' if create_new_version else '''
    -- Save current set (Cmd + S)
    tell application "System Events"
        keystroke "s" using {{command down}}
    end tell
    delay 0.6
    '''

    script = f'''
    set folderPath to "{folder_path}"
    set targetName to "{target_name}"

    -- 1. Activate Ableton Live
    tell application "System Events"
        if not (exists (first process whose name contains "Live" and background only is false)) then
            error "Ableton Live is not currently running."
        end if
        set abletonProc to (first process whose name contains "Live" and background only is false)
        set frontmost of abletonProc to true
    end tell
    delay 0.3

    {save_as_logic}

    -- 2. Export Audio/Video... (Shift + Cmd + R)
    tell application "System Events"
        keystroke "r" using {{command down, shift down}}
    end tell
    delay 1.0

    -- In Ableton's render settings dialog, press Return to click default 'Export'
    tell application "System Events"
        key code 36 -- Return to open save dialog
    end tell
    delay 0.8

    -- 3. Navigate to Project Folder in the macOS Save Dialog (Cmd + Shift + G)
    tell application "System Events"
        keystroke "g" using {{command down, shift down}}
    end tell
    delay 0.5

    tell application "System Events"
        set the clipboard to folderPath
        keystroke "a" using {{command down}}
        delay 0.1
        keystroke "v" using {{command down}}
        delay 0.2
        key code 36 -- Confirm folder path
    end tell
    delay 0.6

    -- 4. Set Export Audio Filename to targetName and confirm
    tell application "System Events"
        set the clipboard to targetName
        keystroke "a" using {{command down}}
        delay 0.1
        keystroke "v" using {{command down}}
        delay 0.2
        key code 36 -- Confirm Save / Start Render!
    end tell
    '''

    return run_applescript(script)


def main():
    print("🔍 Inspecting active Ableton Live session...")
    win_title = get_ableton_window_title()

    # 1. Check if Ableton window title indicates an Untitled set
    if win_title and (
        "untitled" in win_title.lower()
        or "sans titre" in win_title.lower()
        or "ohne titel" in win_title.lower()
    ):
        print(f"⚠️ Active Ableton window is Untitled: '{win_title}'.", file=sys.stderr)
        show_untitled_warning(win_title)
        sys.exit(2)

    als_path, is_untitled_or_template = get_active_project_path()

    # 2. Check if the project is a template, nonexistent, or named Untitled
    if is_untitled_or_template or not als_path or not als_path.exists() or is_untitled_name(als_path.stem):
        print(f"⚠️ Active project is Untitled or a template (Path: '{als_path}', Window: '{win_title}').", file=sys.stderr)
        show_untitled_warning(win_title)
        sys.exit(2)

    project_folder = als_path.parent
    current_set_name = als_path.stem

    print(f"📂 Project Folder: {project_folder}")
    print(f"🎵 Active Set:     {current_set_name}")

    already_exported = has_existing_export(project_folder, current_set_name)

    if already_exported:
        # An audio export already exists for this version -> increment version!
        base_name, highest_version = extract_base_and_versions(project_folder, current_set_name)
        next_version = highest_version + 1
        target_name = f"{base_name}_{next_version}"
        create_new_version = True
        print(f"📦 Found existing export for '{current_set_name}'.")
        print(f"✨ Incrementing to new version: '{target_name}'.")
        notify("goodvibrations HQ", f"Saving as {target_name} & exporting...")
    else:
        # No export exists yet for this version -> stay on current version!
        target_name = current_set_name
        create_new_version = False
        print(f"🆕 No export found for '{current_set_name}' yet.")
        print(f"🎵 Saving set and exporting as '{target_name}'.")
        notify("goodvibrations HQ", f"Saving & exporting: {target_name}...")

    success = automate_ableton(str(project_folder), target_name, create_new_version=create_new_version)

    if success:
        action_desc = "New version saved and exporting" if create_new_version else "Exporting"
        notify("goodvibrations HQ", f"{action_desc}: {target_name}")
        print(f"✅ Successfully initiated export for '{target_name}'.")
    else:
        notify("goodvibrations HQ", "Export automation encountered an issue.")
        print("❌ Automation failed.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
