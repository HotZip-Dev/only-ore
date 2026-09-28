# OnlyOres

**For World of Warcraft: Forever** · by HotZip Addons

OnlyOres remembers every ore node you mine and puts it on your map, so you can build your own mining routes and know when a spot was last picked clean.

## Features

- **Automatic recording.** Mine a node and its spot is saved. No setup and no import.
- **World map pins.** Every saved spot shows the ore's icon. Hover for the ore type, how long ago you last mined it, and how many times you've been there.
- **Minimap pins.**
  - Nearby spots show as a colored ring. When the vein is up, the *Find Minerals* dot shows inside the ring.
  - Spots out of range stick to the minimap's edge with their distance in yards, like party member arrows.
- **Shared spawn points.** When the same spot rolls different ores (Tin/Silver, Iron/Gold), OnlyOres keeps them on one pin and lists every ore seen there.
- **Multi-tap aware.** Forever veins take several hits. Repeated taps on the same vein count as one visit.
- **Waypoints.** Left-click a world map pin to set a waypoint.

## Commands

| Command | What it does |
|---|---|
| `/onlyores` | Show how many spots are saved |
| `/onlyores show` · `hide` · `toggle` | Show/hide all pins |
| `/onlyores minimap` | Show/hide minimap pins only |
| `/onlyores ignore <node name>` | Stop recording a node type and remove its pins (no name = list ignored) |
| `/onlyores unignore <node name>` | Record a node type again |
| `/onlyores clear` | Delete every saved spot (asks for confirmation) |
| `/onlyores debug` · `status` · `log clear` | Troubleshooting tools |

**Shift + right-click** a world map pin to forget that one spot.

## Notes

- Only nodes **you** mine are recorded; OnlyOres does not scan or share data.
- Data is saved per account in `WTF\Account\<account>\SavedVariables\OnlyOres.lua`.

## License

MIT © HotZip Addons · [hotzip.dev](https://hotzip.dev)
