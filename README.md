# goodvibrations HQ

A fast, minimal macOS app for browsing and playing your music demo exports.

Built for producers who keep their Ableton/Logic/DAW exports in a folder tree and want to quickly listen back, compare versions, and stay organised — without leaving the desktop.

goodvibrations HQ is evolving into a personal, local-first producer toolkit: a calm home base for finding projects, hearing the latest versions, and deciding what to work on next. The existing browser/player remains the foundation rather than becoming a generic project-management app.

---

## Install

1. Download the latest **goodvibrations-HQ.zip** from [Releases](../../releases/latest)
2. Unzip → drag **goodvibrations HQ.app** to `/Applications`
3. First launch: right-click → **Open** to clear the macOS security prompt (ad-hoc signed)

**Requires macOS 14 Sonoma or later.**

---

## Features

- **Folder tree browser** — mirrors your music folder exactly; expand/collapse with one click
- **Instant search** — filters all projects as you type
- **Smart sorting** — by recently edited, date added, or alphabetically (persisted between sessions)
- **Playback controls** — play/pause, next/prev track, keyboard shortcuts
- **Menu-bar quick access** — search songs, hear the latest export, and launch your own producer tools
- **Production Checklist** — phase-aware production, mixing, mastering, and finishing checks that stay visible on each project and can be customized locally
- **Finder colour tags** — automatically shows the tags you've already set in Finder
- **Reveal in Finder** — hover any project to open it straight from the app
- **Full state persistence** — reopens with the same project selected, same folders open, same sort order
- **Automatic update notifications** — a small banner appears in the sidebar when a new release is available
- **Click `[goodvibrations HQ]` to open Settings**

---

## Building from source

Requires Xcode command-line tools and Swift 5.9+.

```bash
git clone https://github.com/dalposenrico/backstage.git
cd backstage
swift build
```

To produce a distributable `.app`:

```bash
./build-app.sh
```

This builds a release binary, assembles `goodvibrations HQ.app`, and ad-hoc signs it.

To rebuild your personal copy, replace the version in `/Applications`, and reopen it in one step:

```bash
./install-local.sh
```

Turn on **Settings → Startup → Launch goodvibrations HQ at Login** to keep its Quick Access menu available after restarting your Mac.

For toolchain setup, verification steps, and current widget notes, see [DEVELOPMENT.md](DEVELOPMENT.md). AI coding assistants should start with [AGENTS.md](AGENTS.md).

---

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Play / Pause | `Space` |
| Next track | `⌘ →` |
| Previous track | `⌘ ←` |
| Open music folder | `⌘ O` |
| Refresh library | `⌘ R` |
| Settings | `⌘ ,` or click `[goodvibrations HQ]` |

---

## Releasing a new version

```bash
# 1. Bump version in Sources/demos/Info.plist
# 2. Commit and tag
git add -A && git commit -m "v1.1"
git tag v1.1
git push && git push --tags
```

GitHub Actions builds the app and publishes it to Releases automatically.

---

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned features.

---

## License

MIT
