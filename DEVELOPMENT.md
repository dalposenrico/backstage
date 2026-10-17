# Developing goodvibrations HQ

## Requirements

- macOS 14 Sonoma or newer
- Full Xcode installation recommended
- Swift 5.9 or newer

Use a matching Xcode toolchain and SDK. Check the active setup with:

```bash
xcode-select -p
xcrun swift --version
xcodebuild -version
```

If `xcodebuild` says the active directory is only Command Line Tools, install/open Xcode and select it in Xcode's **Settings → Locations → Command Line Tools**. The equivalent terminal command is:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Build and run

For a quick compile check:

```bash
swift build
```

For an installable local app bundle:

```bash
./build-app.sh
```

The script creates `goodvibrations HQ.app` in the repository root and ad-hoc signs it. It currently opens Finder when finished.

For the personal development copy installed in `/Applications`, use `./install-local.sh`. It builds without opening Finder, installs `/Applications/goodvibrations HQ.app`, moves the previous `Backstage.app` to the Trash, and relaunches the renamed app. macOS may request an administrator password when `/Applications` is not writable.

## Verification checklist

After a user-facing change:

1. Run `swift build`.
2. Build `goodvibrations HQ.app` with `./build-app.sh` when packaging, signing, Info.plist, widgets, or app lifecycle changed.
3. Launch with a small disposable Ableton-style folder tree.
4. Check folder selection, refresh, search, sorting, project selection, playback, seeking, next/previous, Finder opening, and state restoration.
5. Confirm the app never changes source music files.

There is no automated test target yet. The first useful tests should cover `TrackGrouper` filename rules and `ProjectScanner` behavior using temporary folders.

## Local data

- The app’s current bundle identifier is `com.enricodalpos.goodvibrationshq`. On first launch after the September 2026 identity change, missing preferences are copied once from the legacy `com.enricodalpos.demos` defaults domain so the library folder, appearance, and focus settings survive. Local JSON files continue using the legacy `Backstage` Application Support folder for compatibility.

- Root folder path, expanded folders, selection, sort, and appearance use `UserDefaults`.
- Favourites currently use the legacy `~/Library/Application Support/Backstage/favorites.json` path so existing data survives the product rename.
- Menu-bar tool launchers use the legacy `~/Library/Application Support/Backstage/tools.json` path. The file stores file references or Keyboard Maestro macro names/UIDs only; goodvibrations HQ does not copy or alter the selected tools.
- [untitled] handoff status uses `~/Library/Application Support/Backstage/untitled-sync.json`. It stores local file paths, file size/date fingerprints, and status only; audio remains in place. Destination choices are stored in `untitled-destinations.json`. Before invoking the `Automate Untitled Uploads` Keyboard Maestro macro, HQ writes the selected local handoff to `untitled-handoff.json` in the same directory.
- [untitled] destination names and per-project selections use `~/Library/Application Support/Backstage/untitled-destinations.json`. The matching song project is always selected as a new-version destination; optional collection projects are added as new tracks.
- Production Checklist template edits use `~/Library/Application Support/Backstage/studio-workflow-template.json`. Per-project checks, short answers, and dismissed stage suggestions use `project-workflows.json`; both store text and project folder paths only.
- Sidebar collection colors are stored in `UserDefaults` under `collectionColors`. Assignments use folder paths and are inherited by nested folders and projects.
- Music files are read in place and are not copied into goodvibrations HQ.
- Spotify and Apple Music vibe-reference links are stored per project in `UserDefaults` under `projectStreamingReferences`. Playback is handed to the official provider app; HQ does not store credentials or account state.
- Export checkpoints reuse the local project notes and progress stores. Keyboard Maestro can open `goodvibrations://checkpoint?path=...` with a URL-encoded `.als` file or project-folder path; HQ matches it to the containing scanned project and never modifies that path.
- The Versions workspace stores point markers, section names and notes, per-version positions/ranges, best-take choices, and the manual assembly rail in `~/Library/Application Support/Backstage/comparison-markers.json`. Each item uses fractions of its own audio file, so arrangements with different timings do not pretend to align. Imported Ableton locators become editable point markers on the newest export and `.als` files remain read-only.
- Today focus tasks are stored in `~/Library/Application Support/Backstage/daily-focus.json`; each task contains its text, creation/completion dates, and the linked project folder path. Pomodoro duration, sound, running end time, pin preference, and today’s session count use `UserDefaults`. The timer never modifies project or audio files.
- Scheduled focus sessions are real Apple Calendar events created through EventKit in the writable calendar chosen by the user. Their event URL contains the linked local project path and their notes contain the project’s open checklist. `UserDefaults` stores only the preferred calendar identifier and short-lived IDs of events already used to wake the Pomodoro. Automatic wake-up requires goodvibrations HQ to be running.

## Known setup issue (August 2026)

On the current machine, `/Library/Developer/CommandLineTools` is selected and its Swift compiler does not match the installed macOS SDK patch version. `swift build` therefore fails before compiling the package. Selecting a matching full Xcode installation is the recommended fix.

## Widget work in progress

The WidgetKit target is currently represented as a Swift Package executable and manually placed inside an `.appex`. Before shipping it:

- verify that macOS discovers and launches the extension;
- use an App Group container for favourites shared by the host app and widget;
- verify that opening Finder from an App Intent is allowed and behaves correctly;
- sign the extension and containing app in the correct order;
- update the release workflow runner/toolchain if needed.

For dependable distribution, moving the app and widget to an Xcode project is likely cleaner than continuing to hand-assemble the extension bundle.
