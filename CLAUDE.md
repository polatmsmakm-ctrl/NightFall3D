# NightFall — project notes for whoever continues the work

Asymmetric horror game (1 killer vs up to 6 survivors, Dead-by-Daylight style) for iPhone.
Owner: Rashid (Arabic UI, plays with friends, installs the IPA with Sideloadly).

## Stack
- **Godot 4.5**, Mobile renderer, everything built in GDScript at runtime (no hand-made scenes; `scenes/main.tscn` only attaches `scripts/main.gd`).
- **Server**: Node + `ws` in `server/` (deployed on Render, root dir `server`, `npm start`). Rooms, friends presence, position relay, and the **authoritative match rules**.
- **CI**: `.github/workflows/build-ipa.yml` exports the Xcode project on a macOS runner and publishes an unsigned `Nightfall.ipa` to the `latest` release on every push to `main` (≈5 min, macOS minutes are billed ×10 on a private repo).

## Files
- `scripts/main.gd` — the game scene: local player (survivor third person / killer first person), touch HUD, remote players, audio, minimap, quick signals.
- `scripts/world.gd` (`NightWorld`) — procedural maps (`forest`, `village`, `fareej`): terrain, wall + gates, buildings/houses, the market, props, generators, hooks, lockers, pallets, hatches. `configure(map, seed)` decides the layout; `build()` creates nodes over several frames.
- `scripts/rules.gd` (`Rules`) — match rules used in trial (offline) mode. **`server/rules.js` is the same logic for online play — change both together.**
- `scripts/net.gd` (autoload `Net`) — WebSocket client, username, friends list, XP, total escapes and kills (all in `user://profile.cfg`), plus `level_progress()` for the XP bar.
- `scripts/graphics.gd` (autoload `Gfx`) — graphics settings menu, FPS modes, adaptive quality governor.
- `scripts/menu.gd` (`GameMenu`) — menus: name, main, friends, lobby, character select, trial mode; the player card and the swipe area.
- `scripts/lobby.gd` (`NFLobby`) — the start-screen camp (fire, props, cast). `preview(char, label, dir)` stands a character in front of the fire, `focus(on)` moves the camera in on them, `set_cast(players, me)` seats the real room around the fire with name tags (empty list brings back the shipped cast).
- `scripts/ui_theme.gd` (`NFUI`) — the horror look: one shared `Theme` (dark, dry-blood borders), `dress(button, icon)` (styles + scratches + icon + click sound), `bar()`, `safe_insets()`, `CHAR_COL` (each character's signature colour).
- `scripts/icons.gd` (`NFIcons`) — every icon is drawn with `draw_*` calls, no image assets: `NFIcons.draw(ci, "hand", center, size, col)` and `portrait()` for the team bar.
- `scripts/controls.gd` (`NFControls`) — where the touch buttons are and how big, per role, in `user://controls.cfg`. Positions are a fraction of the safe area, radii are px of the 1280x720 design viewport; `DEF` is the shipped layout. `scripts/controls_edit.gd` (`NFControlsEdit`) is the drag-and-resize editor (menu → الاسم والسيرفر, or the in-game settings panel).
- `scripts/loading.gd` (`NFLoading`) — the map-building screen: map name, a painted preview of that map, a random Arabic tip, progress from `world.build_step / NightWorld.BUILD_STEPS`.
- `scripts/results.gd` (`NFResults`) — end of round: everyone on a dark stage (escaped standing on `idle`, dead lying on `dying`), names and points under each one (`unproject_position`), the XP bar filling itself. The camera carries its own `environment`, and the stage sits 600 m above the map.
- `scripts/character_rig.gd` — loads a character GLB and retargets the Mixamo animation GLBs (`assets/anims`) onto it in place.
- `assets/chars` — the owner's 5 characters (SF3D meshes rigged to the Mixamo skeleton). `assets/sfx` — the owner's sounds (mp3) plus synthesized ones (wav).
- `tools/*.gd|tscn` — headless tests (not exported).

## Protocol (JSON over WebSocket)
`hello`, `friends`, `create`, `join`, `leave`, `set`, `invite`, `start`, `lobby`, `layout` (object positions from clients), `st` (position/anim/flashlight, relayed), `ev` (player input → server; server → everyone as `{t:"ev", n:"", d:event|snapshot}`).
`sig` (quick signal: `{t:"sig", k:0..2, p:[x,z]}` → the server relays `{t:"sig", n, k, p}` **to the sender's own side only**, so a survivor signal never reaches the killer).
Inputs (`d.k`): rep, skill, escape, hit, pickup, hook, rescue, struggle, heal, locker, search, pallet, break, power. Snapshot key `gs`.

## Testing without a device
```
godot --headless --path . --import            # after adding class_name scripts or assets
godot --headless --path . res://tools/smoke.tscn   # offline survivor + killer flow
godot --headless --path . res://tools/new.tscn     # fareej, hatch, flashlight, market blackout
NF_URL=ws://127.0.0.1:8099 godot --headless --path . res://tools/online.tscn   # needs server + a bot
```
Screenshots of every screen (menu, character select, lobby, controls editor, loading, both HUDs, results):
```
NF_SHOTS=/tmp/shots LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --rendering-driver opengl3 \
  --resolution 1564x720 --path . res://tools/shot.tscn      # software GL: ~15 min
```
1564x720 is the iPhone Pro Max landscape aspect in UI units (the viewport is 720 tall, `canvas_items` + `expand`).

## Recent behaviour worth knowing
- Hook escape is a mash: each `struggle` adds `MASH_STEP` to `esc`, which decays by `MASH_DECAY`/s; only on the first hook. Hooked survivors hang still and bleed.
- All sounds are the owner's mp3s (`assets/sfx`); the synthesized wavs were removed at his request, so skill checks, pallets, hatch and flashlight are silent until he supplies files. `MALE` in `main.gd` picks male pain vs female scream/oof voices.
- `world.set_blood_moon(true)` (sky shader `blood` uniform + moonlight/ambient/fog tween) fires when the gates get power.
- Fareej house at `NightWorld.DIWAN` is «ديوان راشد الشمري» (`_build_diwan`): fake wall-wash quads (`_sconce`/`_beam`, additive) plus a handful of shadowless real lights — keep it under the Mobile renderer's 8 omni + 8 spot per mesh. Palms use `shaders/palm.gdshader` (alpha-cut feather fronds).

- Moon fall: when the gates get power `doom` (snapshot `dm`) counts down `DOOM_TIME` = 120 s in both rules files; at 0 everyone still inside dies. Client: `world.set_moon_near`, `doom.mp3`, camera shake, flash, results 3.5 s after impact.
- Characters `survivor2/5/6/7` come from the owner's untextured Meshy sculpts (0.8–2.2 M tris): painted by body zones, decimated to 26k tris with baked colour+normal maps, rigged like the others. Blender's JPEGs inside the GLB must be re-encoded with Pillow or Godot fails to load them.

## The interface (rebuilt)
- **Buttons**: everything goes through `NFUI.dress()` — dark scratched plate, dry-blood edge, a drawn icon, and `NFUI.click()`, which plays `assets/sfx/ui_click.mp3` or `click.mp3` **only if the owner drops one in**; there is no file yet, so menu clicks are silent on purpose (nothing is ever synthesized).
- **Character select**: menu page `chars`. The chosen character stands at `NFLobby.STAND` in front of the fire, the camera eases from `CAM_IDLE` to `CAM_CHAR`, and a swipe over the right side of the screen (or ‹ ›) steps the carousel; the new one slides in from the side it came from. Online it still goes through `{t:"set", char:…}` — `want_char` holds the preview until the room list agrees; in trial mode it sets `off_char` and the killer is in the list too.
- **Player card** (top corner, `GameMenu._draw_card`): name, level, XP bar, total escapes and kills.
- **HUD buttons**: icon + small Arabic label, context icons from `NFControls.CTX_ICON`; the rings for battery / power cooldown / swing cooldown are unchanged.
- **Team bar** (`main._draw_team`): one portrait per survivor along the top — character colour, state ring, state glyph, hook countdown ring and seconds, a pip per hook survived, a gold ring around me. The killer sees it as well; **it never shows positions**, and the killer's minimap still has no player dots.
- **Moon countdown** (`main._draw_moon`): a red ring filling around a crescent over `DOOM_TIME`, beating in the last 30 s, with the clock under it.
- **Quick signals**: the `sig` button opens three messages (تعال هني / القاتل هني / قاعد أصلّح). They draw as an arrow on a ring around the middle of the screen pointing at the sender, with their name and the distance, for `SIG_LIFE` seconds. Online they go through the new `sig` message, relayed to the sender's own side only; in trial mode they only show locally.
- **Control layout**: `NFControls` + `NFControlsEdit`. Drag any button, resize the selected one with the slider, "إرجاع الأصلي" restores the shipped layout. Saved per role in `user://controls.cfg`; the editor is in the menu settings page and in the in-game settings panel (`Gfx.menu_open` stays true while it is open, so the round ignores touches).
- **Loading screen**: `NFLoading` while `world.build()` runs, with a drawn preview per map and a random tip from `NFLoading.TIPS`.
- **Results**: `NFResults`. Only the animations already in `assets/anims` are used — escaped players stand in `idle` (there is no cheer clip; drop one in and it can be used), dead players lie on the last frame of `dying`.

## Known gaps
- Models other than the characters are boxes/cylinders built in code; textures are procedural noise.
- No baked lighting (needs the editor on a GPU machine).
- Player positions are client-reported (server only checks distances for interactions).
- Friends list, XP, escapes and kills live on the phone; usernames are not reserved.
- No UI click sound until the owner supplies `assets/sfx/ui_click.mp3`.
- Team-bar portraits are drawn avatars in each character's colour, not renders of the models.
