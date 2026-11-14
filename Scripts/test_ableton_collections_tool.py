#!/usr/bin/env python3
"""
Unit tests for Scripts/ableton_collections_tool.py
"""

import os
import sqlite3
import tempfile
import unittest
from pathlib import Path

from ableton_collections_tool import (
    AbletonCollectionsDB,
    COLOR_DEFAULTS,
)


class TestAbletonCollectionsTool(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "Live-files-test.db"

        # Create mock SQLite database matching Ableton structure
        conn = sqlite3.connect(str(self.db_path))
        c = conn.cursor()
        c.execute("""
            CREATE TABLE files (
                file_id INTEGER PRIMARY KEY AUTOINCREMENT,
                parent_id INTEGER,
                file_type INTEGER,
                subtype INTEGER DEFAULT 0,
                file_kind INTEGER DEFAULT 0,
                name TEXT,
                colors INTEGER DEFAULT 1,
                device_type INTEGER DEFAULT 0
            )
        """)

        # Insert test folder hierarchy
        # 1: /
        # 2: Users
        # 3: enrico
        # 4: Samples
        c.execute("INSERT INTO files (file_id, parent_id, name, colors, file_type) VALUES (1, 0, '/', 1, 1718379634)")
        c.execute("INSERT INTO files (file_id, parent_id, name, colors, file_type) VALUES (2, 1, 'Users', 1, 1718379634)")
        c.execute("INSERT INTO files (file_id, parent_id, name, colors, file_type) VALUES (3, 2, 'enrico', 1, 1718379634)")
        c.execute("INSERT INTO files (file_id, parent_id, name, colors, file_type) VALUES (4, 3, 'Samples', 1, 1718379634)")

        # Item 10: Yellow only (1 + 8 = 9)
        c.execute("INSERT INTO files (file_id, parent_id, name, colors, file_type) VALUES (10, 4, 'kick_yellow.wav', 9, 2002875949)")
        # Item 11: Yellow and Green (1 + 8 + 16 = 25)
        c.execute("INSERT INTO files (file_id, parent_id, name, colors, file_type) VALUES (11, 4, 'snare_yellow_green.wav', 25, 2002875949)")
        # Item 12: Red only (1 + 2 = 3)
        c.execute("INSERT INTO files (file_id, parent_id, name, colors, file_type) VALUES (12, 4, 'synth_red.wav', 3, 2002875949)")
        # Item 13: Untagged (1)
        c.execute("INSERT INTO files (file_id, parent_id, name, colors, file_type) VALUES (13, 4, 'loop_none.wav', 1, 2002875949)")

        conn.commit()
        conn.close()

        self.db = AbletonCollectionsDB(self.db_path)
        self.db.custom_labels = {
            1: "CURRENT",
            3: "INSPO BOX",
        }

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_resolve_color(self):
        # Index 1-7
        self.assertEqual(self.db.resolve_color("1"), 1)
        self.assertEqual(self.db.resolve_color("3"), 3)

        # Standard color names
        self.assertEqual(self.db.resolve_color("red"), 1)
        self.assertEqual(self.db.resolve_color("Yellow"), 3)
        self.assertEqual(self.db.resolve_color("purple"), 6)
        self.assertEqual(self.db.resolve_color("grey"), 7)

        # Custom labels
        self.assertEqual(self.db.resolve_color("current"), 1)
        self.assertEqual(self.db.resolve_color("inspo box"), 3)

        with self.assertRaises(ValueError):
            self.db.resolve_color("nonexistent")

    def test_reconstruct_path(self):
        conn = self.db.get_connection(readonly=True)
        c = conn.cursor()
        path = self.db.reconstruct_path(c, 10)
        conn.close()
        self.assertEqual(path, "/Users/enrico/Samples/kick_yellow.wav")

    def test_counts(self):
        stats = self.db.get_collection_counts()
        counts = {s["index"]: s["total"] for s in stats}
        self.assertEqual(counts[1], 1)  # Red: item 12
        self.assertEqual(counts[3], 2)  # Yellow: item 10, 11
        self.assertEqual(counts[4], 1)  # Green: item 11

    def test_move_collection(self):
        # Move Yellow (3) -> Red (1)
        res = self.db.move_collection(from_idx=3, to_idx=1, dry_run=False)
        self.assertEqual(res["affected_count"], 2)

        conn = self.db.get_connection(readonly=True)
        c = conn.cursor()

        # Item 10 was Yellow (9 -> 1 + 8) -> now should be Red (1 + 2 = 3)
        c.execute("SELECT colors FROM files WHERE file_id = 10")
        self.assertEqual(c.fetchone()[0], 3)

        # Item 11 was Yellow + Green (25 -> 1 + 8 + 16) -> now should be Red + Green (1 + 2 + 16 = 19)
        c.execute("SELECT colors FROM files WHERE file_id = 11")
        self.assertEqual(c.fetchone()[0], 19)

        # Item 12 was Red (3) -> remains Red (3)
        c.execute("SELECT colors FROM files WHERE file_id = 12")
        self.assertEqual(c.fetchone()[0], 3)

        # No items left in Yellow
        c.execute("SELECT count(*) FROM files WHERE (colors & 8) != 0")
        self.assertEqual(c.fetchone()[0], 0)

        # Red now has 3 items (10, 11, 12)
        c.execute("SELECT count(*) FROM files WHERE (colors & 2) != 0")
        self.assertEqual(c.fetchone()[0], 3)

        conn.close()

    def test_swap_collections(self):
        # Swap Yellow (3) and Red (1)
        res = self.db.swap_collections(idx_a=3, idx_b=1, dry_run=False)
        self.assertGreater(res["affected_count"], 0)

        conn = self.db.get_connection(readonly=True)
        c = conn.cursor()

        # Item 10 was Yellow (9) -> should now be Red (3)
        c.execute("SELECT colors FROM files WHERE file_id = 10")
        self.assertEqual(c.fetchone()[0], 3)

        # Item 12 was Red (3) -> should now be Yellow (9)
        c.execute("SELECT colors FROM files WHERE file_id = 12")
        self.assertEqual(c.fetchone()[0], 9)

        conn.close()

    def test_copy_collection(self):
        # Copy Yellow (3) -> Red (1) without removing Yellow
        res = self.db.copy_collection(from_idx=3, to_idx=1, dry_run=False)
        self.assertEqual(res["affected_count"], 2)

        conn = self.db.get_connection(readonly=True)
        c = conn.cursor()

        # Item 10 should now have both Red and Yellow: 1 | 2 | 8 = 11
        c.execute("SELECT colors FROM files WHERE file_id = 10")
        self.assertEqual(c.fetchone()[0], 11)

        conn.close()

    def test_remove_collection(self):
        # Remove Yellow (3)
        res = self.db.remove_collection(idx=3, dry_run=False)
        self.assertEqual(res["affected_count"], 2)

        conn = self.db.get_connection(readonly=True)
        c = conn.cursor()

        # Item 10 should be untagged (1)
        c.execute("SELECT colors FROM files WHERE file_id = 10")
        self.assertEqual(c.fetchone()[0], 1)

        # Item 11 was Yellow + Green (25) -> now Green only (17)
        c.execute("SELECT colors FROM files WHERE file_id = 11")
        self.assertEqual(c.fetchone()[0], 17)

        conn.close()

    def test_backup_and_restore(self):
        backup_path = self.db.backup_database()
        self.assertTrue(backup_path.exists())

        # Modify DB
        self.db.move_collection(from_idx=3, to_idx=1, dry_run=False)

        # Restore from backup
        self.db.restore_backup(backup_path)

        # Verify restored to original state (Item 10 is Yellow 9)
        conn = self.db.get_connection(readonly=True)
        c = conn.cursor()
        c.execute("SELECT colors FROM files WHERE file_id = 10")
        self.assertEqual(c.fetchone()[0], 9)
        conn.close()


if __name__ == "__main__":
    unittest.main()
