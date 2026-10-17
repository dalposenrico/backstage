# goodvibrations HQ — Roadmap

The goal is to stay lean. Every feature below is evaluated against one question: **does this help me find and listen to a demo faster, without adding noise to the UI?**

---

## Tier 1 — Quick wins (zero new UI)

These are small code changes that make the existing experience meaningfully better.

| Feature | Why |
|---|---|
| **Remember playback position per project** | Resume exactly where you left off when you revisit a project |
| **⇧⌘↑ / ⇧⌘↓ to jump to next/prev project** | Navigate the whole library without touching the sidebar |
| **"Last played" timestamp** | Track when you actually listened, not just the file modification date |

## In progress — Menu-bar quick access

goodvibrations HQ now has a persistent Songs and Tools panel in the macOS menu bar. The first version plays recent song exports and opens user-selected apps, files, scripts, Keyboard Maestro files, and folders. Native macro triggers and producer utilities such as Dropbox/Ableton sync checks should be added only after the launcher workflow proves useful.

## In progress — [untitled] export handoff

Each audio export now carries a local [untitled] status in its track row. HQ passes the export path and project name to a dedicated Keyboard Maestro macro for the desktop-app handoff, while keeping confirmation explicit until the automation can reliably verify that [untitled] accepted and uploaded the version.

## Finish runway and Production Checklist

Projects now have a local six-stage finish runway—Spark, Structure, Full Track, Mix, Master, and Done—plus one concrete next move, a spark rating, and a maximum of seven focus slots. The inline Production Checklist adds editable, stage-aware essential checks, optional guidance, and saved reflection prompts without automatically grading or advancing a song. These signals should reward decisions and completed stages rather than raw time or backup count. Evaluate whether they improve real finishing behavior before adding streaks, points, or aggregate scores.

## In progress — Today focus

The Library sidebar can now become a calm Today workspace with project-linked daily actions and a circular Pomodoro. The timer has focus presets, breaks, completion sounds, and a detachable always-on-top window. A task-first weekly Focus Planner pairs an unscheduled list with an airy calendar grid: tasks drag onto days, scheduled cards drag between days, and changes write through to Apple Calendar. Event notes carry the project checklist, and the floating Pomodoro prepares itself when a session begins. Keep this intentionally small and validate whether it helps move one chosen song forward before adding deeper history.

## Implemented — Versions workspace

Versions is a quiet, manual workspace for frequency-coloured exports and references. Draggable point markers handle transitions, comments, and navigation; independently positioned and resizable sections handle notes, starred takes, looping, and the persistent assembly rail. Both can snap to the beat grid. Ableton locators seed markers on the newest export. Keep it pull-based and inventory-like: silent file discovery is useful, but prompts, recommendations, automatic grading, and DAW-style editing are out of character.

---

## Tier 2 — Single element, high payoff

These add one small thing to the UI that earns its place.

| Feature | UI impact | Value |
|---|---|---|
| **Star / favourite projects** | A ⭐ on hover, persisted. Optional "Favourites" filter at the top of the sidebar | Send your best demos without hunting through folders |
| **Per-project quick note** | Right-click → Notes, tiny popover. No new screen | "Send to label", "needs bass rewrite", etc — without switching to Notes.app |
| **Track total duration** | One more `Text()` in the project row | See at a glance how long a session is |
| **Batch export / copy tracks** | Select multiple → copy to folder. One toolbar button | Hand off a selection to a collaborator |

---

## Tier 3 — Bigger, plan before building

These are genuinely useful but need a careful design pass before touching code.

| Feature | What to think through |
|---|---|
| **Mini player mode** | A tiny always-on-top window (just the player bar, ~400×60 px). Useful when working in another app. Needs its own compact layout. |

---

## Deliberately out of scope

Things that would make goodvibrations HQ worse, not better:

- **Public ratings / comment system** — private spark ratings and project notes are enough
- **Cloud sync of the music library** — Finder / iCloud already handles that
- **Equaliser or effects** — you have a DAW for that
- **Playlist queue** — if mini player + next/prev project is good, you don't need this
- **Social / sharing features** — out of character for a local-first tool

---

*Last updated: September 2026*
# [untitled] automation

- [x] Show local [untitled] handoff status in the track list and menu bar.
- [x] Add a separate destination checklist with a default song project and optional collection projects.
- [ ] Validate automatic project creation and uploads against a disposable test project before enabling live uploads.
