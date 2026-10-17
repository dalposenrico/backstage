-- goodvibrations HQ — Ableton Live Auto-Version & Export
-- Triggers the Python automation engine

set scriptPath to (POSIX path of (path to me))
set AppleScript's text item delimiters to "/"
set pathItems to text items of scriptPath
set dirItems to items 1 through ((count of pathItems) - 1) of pathItems
set currentDir to dirItems as text

set pyScript to currentDir & "/ableton_version_export.py"
do shell script "python3 " & quoted form of pyScript
