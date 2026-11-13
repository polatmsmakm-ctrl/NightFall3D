# NightFall — project notes for whoever continues the work

Asymmetric horror game (1 killer vs up to 6 survivors, Dead-by-Daylight style) for iPhone.
Owner: Rashid (Arabic UI, plays with friends, installs the IPA with Sideloadly).

## Stack
- **Godot 4.5**, Mobile renderer, everything built in GDScript at runtime (no hand-made scenes; `scenes/main.tscn` only attaches `scripts/main.gd`).
- **Server**: Node + `ws` in `server/` (deployed on Render, root dir `server`, `npm start`). Rooms, friends presence, position relay, and the **authoritative match rules**.
- **CI**: `.github/workflows/build-ipa.yml` exports the Xcode project on a macOS runner and publishes an unsigned `Nightfall.ipa` to the `latest` release on every push to `main` (≈5 min, macOS minutes are billed ×10 on a private repo).

## Files
- `scripts/main.gd` — the game scene: start-screen campfire, local player (survivor third person / killer first person), touch UI, remote players, audio, minimap, results.
- `scripts/world.gd` (`NightWorld`) — procedural maps (`forest`, `village`, `fareej`): terrain, wall + gates, buildings/houses, the market, props, generators, hooks, lockers, pallets, hatches. `configure(map, seed)` decides the layout; `build()` creates nodes over several frames.
- `scripts/rules.gd` (`Rules`) — match rules used in trial (offline) mode. **`server/rules.js` is the same logic for online play — change both together.**
- `scripts/net.gd` (autoload `Net`) — WebSocket client, username, friends list, XP (stored in `user://profile.cfg`).
- `scripts/graphics.gd` (autoload `Gfx`) — graphics settings menu, FPS modes, adaptive quality governor.
- `scripts/menu.gd` (`GameMenu`) — menus: name, main, friends, lobby, trial mode.
- `scripts/character_rig.gd` — loads a character GLB and retargets the Mixamo animation GLBs (`assets/anims`) onto it in place.
- `assets/chars` — the owner's 5 characters (SF3D meshes rigged to the Mixamo skeleton). `assets/sfx` — the owner's sounds (mp3) plus synthesized ones (wav).
- `tools/*.gd|tscn` — headless tests (not exported).

## Protocol (JSON over WebSocket)
`hello`, `friends`, `create`, `join`, `leave`, `set`, `invite`, `start`, `lobby`, `layout` (object positions from clients), `st` (position/anim/flashlight, relayed), `ev` (player input → server; server → everyone as `{t:"ev", n:"", d:event|snapshot}`).
Inputs (`d.k`): rep, skill, escape, hit, pickup, hook, rescue, struggle, heal, locker, search, pallet, break, power. Snapshot key `gs`.

## Testing without a device
```
godot --headless --path . --import            # after adding class_name scripts or assets
godot --headless --path . res://tools/smoke.tscn   # offline survivor + killer flow
godot --headless --path . res://tools/new.tscn     # fareej, hatch, flashlight, market blackout
NF_URL=ws://127.0.0.1:8099 godot --headless --path . res://tools/online.tscn   # needs server + a bot
```
Screenshots: run a scene under `xvfb-run` (software GL, slow) and save the viewport texture.

## Recent behaviour worth knowing
- Hook escape is a mash: each `struggle` adds `MASH_STEP` to `esc`, which decays by `MASH_DECAY`/s; only on the first hook. Hooked survivors hang still and bleed.
- All sounds are the owner's mp3s (`assets/sfx`); the synthesized wavs were removed at his request, so skill checks, pallets, hatch and flashlight are silent until he supplies files. `MALE` in `main.gd` picks male pain vs female scream/oof voices.
- `world.set_blood_moon(true)` (sky shader `blood` uniform + moonlight/ambient/fog tween) fires when the gates get power.
- Fareej house at `NightWorld.DIWAN` is «ديوان راشد الشمري» (`_build_diwan`): fake wall-wash quads (`_sconce`/`_beam`, additive) plus a handful of shadowless real lights — keep it under the Mobile renderer's 8 omni + 8 spot per mesh. Palms use `shaders/palm.gdshader` (alpha-cut feather fronds).

- Moon fall: when the gates get power `doom` (snapshot `dm`) counts down `DOOM_TIME` = 120 s in both rules files; at 0 everyone still inside dies. Client: `world.set_moon_near`, `doom.mp3`, camera shake, flash, results 3.5 s after impact.
- Characters `survivor2/5/6/7` come from the owner's untextured Meshy sculpts (0.8–2.2 M tris): painted by body zones, decimated to 26k tris with baked colour+normal maps, rigged like the others. Blender's JPEGs inside the GLB must be re-encoded with Pillow or Godot fails to load them.

## Known gaps
- Models other than the characters are boxes/cylinders built in code; textures are procedural noise.
- No baked lighting (needs the editor on a GPU machine).
- Player positions are client-reported (server only checks distances for interactions).
- Friends list and XP live on the phone; usernames are not reserved.
