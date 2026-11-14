#!/usr/bin/env python3
"""
Ableton Live Collections Editor Tool
goodvibrations HQ — Producer Toolkit

Manage and batch-edit Ableton Live's 7 Collections (Browser Color Tags).
Allows moving, swapping, copying, removing, and inspecting collection tags
(e.g., changing all Yellow items to Red).

Features:
- Auto-detects active Ableton Live database & custom collection names from Library.cfg
- Bitmask-accurate modification of Ableton's 7 collection colors:
    1: Red (mask 2)
    2: Orange (mask 4)
    3: Yellow (mask 8)
    4: Green (mask 16)
    5: Blue (mask 32)
    6: Purple (mask 64)
    7: Gray (mask 128)
- Accepts color names ('yellow', 'red'), numbers (1-7), or custom Ableton labels ('INSPO BOX')
- Automatic timestamped database backups before any write operation
- Safe restore functionality
- Live process detection to avoid concurrency conflicts with running Ableton Live
- Dry-run / preview mode
- Breakdown by item type (samples, audio effect racks, plugins, folders, etc.)
"""

from __future__ import annotations

import argparse
import datetime
import glob
import os
import shutil
import sqlite3
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ANSI color codes for readable terminal output
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[38;5;203m"
ORANGE = "\033[38;5;208m"
YELLOW = "\033[38;5;220m"
GREEN = "\033[38;5;114m"
BLUE = "\033[38;5;75m"
PURPLE = "\033[38;5;177m"
GRAY = "\033[38;5;246m"
CYAN = "\033[38;5;44m"

COLOR_ANSI = {
    1: RED,
    2: ORANGE,
    3: YELLOW,
    4: GREEN,
    5: BLUE,
    6: PURPLE,
    7: GRAY,
}

COLOR_DEFAULTS = {
    1: ("Red", 1 << 1),       # 2
    2: ("Orange", 1 << 2),    # 4
    3: ("Yellow", 1 << 3),    # 8
    4: ("Green", 1 << 4),     # 16
    5: ("Blue", 1 << 5),      # 32
    6: ("Purple", 1 << 6),    # 64
    7: ("Gray", 1 << 7),      # 128
}

# 4-character FourCC file_type codes common in Live database
FILE_TYPE_NAMES = {
    2002875949: "Sample (.wav)",
    1634297446: "Sample (.aiff)",
    1718378851: "Sample (.flac)",
    1818651748: "Sample (.mp3)",
    1718379634: "Folder",
    1886156135: "Plugin",
    1987277875: "VST Plugin",
    1633969965: "AU Audio FX",
    1633973805: "AU Synth",
    1634493229: "Audio Effect Rack (.adg)",
    1836069677: "MIDI Clip (.mid)",
    1633772333: "Live Set (.als)",
    1684434020: "Live Device",
}


def find_latest_ableton_db() -> Optional[Path]:
    """Find the most recently modified Live-files-*.db in Ableton's Application Support."""
    base_dir = Path.home() / "Library" / "Application Support" / "Ableton" / "Live Database"
    if not base_dir.exists():
        return None
    db_candidates = sorted(
        base_dir.glob("Live-files-*.db"),
        key=lambda p: p.stat().st_mtime,
        reverse=True
    )
    return db_candidates[0] if db_candidates else None


def find_latest_prefs_dir() -> Optional[Path]:
    """Find the most recently modified Ableton preferences directory."""
    base_dir = Path.home() / "Library" / "Preferences" / "Ableton"
    if not base_dir.exists():
        return None
    prefs_dirs = [d for d in base_dir.iterdir() if d.is_dir() and d.name.startswith("Live ")]
    prefs_dirs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return prefs_dirs[0] if prefs_dirs else None


def load_custom_labels(prefs_dir: Optional[Path]) -> Dict[int, str]:
    """Extract custom collection names (1-7) from Library.cfg."""
    labels: Dict[int, str] = {}
    if not prefs_dir:
        return labels
    cfg_file = prefs_dir / "Library.cfg"
    if not cfg_file.exists():
        return labels

    try:
        tree = ET.parse(cfg_file)
        root = tree.getroot()
        for elem in root.iter("LabelInfo"):
            uri = elem.attrib.get("Uri", "")
            if uri.startswith("color:colors="):
                try:
                    idx = int(uri.split("=")[1])
                    display_name = elem.attrib.get("DisplayName", "").strip()
                    if display_name:
                        labels[idx] = display_name
                except (ValueError, IndexError):
                    pass
    except Exception:
        pass
    return labels


def check_ableton_running() -> Optional[int]:
    """Check if Ableton Live is currently running and return PID if found."""
    try:
        out = subprocess.check_output(["pgrep", "-x", "Live"], text=True).strip()
        if out:
            pids = out.splitlines()
            return int(pids[0])
    except (subprocess.CalledProcessError, ValueError):
        pass

    # Fallback to broader check
    try:
        out = subprocess.check_output(["pgrep", "-il", "Live"], text=True).strip()
        for line in out.splitlines():
            parts = line.strip().split()
            if len(parts) >= 2 and parts[1] == "Live":
                return int(parts[0])
    except Exception:
        pass
    return None


class AbletonCollectionsDB:
    def __init__(self, db_path: Path, prefs_dir: Optional[Path] = None):
        self.db_path = db_path
        self.prefs_dir = prefs_dir or find_latest_prefs_dir()
        self.custom_labels = load_custom_labels(self.prefs_dir)

    def get_collection_info(self, idx: int) -> Tuple[str, str, int]:
        """Returns (default_color_name, custom_label, bitmask)."""
        color_name, mask = COLOR_DEFAULTS[idx]
        custom = self.custom_labels.get(idx, "")
        return color_name, custom, mask

    def resolve_color(self, name_or_num: str) -> int:
        """
        Resolves an input string (e.g. 'yellow', '3', 'INSPO BOX') to a collection index 1-7.
        Raises ValueError if unrecognized.
        """
        token = name_or_num.strip().lower()

        # Check numeric 1-7
        if token.isdigit():
            val = int(token)
            if 1 <= val <= 7:
                return val

        # Check standard color names
        alias_map = {
            "red": 1,
            "orange": 2,
            "yellow": 3,
            "green": 4,
            "blue": 5,
            "purple": 6,
            "gray": 7,
            "grey": 7,
        }
        if token in alias_map:
            return alias_map[token]

        # Check custom labels (case-insensitive substring or exact match)
        for idx, custom in self.custom_labels.items():
            if custom.lower() == token:
                return idx
        for idx, custom in self.custom_labels.items():
            if token in custom.lower():
                return idx

        raise ValueError(
            f"Unknown collection: '{name_or_num}'. Must be 1-7, color name (red, orange, yellow, green, blue, purple, gray), "
            f"or custom label ({', '.join(repr(v) for v in self.custom_labels.values() if v)})."
        )

    def get_connection(self, readonly: bool = True) -> sqlite3.Connection:
        if readonly:
            uri = f"file:{self.db_path}?mode=ro"
            return sqlite3.connect(uri, uri=True)
        else:
            return sqlite3.connect(str(self.db_path))

    def backup_database(self) -> Path:
        """Creates an atomic SQLite backup with timestamp into Backups/."""
        backup_dir = self.db_path.parent / "Backups"
        backup_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_name = f"{self.db_path.name}.{timestamp}.bak"
        backup_path = backup_dir / backup_name

        src_conn = self.get_connection(readonly=True)
        dst_conn = sqlite3.connect(str(backup_path))
        src_conn.backup(dst_conn)
        dst_conn.close()
        src_conn.close()

        return backup_path

    def list_backups(self) -> List[Tuple[Path, datetime.datetime, int]]:
        backup_dir = self.db_path.parent / "Backups"
        if not backup_dir.exists():
            return []
        pattern = f"{self.db_path.name}.*.bak"
        files = backup_dir.glob(pattern)
        res = []
        for f in files:
            stat = f.stat()
            dt = datetime.datetime.fromtimestamp(stat.st_mtime)
            res.append((f, dt, stat.st_size))
        res.sort(key=lambda x: x[1], reverse=True)
        return res

    def restore_backup(self, backup_file: Optional[Path] = None) -> Path:
        """Restores the database from a backup."""
        backups = self.list_backups()
        if not backups:
            raise FileNotFoundError("No backups found in Backups directory.")

        target_backup: Path
        if backup_file:
            target_backup = backup_file
            if not target_backup.exists():
                raise FileNotFoundError(f"Backup file not found: {target_backup}")
        else:
            target_backup = backups[0][0]

        # Copy target backup file over current db
        shutil.copyfile(str(target_backup), str(self.db_path))

        # Remove WAL/SHM if present to force clean reopen
        for ext in ["-wal", "-shm"]:
            sidecar = Path(str(self.db_path) + ext)
            if sidecar.exists():
                try:
                    sidecar.unlink()
                except Exception:
                    pass

        return target_backup

    def get_collection_counts(self) -> List[Dict]:
        """Returns collection stats for all 7 colors."""
        conn = self.get_connection(readonly=True)
        c = conn.cursor()
        stats = []

        for idx in range(1, 8):
            color_name, custom_label, mask = self.get_collection_info(idx)
            c.execute(f"SELECT count(*) FROM files WHERE (colors & {mask}) != 0")
            total = c.fetchone()[0]

            # Breakdown by category
            c.execute(f"""
                SELECT 
                    SUM(CASE WHEN file_type IN (2002875949, 1634297446, 1718378851, 1818651748) THEN 1 ELSE 0 END) as samples,
                    SUM(CASE WHEN device_type != 0 OR file_type IN (1886156135, 1987277875, 1633969965, 1633973805, 1684434020) THEN 1 ELSE 0 END) as plugins,
                    SUM(CASE WHEN file_type = 1718379634 THEN 1 ELSE 0 END) as folders,
                    SUM(CASE WHEN file_type = 1634493229 THEN 1 ELSE 0 END) as racks,
                    SUM(CASE WHEN file_type = 1836069677 THEN 1 ELSE 0 END) as midi,
                    SUM(CASE WHEN file_type = 1633772333 THEN 1 ELSE 0 END) as sets
                FROM files 
                WHERE (colors & {mask}) != 0
            """)
            row = c.fetchone()
            stats.append({
                "index": idx,
                "color": color_name,
                "label": custom_label,
                "mask": mask,
                "total": total,
                "samples": row[0] or 0,
                "plugins": row[1] or 0,
                "folders": row[2] or 0,
                "racks": row[3] or 0,
                "midi": row[4] or 0,
                "sets": row[5] or 0,
            })
        conn.close()
        return stats

    def reconstruct_path(self, cursor: sqlite3.Cursor, file_id: int) -> str:
        """Reconstruct full filesystem path for a file_id."""
        parts = []
        curr = file_id
        depth = 0
        while curr and depth < 30:
            cursor.execute("SELECT parent_id, name FROM files WHERE file_id = ?", (curr,))
            row = cursor.fetchone()
            if not row:
                break
            parent_id, name = row
            if name != "/":
                parts.append(name)
            curr = parent_id
            depth += 1
        return "/" + "/".join(reversed(parts))

    def inspect_collection(self, color_idx: int, limit: int = 50, filter_term: Optional[str] = None) -> List[Dict]:
        """Returns list of items in the specified collection."""
        _, _, mask = self.get_collection_info(color_idx)
        conn = self.get_connection(readonly=True)
        c = conn.cursor()

        query = f"SELECT file_id, name, colors, file_type, device_type FROM files WHERE (colors & {mask}) != 0"
        params = []
        if filter_term:
            query += " AND name LIKE ?"
            params.append(f"%{filter_term}%")
        query += f" ORDER BY name ASC LIMIT {limit}"

        c.execute(query, params)
        rows = c.fetchall()

        items = []
        for fid, name, colors, ftype, devtype in rows:
            path = self.reconstruct_path(c, fid)
            ftype_name = FILE_TYPE_NAMES.get(ftype, f"Type {ftype}")
            if devtype != 0:
                ftype_name = "Plugin / Device"
            items.append({
                "file_id": fid,
                "name": name,
                "colors": colors,
                "type": ftype_name,
                "path": path,
            })
        conn.close()
        return items

    def move_collection(
        self,
        from_idx: int,
        to_idx: int,
        filter_term: Optional[str] = None,
        dry_run: bool = False,
    ) -> Dict:
        """
        Move items from source collection to target collection.
        Clears source bit, sets target bit.
        """
        _, _, from_mask = self.get_collection_info(from_idx)
        _, _, to_mask = self.get_collection_info(to_idx)

        conn = self.get_connection(readonly=dry_run)
        c = conn.cursor()

        where_clause = f"(colors & {from_mask}) != 0"
        params = []
        if filter_term:
            where_clause += " AND name LIKE ?"
            params.append(f"%{filter_term}%")

        c.execute(f"SELECT count(*) FROM files WHERE {where_clause}", params)
        affected_count = c.fetchone()[0]

        # Preview sample items
        c.execute(f"SELECT file_id, name, colors FROM files WHERE {where_clause} LIMIT 10", params)
        samples = []
        for fid, name, col in c.fetchall():
            new_col = (col & ~from_mask) | to_mask
            samples.append((name, col, new_col))

        if not dry_run and affected_count > 0:
            c.execute(
                f"UPDATE files SET colors = (colors & ~{from_mask}) | {to_mask} WHERE {where_clause}",
                params
            )
            conn.commit()
            # Perform WAL checkpoint
            try:
                c.execute("PRAGMA wal_checkpoint(TRUNCATE);")
            except Exception:
                pass

        conn.close()
        return {
            "affected_count": affected_count,
            "samples": samples,
            "dry_run": dry_run,
        }

    def swap_collections(
        self,
        idx_a: int,
        idx_b: int,
        dry_run: bool = False,
    ) -> Dict:
        """Swap two collections across all items."""
        _, _, mask_a = self.get_collection_info(idx_a)
        _, _, mask_b = self.get_collection_info(idx_b)

        conn = self.get_connection(readonly=dry_run)
        c = conn.cursor()

        # Count affected
        c.execute(f"SELECT count(*) FROM files WHERE ((colors & {mask_a}) != 0) != ((colors & {mask_b}) != 0)")
        affected_count = c.fetchone()[0]

        c.execute(f"SELECT count(*) FROM files WHERE (colors & {mask_a}) != 0")
        count_a = c.fetchone()[0]
        c.execute(f"SELECT count(*) FROM files WHERE (colors & {mask_b}) != 0")
        count_b = c.fetchone()[0]

        if not dry_run and affected_count > 0:
            # Case 1: has A, not B -> clear A, set B
            # Case 2: has B, not A -> clear B, set A
            # Case 3: has both or neither -> unchanged
            c.execute(f"""
                UPDATE files 
                SET colors = CASE 
                    WHEN (colors & {mask_a}) != 0 AND (colors & {mask_b}) = 0 THEN (colors & ~{mask_a}) | {mask_b}
                    WHEN (colors & {mask_b}) != 0 AND (colors & {mask_a}) = 0 THEN (colors & ~{mask_b}) | {mask_a}
                    ELSE colors
                END
                WHERE ((colors & {mask_a}) != 0) != ((colors & {mask_b}) != 0)
            """)
            conn.commit()
            try:
                c.execute("PRAGMA wal_checkpoint(TRUNCATE);")
            except Exception:
                pass

        conn.close()
        return {
            "affected_count": affected_count,
            "count_a_before": count_a,
            "count_b_before": count_b,
            "dry_run": dry_run,
        }

    def copy_collection(
        self,
        from_idx: int,
        to_idx: int,
        dry_run: bool = False,
    ) -> Dict:
        """Add target collection to all items that have source collection (without removing source)."""
        _, _, from_mask = self.get_collection_info(from_idx)
        _, _, to_mask = self.get_collection_info(to_idx)

        conn = self.get_connection(readonly=dry_run)
        c = conn.cursor()

        # Items having source but missing target
        where_clause = f"(colors & {from_mask}) != 0 AND (colors & {to_mask}) = 0"
        c.execute(f"SELECT count(*) FROM files WHERE {where_clause}")
        affected_count = c.fetchone()[0]

        if not dry_run and affected_count > 0:
            c.execute(f"UPDATE files SET colors = (colors | {to_mask}) WHERE {where_clause}")
            conn.commit()
            try:
                c.execute("PRAGMA wal_checkpoint(TRUNCATE);")
            except Exception:
                pass

        conn.close()
        return {
            "affected_count": affected_count,
            "dry_run": dry_run,
        }

    def remove_collection(
        self,
        idx: int,
        filter_term: Optional[str] = None,
        dry_run: bool = False,
    ) -> Dict:
        """Remove collection tag from all items."""
        _, _, mask = self.get_collection_info(idx)
        conn = self.get_connection(readonly=dry_run)
        c = conn.cursor()

        where_clause = f"(colors & {mask}) != 0"
        params = []
        if filter_term:
            where_clause += " AND name LIKE ?"
            params.append(f"%{filter_term}%")

        c.execute(f"SELECT count(*) FROM files WHERE {where_clause}", params)
        affected_count = c.fetchone()[0]

        if not dry_run and affected_count > 0:
            c.execute(f"UPDATE files SET colors = (colors & ~{mask}) WHERE {where_clause}", params)
            conn.commit()
            try:
                c.execute("PRAGMA wal_checkpoint(TRUNCATE);")
            except Exception:
                pass

        conn.close()
        return {
            "affected_count": affected_count,
            "dry_run": dry_run,
        }


# ==============================================================================
# CLI Handlers & Display
# ==============================================================================

def cmd_list(db: AbletonCollectionsDB, args: argparse.Namespace):
    stats = db.get_collection_counts()
    live_pid = check_ableton_running()

    print(f"\n{BOLD}Ableton Live Collections Overview{RESET}")
    print(f"{DIM}Database:{RESET} {db.db_path}")
    if live_pid:
        print(f"{DIM}Live Status:{RESET} {YELLOW}● Running (PID {live_pid}){RESET}")
    else:
        print(f"{DIM}Live Status:{RESET} {GREEN}● Closed{RESET}")

    print("─" * 86)
    print(f"{BOLD}{'#':<3} {'Color':<8} {'Custom Label':<26} {'Total':>6} {'Samples':>9} {'Plugins':>9} {'Folders':>8} {'Racks':>6}{RESET}")
    print("─" * 86)

    total_all = 0
    for s in stats:
        idx = s["index"]
        c_code = COLOR_ANSI.get(idx, "")
        color_str = f"{c_code}{s['color']:<8}{RESET}"
        label_str = s['label'] if s['label'] else f"{DIM}(Default){RESET}"
        if len(label_str) > 25:
            label_str = label_str[:23] + ".."
        total_all += s["total"]

        total_fmt = f"{c_code}{s['total']:>6}{RESET}" if s['total'] > 0 else f"{DIM}{'0':>6}{RESET}"
        samples_fmt = f"{s['samples']:>9}" if s['samples'] > 0 else f"{DIM}{'0':>9}{RESET}"
        plugins_fmt = f"{s['plugins']:>9}" if s['plugins'] > 0 else f"{DIM}{'0':>9}{RESET}"
        folders_fmt = f"{s['folders']:>8}" if s['folders'] > 0 else f"{DIM}{'0':>8}{RESET}"
        racks_fmt = f"{s['racks']:>6}" if s['racks'] > 0 else f"{DIM}{'0':>6}{RESET}"

        print(f"{idx:<3} {color_str} {label_str:<26} {total_fmt} {samples_fmt} {plugins_fmt} {folders_fmt} {racks_fmt}")

    print("─" * 86)
    print(f"{DIM}Tip: Run '{Path(sys.argv[0]).name} move --from yellow --to red' to reassign items.{RESET}\n")


def cmd_show(db: AbletonCollectionsDB, args: argparse.Namespace):
    idx = db.resolve_color(args.color)
    color_name, custom_label, _ = db.get_collection_info(idx)
    c_code = COLOR_ANSI.get(idx, "")
    label_desc = f" ({custom_label})" if custom_label else ""

    items = db.inspect_collection(idx, limit=args.limit, filter_term=args.filter)

    print(f"\n{BOLD}Collection {idx}: {c_code}{color_name}{label_desc}{RESET}")
    print(f"{DIM}Showing up to {args.limit} items{f' matching \"{args.filter}\"' if args.filter else ''}:{RESET}")
    print("─" * 80)

    if not items:
        print(f"{DIM}No items found.{RESET}")
    else:
        for it in items:
            print(f"• {BOLD}{it['name']}{RESET}  {DIM}[{it['type']}]{RESET}")
            print(f"  {DIM}{it['path']}{RESET}")
    print("─" * 80 + "\n")


def check_live_write_guard(force: bool):
    live_pid = check_ableton_running()
    if live_pid and not force:
        print(f"\n{RED}{BOLD}⚠️  Warning: Ableton Live is currently running (PID {live_pid})!{RESET}")
        print("Ableton holds browser tags and database transactions in memory.")
        print("Modifying the database while Live is open can cause conflicts, database locks,")
        print("or Live may overwrite your changes when saving or closing.")
        print(f"\n{BOLD}Recommendation:{RESET} Please quit Ableton Live first, then re-run this command.")
        print(f"If you must proceed anyway, add {CYAN}--force{RESET} to override this safeguard.\n")
        sys.exit(1)


def cmd_move(db: AbletonCollectionsDB, args: argparse.Namespace):
    from_idx = db.resolve_color(args.source)
    to_idx = db.resolve_color(args.target)

    from_color, from_label, _ = db.get_collection_info(from_idx)
    to_color, to_label, _ = db.get_collection_info(to_idx)
    c_from = COLOR_ANSI.get(from_idx, "")
    c_to = COLOR_ANSI.get(to_idx, "")

    from_desc = f"{c_from}{from_color}{f' ({from_label})' if from_label else ''}{RESET}"
    to_desc = f"{c_to}{to_color}{f' ({to_label})' if to_label else ''}{RESET}"

    if from_idx == to_idx:
        print(f"{RED}Source and target collection are the same ({from_color}). Nothing to do.{RESET}")
        return

    dry_run = args.dry_run

    if not dry_run:
        check_live_write_guard(args.force)
        # Automatic backup before modification
        backup_path = db.backup_database()
        print(f"{GREEN}✓ Safety backup created:{RESET} {backup_path.name}")

    res = db.move_collection(from_idx, to_idx, filter_term=args.filter, dry_run=dry_run)
    count = res["affected_count"]

    mode_prefix = f"{YELLOW}[DRY RUN - PREVIEW ONLY]{RESET} " if dry_run else ""
    print(f"\n{mode_prefix}{BOLD}Moving Collection Items:{RESET}")
    print(f"  From: {from_desc}")
    print(f"  To:   {to_desc}")
    if args.filter:
        print(f"  Filter: '{args.filter}'")
    print(f"  Affected items: {BOLD}{count}{RESET}")

    if res["samples"]:
        print(f"\n{DIM}Sample affected items:{RESET}")
        for name, old_c, new_c in res["samples"][:8]:
            print(f"  • {name} {DIM}(mask: {old_c} → {new_c}){RESET}")

    if dry_run:
        print(f"\n{CYAN}To apply this change for real, re-run without --dry-run (ensure Ableton Live is closed).{RESET}\n")
    else:
        print(f"\n{GREEN}{BOLD}✓ Successfully moved {count} items from {from_color} to {to_color}!{RESET}\n")


def cmd_swap(db: AbletonCollectionsDB, args: argparse.Namespace):
    idx_a = db.resolve_color(args.color_a)
    idx_b = db.resolve_color(args.color_b)

    if idx_a == idx_b:
        print(f"{RED}Both collections are the same. Nothing to swap.{RESET}")
        return

    name_a, label_a, _ = db.get_collection_info(idx_a)
    name_b, label_b, _ = db.get_collection_info(idx_b)
    c_a = COLOR_ANSI.get(idx_a, "")
    c_b = COLOR_ANSI.get(idx_b, "")

    desc_a = f"{c_a}{name_a}{f' ({label_a})' if label_a else ''}{RESET}"
    desc_b = f"{c_b}{name_b}{f' ({label_b})' if label_b else ''}{RESET}"

    dry_run = args.dry_run
    if not dry_run:
        check_live_write_guard(args.force)
        backup_path = db.backup_database()
        print(f"{GREEN}✓ Safety backup created:{RESET} {backup_path.name}")

    res = db.swap_collections(idx_a, idx_b, dry_run=dry_run)
    mode_prefix = f"{YELLOW}[DRY RUN]{RESET} " if dry_run else ""

    print(f"\n{mode_prefix}{BOLD}Swapping Collections:{RESET} {desc_a} ⟷ {desc_b}")
    print(f"  Items in {name_a}: {res['count_a_before']}")
    print(f"  Items in {name_b}: {res['count_b_before']}")
    print(f"  Total items updated: {BOLD}{res['affected_count']}{RESET}\n")


def cmd_copy(db: AbletonCollectionsDB, args: argparse.Namespace):
    from_idx = db.resolve_color(args.source)
    to_idx = db.resolve_color(args.target)

    from_color, _, _ = db.get_collection_info(from_idx)
    to_color, _, _ = db.get_collection_info(to_idx)

    dry_run = args.dry_run
    if not dry_run:
        check_live_write_guard(args.force)
        backup_path = db.backup_database()
        print(f"{GREEN}✓ Safety backup created:{RESET} {backup_path.name}")

    res = db.copy_collection(from_idx, to_idx, dry_run=dry_run)
    mode_prefix = f"{YELLOW}[DRY RUN]{RESET} " if dry_run else ""
    print(f"\n{mode_prefix}{BOLD}Copying Collection Tags:{RESET} {from_color} → {to_color}")
    print(f"  New items tagged: {BOLD}{res['affected_count']}{RESET}\n")


def cmd_remove(db: AbletonCollectionsDB, args: argparse.Namespace):
    idx = db.resolve_color(args.color)
    color_name, custom_label, _ = db.get_collection_info(idx)
    c_code = COLOR_ANSI.get(idx, "")
    desc = f"{c_code}{color_name}{f' ({custom_label})' if custom_label else ''}{RESET}"

    dry_run = args.dry_run
    if not dry_run:
        check_live_write_guard(args.force)
        backup_path = db.backup_database()
        print(f"{GREEN}✓ Safety backup created:{RESET} {backup_path.name}")

    res = db.remove_collection(idx, filter_term=args.filter, dry_run=dry_run)
    mode_prefix = f"{YELLOW}[DRY RUN]{RESET} " if dry_run else ""
    print(f"\n{mode_prefix}{BOLD}Removing Collection Tag:{RESET} {desc}")
    print(f"  Untagged items: {BOLD}{res['affected_count']}{RESET}\n")


def cmd_backups(db: AbletonCollectionsDB, args: argparse.Namespace):
    backups = db.list_backups()
    print(f"\n{BOLD}Available Backups for {db.db_path.name}:{RESET}")
    print("─" * 70)
    if not backups:
        print(f"{DIM}No backups found.{RESET}\n")
        return
    for path, dt, size in backups:
        size_mb = size / (1024 * 1024)
        print(f"• {path.name:<45} {dt.strftime('%Y-%m-%d %H:%M:%S')}  {size_mb:>6.1f} MB")
    print("─" * 70 + "\n")


def cmd_restore(db: AbletonCollectionsDB, args: argparse.Namespace):
    check_live_write_guard(args.force)
    target_backup = Path(args.file) if args.file else None
    restored = db.restore_backup(target_backup)
    print(f"\n{GREEN}{BOLD}✓ Database successfully restored from:{RESET} {restored.name}\n")


# ==============================================================================
# Main Parser
# ==============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Ableton Live Collections Editor — Inspect and batch-edit Ableton's 7 Browser Collections.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s list
  %(prog)s show yellow
  %(prog)s move --from yellow --to red --dry-run
  %(prog)s move --from yellow --to red
  %(prog)s move --from "inspo box" --to "current"
  %(prog)s swap yellow red
  %(prog)s copy --from yellow --to green
  %(prog)s remove yellow
  %(prog)s backups
  %(prog)s restore
        """
    )
    parser.add_argument("--db", type=Path, help="Explicit path to Ableton Live-files-*.db database file")
    parser.add_argument("--force", action="store_true", help="Bypass Ableton Live running safety check")

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # list
    p_list = subparsers.add_parser("list", help="List all 7 collections, labels, and item counts")

    # show / inspect
    p_show = subparsers.add_parser("show", help="Inspect items in a specific collection")
    p_show.add_argument("color", help="Collection number (1-7), color name, or custom label")
    p_show.add_argument("--limit", type=int, default=30, help="Max items to display (default: 30)")
    p_show.add_argument("--filter", type=str, help="Filter items by name substring")

    # move
    p_move = subparsers.add_parser("move", help="Move items from one collection to another (e.g. yellow -> red)")
    p_move.add_argument("--from", dest="source", required=True, help="Source collection (color name, 1-7, or label)")
    p_move.add_argument("--to", dest="target", required=True, help="Target collection (color name, 1-7, or label)")
    p_move.add_argument("--filter", type=str, help="Optional filter by item name substring")
    p_move.add_argument("--dry-run", action="store_true", help="Preview changes without modifying database")

    # swap
    p_swap = subparsers.add_parser("swap", help="Swap items between two collections")
    p_swap.add_argument("color_a", help="First collection")
    p_swap.add_argument("color_b", help="Second collection")
    p_swap.add_argument("--dry-run", action="store_true", help="Preview swap without modifying database")

    # copy
    p_copy = subparsers.add_parser("copy", help="Add target collection tag to items having source tag")
    p_copy.add_argument("--from", dest="source", required=True, help="Source collection")
    p_copy.add_argument("--to", dest="target", required=True, help="Target collection")
    p_copy.add_argument("--dry-run", action="store_true", help="Preview without modifying database")

    # remove
    p_remove = subparsers.add_parser("remove", help="Remove a collection tag from items")
    p_remove.add_argument("color", help="Collection to remove")
    p_remove.add_argument("--filter", type=str, help="Optional filter by item name substring")
    p_remove.add_argument("--dry-run", action="store_true", help="Preview without modifying database")

    # backups
    p_backups = subparsers.add_parser("backups", help="List available database backups")

    # restore
    p_restore = subparsers.add_parser("restore", help="Restore database from a backup")
    p_restore.add_argument("--file", type=Path, help="Specific backup file path to restore (defaults to latest)")

    args = parser.parse_args()

    # Determine database path
    db_path = args.db or find_latest_ableton_db()
    if not db_path or not db_path.exists():
        print(f"{RED}Error: Could not locate Ableton Live database.{RESET}")
        print("Please specify the path with --db /path/to/Live-files-XXXXX.db")
        sys.exit(1)

    db = AbletonCollectionsDB(db_path)

    cmd = args.command or "list"
    if cmd == "list":
        cmd_list(db, args)
    elif cmd == "show":
        cmd_show(db, args)
    elif cmd == "move":
        cmd_move(db, args)
    elif cmd == "swap":
        cmd_swap(db, args)
    elif cmd == "copy":
        cmd_copy(db, args)
    elif cmd == "remove":
        cmd_remove(db, args)
    elif cmd == "backups":
        cmd_backups(db, args)
    elif cmd == "restore":
        cmd_restore(db, args)


if __name__ == "__main__":
    main()
