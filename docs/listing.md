# OnlyOres: store listing fields

Copy-paste source for the CurseForge and Wago project pages, field by field in
form order. Keep in sync when features change. (`docs/` is excluded from the
addon zip via `.pkgmeta`.)

Status: CurseForge project ID `1719476` (re-created 2026-09-30; old `1716887` deleted) · Wago project ID `vNAWgQKo` (unchanged) (also add both to `OnlyOres.toc`)

---

## Shared

| Field | Value |
|---|---|
| Name | `OnlyOres` |
| Logo | `docs/logo.png` (square PNG, ≥400×400, original art) + `docs/logo-256.png` (256×256 copy for sites that require it) |
| License | GPL v3 |
| Source code | *(blank while the repo is private; if made public: `https://github.com/HotZip-Dev/only-ore`)* |
| Website | *(blank until https://hotzip.dev is live; it had no working HTTPS site as of 2026-09-28)* |

**Summary** (CurseForge limit 256 chars; this is 124):
```
Mine a node and OnlyOres remembers it: pins on your world map and minimap, a last-mined timer, and distance to nearby veins.
```

---

## CurseForge (authors.curseforge.com → Create A Project)

| Field | Value |
|---|---|
| Project name | `OnlyOres` |
| Logo | `docs/logo.png` |
| Summary | *(Shared summary)* |
| Class | Addons |
| Main category | Map & Minimap |
| Additional categories | Professions (or closest gathering/tradeskill option) |
| Allow Comments | ✅ on (the description invites bug reports in comments) |
| Unlisted project | ⬜ off for launch (on = hidden, link-only) |
| Social Links | *(none yet; add website/Discord when they exist)* |
| Description | Editor → **Markdown**, paste the Description below |
| License | GPL v3 |

## Wago (addons.wago.io → developer dashboard → create project)

| Field | Value |
|---|---|
| Addon Website | *(blank until hotzip.dev is live)* |
| Addon License | `https://www.gnu.org/licenses/gpl-3.0.html` |
| Addon Wiki | *(blank)* |
| Addon Source | *(blank while repo is private)* |
| Support link | *(blank for now; later the CurseForge project URL, or GitHub Issues if the repo goes public)* |
| Discord link | *(blank; no HotZip Discord yet)* |
| Description | same Markdown as below |

---

## Description (Markdown)

Paste everything between the lines.

---

**Made for World of Warcraft: Forever.**

OnlyOres remembers every ore node you mine and puts it on your map, so you can build your own mining routes and see how long ago each spot was last picked clean.

## Features

- **Automatic recording.** Mine a node and its spot is saved. No setup, no imports.
- **World map pins.** Each saved spot shows the ore's icon. Hover to see the ore type, how long ago you last mined it, and how many times you've been there.
- **Minimap rings.** Nearby spots show as a colored ring. When the vein is up, the *Find Minerals* dot appears inside the ring, so you can tell at a glance whether it's there.
- **Distance to the next vein.** Spots out of minimap range stick to the minimap's edge with their distance in yards, like party member arrows.
- **Shared spawn points.** When the same spot rolls different ores (Tin/Silver, Iron/Gold), they stay on one pin with every ore you've seen there.
- **Built for Forever's multi-tap veins.** Hitting the same vein several times counts as one visit.
- **Waypoints.** Left-click a world map pin to set a waypoint to it.

## Commands

- `/onlyores`: how many spots you've saved
- `/onlyores show` / `hide` / `toggle`: show or hide all pins
- `/onlyores minimap`: show or hide minimap pins only
- `/onlyores ignore <node name>`: stop recording a node type and remove its pins
- `/onlyores unignore <node name>`: start recording it again
- `/onlyores clear`: delete every saved spot (asks for confirmation)

**Shift + right-click** a world map pin to forget that one spot.

## Good to know

- Only nodes **you** mine are recorded. OnlyOres doesn't scan the world or share data with anyone.
- Your data is saved per account, so all your characters build the same map.

Found a bug or have an idea? Leave a comment!

---
