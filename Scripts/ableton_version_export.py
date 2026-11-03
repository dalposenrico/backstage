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
       Exports audio with the current version name into the project folder.
3. Robust multi-monitor / dual-screen & multi-plugin handling:
   - Filters out floating VST/AU plugin windows (which contain '/').
   - Raises the real Ableton project window even when positioned on a secondary display.
   - Detects the Export Audio/Video dialog bounds and triggers the Export button directly.
   - Confirms the Save panel to begin rendering into the project folder.
4. Posts a native macOS notification.
"""

from __future__ import annotations

import os
import re
import sys
import glob
import time
import ctypes
import subprocess
from ctypes import c_double, c_uint32, c_void_p, Structure
from pathlib import Path

AUDIO_EXTENSIONS = {".wav", ".mp3", ".aif", ".aiff", ".flac", ".m4a"}

# CoreGraphics mouse click definitions
class CGPoint(Structure):
    _fields_ = [("x", c_double), ("y", c_double)]

try:
    cg = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    cg.CGEventCreateMouseEvent.restype = c_void_p
    cg.CGEventCreateMouseEvent.argtypes = [c_void_p, c_uint32, CGPoint, c_uint32]
    cg.CGEventPost.argtypes = [c_uint32, c_void_p]
except Exception:
    cg = None


def click_screen_point(x: float, y: float):
    """Sends a hardware mouse double-click to (x, y) to reliably activate modal buttons across screens."""
    if cg is None:
        return
    pt = CGPoint(x, y)
    for _ in range(2):
        cg.CGEventPost(0, cg.CGEventCreateMouseEvent(None, 1, pt, 0))
        time.sleep(0.04)
        cg.CGEventPost(0, cg.CGEventCreateMouseEvent(None, 2, pt, 0))
        time.sleep(0.08)


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
        bytes_to_read = min(file_size, 20 * 1024 * 1024)

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

    if project_name and not is_untitled_name(project_name):
        if last_doc and last_doc.parent.exists():
            direct_cand = last_doc.parent / f"{project_name}.als"
            if direct_cand.exists():
                return direct_cand, False

    if last_doc and not is_template and last_doc.exists() and not is_untitled_name(last_doc.stem):
        return last_doc, False

    if project_name and not is_untitled_name(project_name):
        search_roots = [
            Path.home() / "Music",
            Path.home() / "Documents",
            Path.home() / "Desktop",
        ]
        if last_doc and last_doc.parent.exists():
            search_roots.insert(0, last_doc.parent)

        for root in search_roots:
            if not root.exists():
                continue
            matches = list(root.glob(f"**/{project_name}.als"))
            if matches:
                best = max(matches, key=lambda p: p.stat().st_mtime)
                return best, False

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
    Automates Ableton Live:
    - Multi-monitor aware: activates Live, ignores floating plugin windows, raises project window.
    - If `create_new_version`: Shift+Cmd+S to save new set name and waits for save.
    - Opens Export Audio/Video (Shift+Cmd+R).
    - Clicks the 'Export' button via exact dialog bounds and CoreGraphics click.
    - Confirms Save panel to render audio.
    """
    escaped_target = target_name.replace('"', '\\"')

    # 1. Activate Live, make frontmost, and raise the main project window
    activate_script = """
    tell application "Live" to activate
    tell application "System Events"
        set frontmost of process "Live" to true
        repeat 20 times
            if frontmost of process "Live" then exit repeat
            delay 0.05
        end repeat
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
    end tell
    """
    subprocess.run(["osascript", "-e", activate_script])
    time.sleep(0.3)

    # 2. Save Live Set As... if creating a new version
    if create_new_version:
        save_as_script = f"""
        tell application "System Events"
            tell process "Live"
                keystroke "s" using {{command down, shift down}}
            end tell
        end tell
        """
        subprocess.run(["osascript", "-e", save_as_script])
        time.sleep(0.8)

        type_name_script = f"""
        tell application "System Events"
            set the clipboard to "{escaped_target}"
            delay 0.05
            keystroke "a" using {{command down}}
            delay 0.05
            keystroke "v" using {{command down}}
            delay 0.2
            key code 36 -- Return / Save
        end tell
        """
        subprocess.run(["osascript", "-e", type_name_script])
        # Wait for Ableton to write the new project set to disk
        time.sleep(1.8)

    # 3. Open Export Audio/Video dialog (Shift + Cmd + R)
    open_export_script = """
    tell application "Live" to activate
    tell application "System Events"
        set frontmost of process "Live" to true
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
        keystroke "r" using {command down, shift down}
    end tell
    """
    subprocess.run(["osascript", "-e", open_export_script])

    # 4. Wait for Export Audio/Video dialog and get its exact screen bounds
    dlg_bounds = None
    for _ in range(40):
        time.sleep(0.1)
        res = subprocess.run(["osascript", "-e", """
        tell application "System Events"
            tell process "Live"
                repeat with w in windows
                    try
                        if name of w is "Export Audio/Video" or subrole of w is "AXDialog" then
                            set pos to position of w
                            set sz to size of w
                            return "" & (item 1 of pos) & " " & (item 2 of pos) & " " & (item 1 of sz) & " " & (item 2 of sz)
                        end if
                    end try
                end repeat
            end tell
        end tell
        """], capture_output=True, text=True)
        out = res.stdout.strip()
        if out:
            parts = out.split()
            if len(parts) == 4:
                dlg_bounds = [float(p) for p in parts]
                break

    if dlg_bounds:
        dx, dy, dw, dh = dlg_bounds
        # The Export button is at x + 108.0, y + h - 22.0
        btnX = dx + 108.0
        btnY = dy + dh - 22.0
        click_screen_point(btnX, btnY)
    else:
        # Fallback: send Return directly
        subprocess.run(["osascript", "-e", "tell application \"System Events\" to tell process \"Live\" to key code 36"])

    # 5. Wait for the macOS Save panel to appear
    save_opened = False
    for _ in range(40):
        time.sleep(0.1)
        res = subprocess.run(["osascript", "-e", """
        tell application "System Events"
            tell process "Live"
                if exists (first window whose name is "Save") then
                    return "yes"
                end if
            end tell
        end tell
        """], capture_output=True, text=True)
        if "yes" in res.stdout:
            save_opened = True
            break

    if not save_opened:
        # Extra fallback: send Return to trigger Export button if it didn't click
        subprocess.run(["osascript", "-e", "tell application \"System Events\" to tell process \"Live\" to key code 36"])
        time.sleep(0.6)

    # 6. Click Save in the Save dialog
    subprocess.run(["osascript", "-e", """
    tell application "System Events"
        tell process "Live"
            if exists (first window whose name is "Save") then
                set s to window "Save"
                try
                    set sg to first UI element of s whose role is "AXSplitGroup"
                    click (first button of sg whose name is "Save" or title is "Save")
                on error
                    key code 36
                end try
            end if
        end tell
    end tell
    """])

    time.sleep(0.5)
    # 7. Confirm Replace if file already exists
    subprocess.run(["osascript", "-e", """
    tell application "System Events"
        tell process "Live"
            try
                click (first button of (first sheet of window "Save") whose name is "Replace")
            end try
        end tell
    end tell
    """])

    return True


def main():
    print("🔍 Inspecting active Ableton Live session...")
    win_titles = get_ableton_window_titles()
    main_win = find_main_ableton_window_title(win_titles)

    # 1. Check if the MAIN Ableton window title indicates an Untitled set
    if main_win:
        main_stem = clean_project_name_from_title(main_win)
        if is_untitled_name(main_stem):
            print(f"⚠️ Active Ableton window is Untitled: '{main_win}'.", file=sys.stderr)
            show_untitled_warning(main_win)
            sys.exit(2)

    als_path, is_untitled_or_template = get_active_project_path()

    # 2. Check if the project is a template, nonexistent, or named Untitled
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
        print(f"🎵 Exporting as '{target_name}'.")
        notify("goodvibrations HQ", f"Exporting: {target_name}...")

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
