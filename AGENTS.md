# goodvibrations HQ — Project Guide

This file is the durable starting context for any AI coding assistant working in this repository.

## Product

goodvibrations HQ is Enrico's personal, local-first producer toolkit for macOS. It should make it faster to find, audition, understand, and move music projects forward without forcing a producer to reorganize their existing folders.

The current app is an Ableton-focused project browser and demo player. The longer-term direction is a calm home base for music projects: project status, favourites, notes, versions, and a small set of genuinely useful producer utilities.

## Product principles

- Preserve the producer's existing folder structure; do not invent a second library to maintain.
- Prefer local files and on-device metadata. No account or cloud dependency unless explicitly requested.
- Optimize for “open the right project and continue working” rather than generic project management.
- Add one strong workflow at a time. Avoid turning goodvibrations HQ into a DAW, social network, or crowded dashboard.
- Keep the interface fast, quiet, and recognizably native to macOS.

## Current stack

- Swift 5.9 package, SwiftUI, macOS 14+
- AVFoundation for audio playback
- AppKit where macOS-specific behavior is needed
- No third-party dependencies
- Hand-assembled `.app` bundle via `build-app.sh`
- GitHub Actions release on `v*` tags

## Repository map

- `Sources/demos/demosApp.swift` — app entry point, scenes, menus, keyboard commands
- `Sources/demos/AppStore.swift` — main application state and persistence coordination
- `Sources/demos/ProjectScanner.swift` — maps folders and Ableton `.als` files into projects
- `Sources/demos/AudioPlayer.swift` — local audio playback
- `Sources/demos/Models.swift` — folder, project, track, and version models
- `Sources/demos/Views/` — SwiftUI interface
- `Sources/BackstageWidget/` — work-in-progress favourites widget
- `Sources/demos/Info.plist` — app identity and version
- `build-app.sh` — release bundle assembly and ad-hoc signing
- `ROADMAP.md` — product backlog; update it when priorities materially change
- `DEVELOPMENT.md` — local setup, checks, and known environment constraints

## Working rules

1. Read `git status` before editing. The repository may contain active work that must be preserved.
2. Before implementing a feature, explain the user workflow in one or two sentences and identify where its data will live.
3. Keep filesystem scanning off the main actor. Keep UI-observed state changes on the main actor.
4. Never modify, rename, move, or delete a user's music files unless the user explicitly requests that exact action.
5. Treat paths and project names as private local data. Do not add analytics or remote uploads by default.
6. Prefer small model/store types over adding more logic to the large view files.
7. Add focused tests when extracting non-UI logic. At minimum, run the checks in `DEVELOPMENT.md`.
8. Automatically commit and push verified, working changes with clear, descriptive commit messages.

## Current work in progress

There are uncommitted favourites, menu-bar, and WidgetKit changes as of August 2026. Inspect the current diff before touching them. The widget's data-sharing and packaging approach still needs validation in a full Xcode environment.

## Near-term product sequence

1. Stabilize the current browser/player and finish favourites safely.
2. Add lightweight project metadata: status and a short “next action” note.
3. Add a project overview that surfaces recent, stalled, favourite, and nearly finished work.
4. Only then evaluate additional producer tools based on repeated real use.
