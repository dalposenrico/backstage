# Backstage — Roadmap

The goal is to stay lean. Every feature below is evaluated against one question: **does this help me find and listen to a demo faster, without adding noise to the UI?**

---

## Tier 1 — Quick wins (zero new UI)

These are small code changes that make the existing experience meaningfully better.

| Feature | Why |
|---|---|
| **Remember playback position per project** | Resume exactly where you left off when you revisit a project |
| **⇧⌘↑ / ⇧⌘↓ to jump to next/prev project** | Navigate the whole library without touching the sidebar |
| **"Last played" timestamp** | Track when you actually listened, not just the file modification date |

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
| **Waveform preview** | Replace flat track rows with rendered waveforms (AVFoundation). Beautiful and useful but non-trivial — should be opt-in via Settings toggle. |

---

## Deliberately out of scope

Things that would make Backstage worse, not better:

- **Ratings / comment system** — use a Quick Note instead
- **Cloud sync of the music library** — Finder / iCloud already handles that
- **Equaliser or effects** — you have a DAW for that
- **Playlist queue** — if mini player + next/prev project is good, you don't need this
- **Social / sharing features** — out of character for a local-first tool

---

*Last updated: March 2026*
