# NightFall — project notes for whoever continues the work

Asymmetric horror game (1 killer vs up to 6 survivors, Dead-by-Daylight style) for iPhone.
Owner: Rashid (Arabic UI, plays with friends, installs the IPA with Sideloadly).

## Stack
- **Godot 4.5**, **Forward+ renderer** (Metal on iOS; it was Mobile until the high-end pass), everything built in GDScript at runtime (no hand-made scenes; `scenes/main.tscn` only attaches `scripts/main.gd`).
- **Server**: Node + `ws` in `server/` (deployed on Render, root dir `server`, `npm start`). Rooms, friends presence, position relay, and the **authoritative match rules**.
- **CI**: `.github/workflows/build-ipa.yml` exports the Xcode project on a macOS runner and publishes an unsigned `Nightfall.ipa` to the `latest` release on every push to `main` (≈5 min, macOS minutes are billed ×10 on a private repo).

## Files
- `scripts/main.gd` — the game scene: local player (survivor third person / killer first person), touch HUD, remote players, audio, minimap, quick signals.
- `scripts/world.gd` (`NightWorld`) — procedural maps (`forest`, `village`, `fareej`, `rubkhali`, `garage`, `beach`): terrain, wall + gates, buildings/houses, the market, props, generators, hooks, lockers, pallets, hatches. `configure(map, seed, theme)` decides the layout; `build()` creates nodes over several frames.
- `scripts/rules.gd` (`Rules`) — match rules used in trial (offline) mode. **`server/rules.js` is the same logic for online play — change both together.**
- `scripts/net.gd` (autoload `Net`) — WebSocket client, username, friends list, XP, total escapes and kills (all in `user://profile.cfg`), plus `level_progress()` for the XP bar.
- `scripts/graphics.gd` (autoload `Gfx`) — the settings panel (sound + graphics), FPS modes, adaptive quality governor. `open_settings()` opens it from a menu button; the gear itself is always on screen.
- `scripts/audio.gd` (autoload `Aud`) — the audio buses and the three volumes. Two buses sit under Master: **Music** (ambient bed, chase track, campfire, doomsday) and **SFX** (footsteps, generators, gates, screams, heartbeat, breathing, rope, one-shots, other players' sounds, UI clicks). Every player sets `.bus` when it is created. `set_vol("master"|"music"|"sfx", 0..1)` applies live and saves `user://audio.cfg`.
- `scripts/haptics.gd` (`NFHaptics`) — every buzz of the phone. `pulse(kind)` / `pulse_scaled(kind, 0..1)` with a per-kind cooldown; `KINDS` holds the duration, strength and cooldown of each. One switch (`Aud.haptics`, "الاهتزاز" in settings) turns all of it off. It reaches the iPhone through `Input.vibrate_handheld`, so **none of it can be checked without the device** — on desktop the calls do nothing.
- `scripts/look_mod.gd` (`NFLookMod`) — a `SkeletonModifier3D` that turns a character's head/neck toward a world point *after* the animation has posed the skeleton. `CharacterRig.look(at, weight)` / `look_clear()`.
- `scripts/dev.gd` (autoload `Dev`) — hidden developer tools, off and invisible unless this phone has unlocked them; the unlock lives only in `user://dev.cfg` and is never sent anywhere.
- `scripts/menu.gd` (`GameMenu`) — menus: name, main, friends, lobby, character select, trial mode, the friends' board (`board`); the player card and the swipe area.
- `scripts/bot.gd` (`NFBot`) — the computer killer in trial mode (see «The extreme pass»).
- `scripts/lobby.gd` (`NFLobby`) — the start-screen camp (fire, props, cast). `preview(char, label, dir)` stands a character in front of the fire, `focus(on)` moves the camera in on them, `set_cast(players, me)` seats the real room around the fire with name tags (empty list brings back the shipped cast). `_time_of_day()` reads the clock on the phone and lights the camp for dawn / day / dusk / night (sky `day`+`warm`, moonlight, ambient, fog, `fire_mul`), with a 30% chance of mist; `NFLobby.force_hour` / `force_mist` override it for tests and screenshots.
- `scripts/ui_theme.gd` (`NFUI`) — the horror look: one shared `Theme` (dark, dry-blood borders), `dress(button, icon)` (styles + scratches + icon + click sound), `bar()`, `safe_insets()`, `CHAR_COL` (each character's signature colour).
- `scripts/icons.gd` (`NFIcons`) — every icon is drawn with `draw_*` calls, no image assets: `NFIcons.draw(ci, "hand", center, size, col)` and `portrait()` for the team bar.
- `scripts/controls.gd` (`NFControls`) — where the touch buttons are and how big, per role, in `user://controls.cfg`. Positions are a fraction of the safe area, radii are px of the 1280x720 design viewport; `DEF` is the shipped layout. `scripts/controls_edit.gd` (`NFControlsEdit`) is the drag-and-resize editor (menu → الاسم والسيرفر, or the in-game settings panel).
- `scripts/loading.gd` (`NFLoading`) — the map-building screen: map name, a painted preview of that map, a random Arabic tip, progress from `world.build_step / NightWorld.BUILD_STEPS`.
- `scripts/results.gd` (`NFResults`) — end of round: first the victory shot if anyone got out (`_build_victory`: the escaped survivors at a lit gate, the camera circling them for 5 s, «نجوا!» and their names; dead players are not in it), then everyone on a dark stage (escaped standing on `idle`, dead lying on `dying`), names and points under each one (`unproject_position`), the XP bar filling itself. `setup()` takes `victory` — the rows whose state is `escaped`, built in `main._show_results`. The camera carries its own `environment`, and the stage sits 600 m above the map.
- `assets/chars/<char>_hi.glb` — an optional close-up copy of a character at four or five times
  the triangles. `CharacterRig.setup(char, anims, close_up := true)` loads it, and only the two
  places where the camera is right in front of a character use it: the character select stand and
  the victory shot. The round itself always loads the small one.
- `scripts/character_rig.gd` — loads a character GLB and retargets the Mixamo animation GLBs (`assets/anims`) onto it in place. The three emotes (`wave`, `dance`, `clap`) have no GLB: `_emote_anim()` poses them on the same skeleton in code, and a real clip dropped into `assets/anims` takes over automatically. These characters' rest pose is a **T-pose in a Z-down skeleton space** (up is `-Z`, they face `+Y`, the right arm lies along `-X`), so `_emote_world()` writes rotations in that frame and `_emote_anim()` turns each one into a local bone rotation with `rest * (G⁻¹ · R · G)`. `tools/bones.tscn` prints the axes and where the hands end up — run it before touching the poses.
- `assets/maps/carpark.glb` — the only modelled map piece in the game: one 30 x 20 m car-park
  module (CC0, Innerscene Corp) split into named pieces (`slab aisle paint detail doors lift core
  wall_s north_block cols`) by `tools/split_glb.py`, which also shrinks the textures. Re-run that
  script if the model is ever replaced; the garage map picks the pieces per module.
- `assets/maps/beach.glb` — the lagoon diorama the beach map scatters (palm, wet-sand tile, shells,
  a creeper; 5 m across, 14k tris). It arrived with **KHR_mesh_quantization required**, which this
  Godot build refuses to load, so `tools/dequant_glb.py` expanded every packed attribute to float —
  run that on any model that fails to import with no error message.
- `assets/mapshots/<map>.png` — the 512x288 preview of each map shown on the picker, rendered by
  `tools/mapshot.tscn` (one scenic camera per map, HUD off, lit a stop and a half brighter so it
  reads on a small card). Re-run it after a map changes; a map with no picture still gets a button.
- `tools/rig_character.py` — **the way a new character gets into the game**. Meshy sculpts come out
  textured but with half a million triangles and no skeleton. The script (v2) puts the T-pose mesh
  in the cast's space (auto-turned by the toes; `--facing keep|turn` when high heels fool it),
  **fits the skeleton to the body** (armpit, arm centre line, fingertip, leg centres, torso depth —
  measured the same way on the donor and the sculpt) and rewrites the joints' *rest translations*
  so the bones are as long as this body's limbs (v1 only changed the bind matrices, which is what
  stretched «وردة الليل»'s forearms), welds the UV-seam doubles and decimates **by region** (head,
  hands and feet keep their own triangle budgets), weights **by body part** (arm chain, leg chain
  with a soft left/right seam, torso by height; everything past the wrist is the hand, everything
  under the ankle the foot and toes), smooths the weights on the welded surface so seams do not
  open, and pads the texture islands so seams do not show dark specks.
  `python3 tools/rig_character.py sculpt.glb assets/chars/survivorN.glb --faces 30000` and
  `... survivorN_hi.glb --faces 70000 --tex 2048`. Donor rig: `tools/rig/donor_mixamo22.glb`.
  Needs `pip install pymeshlab` + the system's `libopengl0`. `tools/shot14.tscn` renders a pose
  sheet (idle / run / crouch / repair / attack + hand and feet close-ups) to judge a rig.
  `survivor1` «الناجية», `survivor2` «الرحّال», `survivor3` «الشريف» and `survivor8` «وردة الليل» are
  all made this way, from the owner's textured sculpts; `MALE` in `main.gd` lists the men.
- `tools/rig_character.py --bake` (`tools/rig_bake.py` + `tools/simplify.cpp`) — **the second way
  in, with no pymeshlab**, for a sculpt whose own UV atlas cannot survive the collapse. It was
  written for the killer, «البركة القرمزية» (Crimson Benediction): 3.1 M triangles in 3,937 UV
  islands, almost all of them hair, so keeping the atlas would have pinned ~21k triangles to
  island corners. Instead it welds the sculpt, collapses it with its own quadric simplifier (the
  same four region budgets, an importance per vertex — face skin x7, dark hair x0.25 — no edge
  longer than 6 cm so limbs keep rings to bend at, and hair strands allowed to pinch shut),
  unwraps the result into a **new atlas** (charts by facing direction, packed as bitmaps; the face
  gets 2.1x the texels per metre, hair 0.32x) and **bakes** colour, metallic-roughness and normal
  from the closest point of the full sculpt. The normal map holds the sculpt's geometry in the
  small mesh's tangent space, and the GLB carries `TANGENT` so Godot shades with the frame the
  bake used. Needs numpy, scipy, opencv, pillow and g++; ~1.5 min for 30k, ~4 min for 70k/2048.
  Three switches came with her and work on both paths:
  `--arms SHOULDER,ELBOW,WRIST` (metres from the centre line; her hair hides the armpit and her
  claws run 7 cm past the fingertips, so the automatic arm fit put the elbow in the forearm),
  `--chest 0.12` (what stands further than that in front of the spine at chest height moves with
  `Spine2` as one piece — by height alone a full bust is split between two spine bones and
  stretches in the crouch), and, bake path only, a **hair mask** from the sculpt's colour: dark
  vertices above the hips and inside the shoulders take no arm weight, so a lowered arm does
  not drag the hair on the shoulder down with it. Her two files were made with
  `python3 tools/rig_character.py sculpt.glb assets/chars/killer.glb --faces 30000 --tex 1024 --facing keep --arms 0.235,0.50,0.745 --chest 0.12 --bake`
  and `... killer_hi.glb --faces 70000 --tex 2048 ...` (same switches).
- `assets/chars` — the owner's characters (SF3D meshes rigged to the Mixamo skeleton). `assets/sfx` — the owner's sounds (mp3) plus synthesized ones (wav).
- `tools/*.gd|tscn` — headless tests (not exported).

## Protocol (JSON over WebSocket)
`hello`, `friends`, `create`, `join`, `leave`, `set`, `invite`, `start`, `lobby`, `layout` (object positions from clients), `st` (position/anim/flashlight, relayed), `ev` (player input → server; server → everyone as `{t:"ev", n:"", d:event|snapshot}`).
`ev` input `door` (`{k:"door", i, on}` → the server checks you are next to it and sends `{k:"door", i, on, by}` to the room).
`emote` (`{t:"emote", k:0..2}` → the server sends `{t:"emote", n, k}` to the rest of the room; campfire only).
`sig` (quick signal: `{t:"sig", k:0..2, p:[x,z]}` → the server relays `{t:"sig", n, k, p}` **to the sender's own side only**, so a survivor signal never reaches the killer).
Inputs (`d.k`): rep, skill, escape, hit, pickup, hook, rescue, struggle, heal, locker, search, pallet, break, power, door, board, arrive, ram, trap, snap, disarm, spike, pop. Snapshot key `gs` (also `tp` traps, `sp` spikes; survivor rows carry `held` at 11 and `shield` at 12; `rd` rows `flat` at 5).
`stats` (`{t:"stats", s:{lv, xp, esc, kills, rounds}}`, also inside `hello`): the server keeps each player's numbers (memory + `server/stats.json`) and hands friends' rows out in `friends` (`stats: [...]`) and live as `{t:"fstats", s}`.
Snapshot also carries `dr` (door states), `ek`/`et`/`en` (the round's event, seconds left, the survivor the alarm gives away) and `ad` (the call to prayer: 0 not yet, 1 playing, 2 done). The clients send the doorway positions in `layout.d`, each gate's escape-car spot in `layout.c` and its road's end (the last gate) in `layout.e`; `layout.h` now holds the 9 map hooks plus 9 along each road (the server takes up to 48). Snapshot `rd` is one row per road: `[state, driver, riders, seconds left, why]`, and each survivor row carries the car they are in at index 10.

## Testing without a device
```
godot --headless --path . --import            # after adding class_name scripts or assets
godot --headless --path . res://tools/smoke.tscn   # offline survivor + killer flow
godot --headless --path . res://tools/new.tscn     # fareej, hatch, flashlight, market blackout
godot --headless --path . res://tools/ui.tscn      # buttons, signals, loading, results, character select
godot --headless --path . res://tools/map.tscn     # the desert map, both themes, emotes, the jumpscare
godot --headless --path . res://tools/bones.tscn   # where the emote poses put the hands
godot --headless --path . res://tools/dev.tscn     # audio buses, volumes, the hidden tools
godot --headless --path . res://tools/event.tscn   # the round's event, adhan, doors, blackout, fog, lights
godot --headless --path . res://tools/feel.tscn    # haptics switch, camera moves
godot --headless --path . res://tools/win.tscn      # group rescue, camp by time of day, victory screen
godot --headless --path . res://tools/garage.tscn   # the car park: modules, objectives, walking, blackout
godot --headless --path . res://tools/look.tscn     # ground shading, contact shadows, grade pass, drop-in clips/models
godot --headless --path . res://tools/beach.tscn    # the beach: sand, lagoon, palms, wading
godot --headless --path . res://tools/road.tscn     # the road chase: board, drive, ride, arrive, rammed, out of time, the moon
NF_SHOTS=/tmp/shots godot --headless --path . res://tools/mapshot.tscn  # the six map previews (needs a display)
node server/test.js                                # room code, join by code, theme, emote and signal relay
NF_URL=ws://127.0.0.1:8099 godot --headless --path . res://tools/online.tscn   # needs server + a bot
```
Screenshots — `tools/shot.tscn` for the interface, `tools/shot2.tscn` for the desert, the themes, the emotes
and the jumpscare, `tools/shot4.tscn` for the sound settings and the hidden tools, `tools/shot6.tscn` for the
doors, the blackout, the fog and the alarm, `tools/shot7.tscn` for the camp by time of day, the shared
unhook and the victory screen, `tools/shot8.tscn` for the car park, `tools/shot9.tscn` for the
daylight Empty Quarter, `tools/shot10.tscn` for the look pass before/after:
```
NF_SHOTS=/tmp/shots LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --rendering-driver opengl3 \
  --resolution 1564x720 --path . res://tools/shot.tscn      # software GL: ~15 min
```
1564x720 is the iPhone Pro Max landscape aspect in UI units (the viewport is 720 tall, `canvas_items` + `expand`).

## Recent behaviour worth knowing
- Hook escape is a mash: each `struggle` adds `MASH_STEP` to `esc`, which decays by `MASH_DECAY`/s; only on the first hook. Hooked survivors hang still and bleed.
- Unhooking is a **hold shared between survivors**: `rescue` is `{k:"rescue", n, on}`, `resc` fills at `hands / RESCUE_TIME` per second (2.0 s alone, 1.1 s with two, 0.7 s with three) and drains at half speed when everyone lets go. The snapshot row carries `resc` (8) and the number of hands (9), so each phone shows «%d يشيلونه سوا — أسرع!» on the bar, and the `rescued` event carries `hands`. **`tick()` returns an Array of events in both rules files** and `server.js` broadcasts them, because a rescue can finish inside a tick.
- All sounds are the owner's mp3s (`assets/sfx`); the synthesized wavs were removed at his request, so skill checks, pallets, hatch and flashlight are silent until he supplies files. `MALE` in `main.gd` picks male pain vs female scream/oof voices.
- `world.set_blood_moon(true)` (sky shader `blood` uniform + moonlight/ambient/fog tween) fires when the gates get power; on `rubkhali` it reddens the sunlight and the storm instead.
- `fog_base` is the density the map settled on after its weather and theme; `set_fog` (the heavy-fog event) and the desert's dust surge both scale that, never the raw `fog_density`.
- Fareej house at `NightWorld.DIWAN` is «ديوان راشد الشمري» (`_build_diwan`): fake wall-wash quads (`_sconce`/`_beam`, additive) plus a handful of shadowless real lights — keep it under the Mobile renderer's 8 omni + 8 spot per mesh. Palms use `shaders/palm.gdshader` (alpha-cut feather fronds).

- Moon fall: when the gates get power `doom` (snapshot `dm`) counts down `DOOM_TIME` = 120 s in both rules files; at 0 everyone still inside dies. Client: `world.set_moon_near`, `doom.mp3`, camera shake, flash, results 3.5 s after impact.
- Characters `survivor2/6` (and `5/7` before they were replaced) come from the owner's untextured Meshy sculpts (0.8–2.2 M tris): painted by body zones, decimated to 26k tris with baked colour+normal maps, rigged like the others. Blender's JPEGs inside the GLB must be re-encoded with Pillow or Godot fails to load them.

## The interface (rebuilt)
- **Buttons**: everything goes through `NFUI.dress()` — dark scratched plate, dry-blood edge, a drawn icon, and `NFUI.click()`, which plays `assets/sfx/ui_click.mp3` or `click.mp3` **only if the owner drops one in**; there is no file yet, so menu clicks are silent on purpose (nothing is ever synthesized).
- **Character select**: the stand is lit like a photographer would: a warm key in front and to one
  side, a cool fill opposite it, and a hard rim behind, all three coming up as the camera moves in
  (`NFLobby`: `key_light` / `fill_light` / `back_light`). Menu page `chars`. The chosen character stands at `NFLobby.STAND` in front of the fire, the camera eases from `CAM_IDLE` to `CAM_CHAR`, and a swipe over the right side of the screen (or ‹ ›) steps the carousel; the new one slides in from the side it came from. Online it still goes through `{t:"set", char:…}` — `want_char` holds the preview until the room list agrees; in trial mode it sets `off_char` and the killer is in the list too.
- **Player card** (top corner, `GameMenu._draw_card`): name, level, XP bar, total escapes and kills.
- **HUD buttons**: icon + small Arabic label, context icons from `NFControls.CTX_ICON`; the rings for battery / power cooldown / swing cooldown are unchanged.
- **Team bar** (`main._draw_team`): one portrait per survivor along the top — character colour, state ring, state glyph, hook countdown ring and seconds, a pip per hook survived, a gold ring around me. The killer sees it as well; **it never shows positions**, and the killer's minimap still has no player dots.
- **Moon countdown** (`main._draw_moon`): a red ring filling around a crescent (a sun on `rubkhali`) over `DOOM_TIME`, beating in the last 30 s, with the clock under it.
- **Quick signals**: the `sig` button opens three messages (تعال هني / القاتل هني / قاعد أصلّح). They draw as an arrow on a ring around the middle of the screen pointing at the sender, with their name and the distance, for `SIG_LIFE` seconds. Online they go through the new `sig` message, relayed to the sender's own side only; in trial mode they only show locally.
- **Control layout**: `NFControls` + `NFControlsEdit`. Drag any button, resize the selected one with the slider, "إرجاع الأصلي" restores the shipped layout. Saved per role in `user://controls.cfg`; the editor is in the menu settings page and in the in-game settings panel (`Gfx.menu_open` stays true while it is open, so the round ignores touches).
- **Map picker**: `GameMenu._map_card()` — each map is a card with its rendered preview from
  `assets/mapshots/` and its Arabic name, three to a row, in both the online lobby and trial mode.
- **Loading screen**: `NFLoading` while `world.build()` runs, with a drawn preview per map and a random tip from `NFLoading.TIPS`.
- **Campfire emotes**: `NFLobby.emote(name, k)` plays wave / dance / clap on the right character at the fire and goes
  back to idle after 3.4 s; the menu row sends `{t:"emote", k}` so everyone in the room sees it.
- **Jumpscare**: when the killer lifts you (`my_state` turns `carried`), `main._start_scare()` points a second camera
  at his face for 0.62 s with a red wash, then hands control back. It never freezes input the round needs.
- **Sound**: `الصوت` (master) with a `تفصيل` button that folds out `صوت الموسيقى` and `صوت اللعب`, in the settings
  panel — reachable from the main menu, the lobby and the in-game gear. 0-100%, live while dragging, saved.
- **Play again**: the results screen has a second button. Online the host sends `lobby`, which puts the whole room back
  in the same lobby; in trial mode `Net.replay` carries the settings across the scene reload.
- **Victory screen**: survivors who got out stand in the lit gate while the camera circles them for 5 s (`NFResults._build_victory`), with «نجوا!» and their names; the statistics stage and its buttons are hidden until it ends. Nobody escaped → it is skipped and the numbers come up at once. The pose uses the `dance` / `wave` emotes, because there is no victory clip in `assets/anims`.
- **Results**: `NFResults`. Only the animations already in `assets/anims` are used — escaped players stand in `idle` (there is no cheer clip; drop one in and it can be used), dead players lie on the last frame of `dying`.

## Maps
Every map keeps the same skeleton: perimeter wall, two gates each with a 600 m escape road (see «The road chase»), the market, 7 generators,
9 hooks, 10 lockers, 9 pallets, 5 hatches, all seeded from the host's seed so every client builds the same layout.
- `forest` — hills, pine forest, shacks.
- `village` — a grid of abandoned houses.
- `fareej` — a Kuwaiti neighbourhood: walled houses, streets, mosque, flag, the lit «ديوان راشد الشمري».
- `garage` «المواقف» — the car park under an apartment block, and the only map built from a
  model instead of code (`assets/maps/carpark.glb`, CC0). `_plan_garage` repeats the 30 x 20 m
  module in a 5 x 7 grid, scaled 1.4 (so the floor is 210 x 196 m with a 4.2 m slab overhead),
  and decides per module which pieces it gets: the stair core on the west edge and a few inside,
  and a cross wall every third module — that is what makes the bays join into one floor you can
  run around instead of 35 sealed boxes. **The model's `north_block` piece is never placed**: it is
  the model's own ramp to a next storey that does not exist (a slope running up into the slab,
  walled in, solid), and players could never climb it. The only ramp in the map is the real one
  to the roof. `_build_garage` draws each
  piece as one MultiMesh per row of modules (≈60 draw calls, and a row is small enough that the
  mobile renderer's 8 lights per object still land where they should), `_build_garage_shell`
  adds the box collision, the slab and the outside wall with its two openings toward the gates,
  `_build_garage_lights` hangs a fluorescent strip over every module (one in ten is dead, all of
  them die in the blackout; ambient 1.12, strips at 3.3 with a 23 m reach, fog 0.016) and `_build_garage_props` parks ~87 cars as three coloured MultiMeshes
  with one box collider each, plus the concrete crash barriers that are the only vault spots down
  there. No trees, grass, market, scatter or doors on this map; footsteps are always `indoor`, and
  the minimap draws the cores and cross walls instead of the market.
  **The roof**: the slab is walkable. A car ramp (`GAR_RAMP_X/Z`, about nine degrees, flush with
  the floor at the bottom and with the roof at the top) comes up through a hole left in one row of
  the slab, a parapet runs round the edge, and a bridge carries the **second gate — which is up on
  the roof at `GAR_ROOF` (4.7 m)** out to the perimeter. The **seventh generator** is up there too,
  in the open, with one hook beside it. A gate whose `y` is above the ground now gets a taller
  frame and a wall under its opening (`_build_objectives`), and `main._near` requires the two
  points to be within 3 m vertically, so you cannot work the roof generator from the floor below.
  **On the map** (`main._draw_roof_ramp` / `_roof_badge`): the ramp is a cyan strip with chevrons
  pointing up the slope and «السطح ↑» beside it on the big map; the roof gate, the roof generator
  and the roof hook each carry a cyan ▲; the legend has «▲ فوق السطح»; and while you stand on the
  roof the minimap rings your arrow and says «على السطح».
- `beach` «الشاطئ» — a lagoon beach: sand (`relief 1.1`), eight beach huts, the market set back
  from the water, and the sea along the **north** side. `_raw_h` drops the ground by up to 3.4 m
  north of `BEACH_SHORE` (42 m), the lagoon surface sits at `BEACH_WATER` (-0.55) as one
  transparent plane with a scrolling normal map, and a collision wall at `BEACH_SHORE + 9` lets
  you wade in knee-deep but not swim out. `_build_beach` scatters the model's pieces as one
  MultiMesh per sub-mesh (46 palms, 70 wet-sand patches, 24 shells = **25 draw calls**), plus a
  foam line along the shore. Objectives never land in the water (`_random_site` and `_free_spot`
  refuse anything past the shore).
- `rubkhali` «الربع الخالي» — **the only map that plays in daylight**: a sandstorm at noon with the
  sun in the sky instead of the moon. `shaders/sky.gdshader` has a `sun` uniform (0 everywhere else)
  that replaces the night gradient with ochre dust, kills the stars, turns the disc into a flat white
  sun with a wide halo and paints the clouds as sheets of sand; `_build_environment` gives it hard warm
  sunlight (2.4), bright sandy ambient (1.5), sand-coloured fog at 1.3x density and `fog_sky_affect 0.5`
  so the sun still burns through. The round's blackout event is a **surge of sand** there (fog x2.3,
  «عجاج ثقيل!») instead of the lights going out, and when the gates get power the whole storm turns
  blood red and **the sun** comes down — same `doom` countdown, with the sun icon in the HUD and
  «اهرب قبل لا تنزل الشمس!». The rest of the map (`_build_rubkhali`): long dunes (`relief = 3.0`, low-frequency noise),
  6 bedouin tents (`_build_tent`, dark woven cloth, open front, rug, cold fire pit, a locker inside) and 5 mud houses
  (`_build_mud_house`, palm beams through the walls). A dust storm: thick sand-coloured fog plus the `dust` particles
  turned into blowing grains, so you cannot see far. Cover is the point out here — `_build_desert_scatter` lays down
  7 Land Cruiser wrecks (`_wreck`, half buried, missing wheels), 11 ruined mud walls, 16 boulders, fences, camel thorn
  and palm clusters. `_build_animals` walks 9 horses and camels (`_animal_mesh`: one merged mesh each, one draw call,
  **no collision and no sound**) along seeded waypoint loops; `_step_animals` moves them. The wall is 12 m tall here
  so a dune crest never sees over it.

## Themes (normal / fog / snow / halloween)
Chosen by the host in the room (or in trial mode) and sent with `start`, so everyone builds the same weather.
**`fog`** «ضباب» is the host's second mood: fog density ×3.1, a low heavy layer, moonlight down to
0.75 and the colour drained — a night you can hide a killer in. The start-screen camp is **always
night** now (`NFLobby._time_of_day` no longer follows the phone clock) and it turns misty while the
room's weather is `fog`, so the menu already shows what the round will look like.
`NightWorld.configure(map, seed, theme)` applies it: terrain vertex colours, fog, ambient and moonlight, the grass
and foliage shader tints, and `_snow_cap()` slabs on every roof. Snow turns the falling-leaf particles into flakes and
`main._make_breath()` gives every character visible breath. Halloween adds `_pumpkin()` (carved, lit, flickering) at
every door and along the paths, and `_cobweb()` under the eaves and on the hooks. Counters `snow_caps`, `pumpkins`,
`webs`, `wrecks` exist so the headless test can see the dressing.

## Feel: camera and haptics
- **Camera** (`main._camera_feel`, run every physics step): `_shake(power)` adds a spring-damped tip/roll used
  for hits, the grab and the moon landing. Carried adds a slow sway and 0.8 m of pull-back. Hooked pulls the
  camera 3.4 m further out and, for the first 2.6 s (`hook_cam`), swings the look round to the front of the hook
  (a hooked character always faces +z) and tips up. Escaping runs `slowmo` for 1.1 s: `Engine.time_scale` dips to
  0.45 and the FOV opens to 84, then both snap back.
- **Haptics**: heartbeat ticks that follow `danger`, a strong hit when you are struck, a heavier one when he
  lifts you, a rising rumble as the moon comes down and a long one on impact, plus small ticks on hooks and
  escapes. All through `NFHaptics`, all behind the "الاهتزاز" switch.
- **No character movements**: the limp, the out-of-breath and startle poses and the head turns were removed at
  the owner's request (phase 1 built them, he asked for them out). The camera moves, the haptics and the sounds
  stay. `scripts/look_mod.gd` is gone with them — do not bring any of it back without being asked.

## The round's event, the call to prayer, doors and lights
- **One event per round**, decided from the room seed so the server and every phone agree
  (`Rules.ev_kind / ev_at`, mirrored in `rules.js`): a **blackout** (20 s, every street and house light
  out and the ambient dimmed), **heavy fog** (40 s, fog density ×3.4) or an **alarm** (5 s, one live
  survivor given away to the killer as a pulsing arrow at the edge of his screen — his minimap still
  shows nobody). It fires between 60 s and 180 s in, and everyone gets a short Arabic warning.
- **Call to prayer**: also seeded (40-190 s). `world.adhan_point()` is the minaret on the fareej and a
  far corner of the map elsewhere; it plays `assets/sfx/adhan.mp3` on the Music bus at -14 dB with a
  low-pass, and fades out over 2.5 s when the snapshot says it is done. **The file is the owner's own
  recitation, trimmed to 55 s** — replace `assets/sfx/adhan.mp3` to change it.
- **Doors**: every doorway that does not already hold a pallet gets a leaf (`world._build_doors`,
  `set_door(i, shut)`), open by default so the map plays as it always did. Survivors and the killer can
  swing one shut or open from the interact button; it goes through the rules (`door` input, `dr` in the
  snapshot) so everyone sees the same thing, and anyone within 60 m who did not touch it gets a marker
  pointing at the sound. **There is no door sound file yet** — drop `assets/sfx/door.mp3` in and it can
  be played; until then it is silent on purpose. Windows stayed as vault openings.
- **Lights**: `world._amb_light()` registers every street lamp, house lamp, barrel fire, tent ember and
  pumpkin with its base energy. One loop in `_process` flickers them, blacks them out during the event,
  and drops a **house** light to 12% while the killer is within 25 m of it, easing back when he leaves.
  The gate, hook and generator lights are deliberately left out of all that.

## Hidden developer tools
Locked by default: fifteen taps on the version text open a page that asks for the **passkey 4343**
(`Dev.KEY`, `Dev.try_key`); «اقفل الأدوات» locks them again (`Dev.lock`). The dev page also has
«زر Vanish بالجولة» (`Dev.vanish_tool`): with it on, the round shows a **«Vanish»** button (survivor
and killer) that hides me on every other phone — `main.vanished` goes out as `v` in my `st`
(the server relays it), other phones hide that remote's node and torch, and the computer killer
ignores me. While she is vanished, survivors' phones also drop the heartbeat, breathing and chase
music. **Every phone matches a remote player's stride to how fast they really move** (`r.spd`, the
`play(anim, stride)` scale), and my own run/sprint stride may go up with `Dev.speed` (`_fast()`), so
a faster player runs instead of gliding. On a phone that has them, a small panel appears during a round with two switches:
see-through outlines of the other players (their own model drawn again with a `no_depth_test` overlay
material, plus a mast and a name/distance tag), and a movement-speed multiplier. All of it is local:
nothing is relayed, the server never hears about it, and nothing is drawn on anyone else's phone.
`tools/dev.tscn` covers the buses, the lock and both tools.

## Dropping new content in (no code changes needed)
The game looks for these files and uses them the moment they exist. Until then it falls back to
what is there now, so a missing file never breaks a round.
- **`assets/anims/<name>.glb`** — Mixamo clips, exported as **glTF Binary, "Without Skin", 30 fps,
  no keyframe reduction**, on the same skeleton as the others. Already used: `idle walk run sprint
  crouchwalk hide attack injured dying vault carry carried hang crawl repair`. **Waiting for:
  `hit`** (a flinch played on whoever is struck, one shot, never touches movement), **`fall`**,
  **`standup`**, **`cheer`** (the victory shot uses it instead of the dance), and
  **`wave` / `dance` / `clap`** (the campfire emotes, hand-posed in code until then).
- **`assets/props/<name>.glb`** — a real model to replace the boxes built in code: `car`, `lamp`,
  `generator`, `hook`, `locker`. `world._swap_model()` hides the code-built meshes and parents the
  model to the same body, so **collision never changes** and the round plays identically. The
  garage's own parked cars are a MultiMesh and are not swapped. A generator's "done" bulb stops
  changing colour when a model replaces it (its light still does).
- **`assets/sfx/<name>.mp3`** — `ui_click` (menu buttons) and `door` (door leaves). Still silent.
- Whole map models go through `tools/split_glb.py` (see `assets/maps/carpark.glb`).

## The look pass (mobile-friendly, no baked lighting)
A real lightmap bake is **not possible** with this project: the maps have no saved scene to bake —
every round is generated from the host's seed when it starts. These three do the same job at
runtime instead:
- **Ground shading** (`world._ground_ao`): the terrain's vertex colours are darkened under walls,
  houses, tents and the market while the mesh is built. Free to draw, survives a new seed.
- **Contact shadows** (`world._blob` / `_build_blobs`): a soft dark patch under every generator,
  hook, locker, pallet, car, lamp, wreck and garage column — all of them in **one MultiMesh, two
  triangles each** (≈50 on the forest, ≈400 in the garage).
- **Finer materials** (`world._pbr`): every procedural surface now carries a second detail layer
  (albedo + normal at 7× the frequency) so concrete and wood keep their grain up close, plus a
  stronger normal and more roughness contrast.
- **Grade pass** (`shaders/grade.gdshader`, `main._build_grade`): one fullscreen shader under the
  HUD — vignette, film grain, corner desaturation, and the edges tighten and go red as `danger`
  rises (or while you are down / hooked). Off on the lowest graphics preset.

## The killer is «البركة القرمزية»
`assets/chars/killer.glb` (30k triangles, the round) and `killer_hi.glb` (70k, the character stand
in trial mode) are the owner's Crimson Benediction sculpt. **The old masked killer is gone** — his
model and its two extracted textures were deleted, and nothing else had to change because the
character id is still `killer` (server, rules, menus, tests). Two things in `main.gd` follow her:
the jumpscare aims at 1.74 m (her face while she lifts; his was 1.62) and `killer` left `MALE`.
She was rigged on a machine with no Godot, so she was checked with a software renderer that
skins the GLB with the clips in `assets/anims` the way `character_rig.gd` retargets them (idle,
run, crouch, repair, attack, carry, injured, hang, crawl) — **run `tools/shot14.tscn` on her
the first time a Godot build is at hand.**

## The hidden character and the three new survivors
- `survivor4` is now «الفالكيري القرمزية» (Crimson Valkyrie) and it is **hidden** (`GameMenu.SECRET`):
  `_char_list()` leaves it out unless `Net.has_secret()` — true on the owner's phone (the one with
  the hidden tools unlocked, `Dev.unlocked`) and on any phone he has opened it for (`Net.secret`
  in `user://profile.cfg`). On the owner's phone every friend row on the friends page has
  «افتح السرية / اقفل السرية»: it sends `{t:"gift", to, on}`, the server relays `{t:"gift", from, on}`
  to that friend **if he is online**, and his phone saves it. `Net.gifted` remembers who got it.
  The server never hands `survivor4` out by itself (`HIDDEN` in `server.js`), and the practice
  dummy in trial mode no longer wears it. «ناجي 4» (the old model) is deleted.
- `survivor5` is «المحاربة الجريحة» (Battle-Scarred Survivor) in place of «المقاتلة», and
  `survivor7` is «الباحثة» (Neon Genome Researcher) in place of «الطالبة». Same ids, new models.
- All three were rigged with `--bake`, each with a `_hi` copy:
  valkyrie `--arms 0.23,0.52,0.81 --chest 0.12 --hair 125`, battle `--arms 0.205,0.375,0.515
  --chest 0.12 --hair 85`, researcher `--arms 0.23,0.43,0.60 --chest 0.12 --hair 85`
  (`--hair` = how dark counts as hair: 70 for black, ~120 for brown). Checked with the software
  renderer only, like the killer. **The shoulder joint sits 3 cm inside the armpit crease** on all
  three: at the crease (the first build) the top of the shoulder stayed a square shelf in idle and
  the owner sent it back; further in (6 cm) the upper arm balloons. The bake path also keeps dark
  things *on the arm* (armbands, sleeves) out of the hair mask now.
- **The unlock code**: the gift needs the Render server to be on this version and the friend online,
  so there is a second way with no server: `Net.secret_code(name)` — six digits from the friend's
  username — shows on the owner's phone when he presses «افتح السرية», and the friend types it into
  «كود الشخصية السرية» on his own friends page (`Net.redeem`). Tied to the username.

## «حارسة الليل» (survivor6) — the first character with lossless maps
The owner's Midnight Sentinel sculpt (1.9 M triangles, three 2048 maps: colour, metal-rough,
normal; 802 texels per metre on average, 831 on the face) replaced the nurse «الممرضة» in the
`survivor6` slot (same id: server, menus, the camp cast and the tests are unchanged). Made with
`python3 tools/rig_character.py sculpt.glb assets/chars/survivor6.glb --faces 30000 --tex 2048
--face-faces 9000 --arms 0.235,0.43,0.60 --chest 0.12 --hair 85 --hair-density 0.85 --fringe --bake --external`
and `... survivor6_hi.glb --faces 100000 --tex 4096 --face-faces 40000 ...` (same switches; 39k and
122k triangles in all). Four switches are new:
- `--face-faces N`: the front of the face (skin, brows, lashes, eyes: everything there but the hair)
  gets its own budget. Sharing the head's with the hair, her face came out at about a tenth of the
  sculpt's triangles: lips, eyelids and brows lost their shape and the owner saw a different face in
  the game. The close-up keeps all 21.8k of the sculpt's face triangles, the round model 9k.
- `--external`: the maps are written **beside** the GLB as lossless PNGs
  (`survivor6[_hi]_col / _mr / _nrm.png`, no JPEG step) and the GLB points at them by `uri`, so
  Godot's glTF importer loads the textures it imported itself. Each PNG has a **committed
  `.import`** (`.gitignore` lets `assets/chars/*.png.import` through) with `compress/high_quality=true`
  — **ASTC 4x4 on the iPhone, BC7 on desktop** instead of the default ETC2 / DXT1 — mipmaps, no size
  limit, and the normal map flagged as one. Every other character still takes Godot's defaults.
- `--hair-density 0.85`: her curls carry highlights, so the hair gets 0.85 of the body's texels
  (default 0.32). The close-up has 1418 texels per metre on the body, ~2980 on the face and ~1200
  on the hair, all above the sculpt's own 802: the bake loses nothing the source had.
- `--fringe`: hair hanging over the face keeps its strands through the collapse, and the bake
  takes **hair on hair** (`Sculpt.sample(want)`): hair has its own KD-tree (its triangles are big and
  its vertices few, so by vertex distance the dense forehead always won), a texel on a hair face
  takes the nearest hair triangle, and on the head the thin edge of a hair mass does too when hair
  is within 8 mm of the nearest surface. Skin is never forced (that put skin into the irises and
  the collar buckle). "Hair" here is **hair proper** — the big dark masses (`hair_only`, connected
  components over 2% of the dark vertices) — never the brows, lashes or irises: counting those made
  the brows thick and brown and put dark wedges of fringe over the eyelids. Without it the fringe
  came out streaked with forehead skin.
`character_rig.gd` now sets every character material to anisotropic filtering (glTF materials
default to plain trilinear; the level, 16x on «فائق», comes from the viewport). `tools/tex.tscn`
checks what the engine really imported: sizes 2048 / 4096, BC7 not DXT1, mipmaps, the ASTC copy
in `.godot/imported`, anisotropic filtering. `check.yml` photographs her pose sheet through
Forward+ (`tools/shot14.tscn`, `NF_SHEET` picks another character).

## The start screen (the camp), second pass
- **Logo and opening shot**: `assets/ui/logo.png` (the owner's NightFall wordmark, cut out of
  `assets/ui/poster.jpg`) replaces the «NightFall» label on the main and name pages. Once per launch
  (`NFLobby.intro_done`) the poster fills the screen and fades while the camera comes down from the
  moon (`NFLobby.intro` 0 -> 1 over 2.8 s); the menu fades in at the end. Skipped headless.
- **The killer stalks**: while nobody in the room plays the killer, the shipped killer (`stalker`)
  vanishes for 2-4.5 s and comes back at the next of `STALK` (all right of the menu column),
  usually nearer the fire, with a low red light on her face (`stalk_rim`).
- **At the fire**: the character standing there is the one I last started a round with
  (`Net.last_char`). Online friends who are not in a room sit at the fire with green name tags
  (`GameMenu._friends_at_fire`, the survivor picked from a hash of the name since the server does
  not say); tapping one (`camp_pad`, `NFLobby.pick`) makes a room and invites him.
- **Air**: ground mist and fireflies (`_drift`), a shape that crosses behind the trees every
  16-30 s (`shade`, forest and village only), the hook at `HOOK_AT` swinging (bloody when I died
  last round), the phone's tilt leaning the camera a few degrees.
- **The camp wears the picked map** (`NFLobby.set_map`): palms and dunes for the Empty Quarter,
  palms and the sea for the beach, the wall, a lit house and the minaret for the fareej, the slab,
  columns and strip lights for the car park, three houses for the village. The dressing glows a
  little of its own colour so it reads in the dark.
- **Blood moon**: if nobody got out of my last round (`Net.last_round.wipe`), the camp sits under it.
- **Card and daily line**: the card shows the level title (`Net.title()`) and the last round
  (`Net.last_round`); under the status line, «تحدي اليوم» (`Net.daily()`, picked from the date,
  counted on the phone, +150 XP once) and a tip that changes with the date.
- **Emotes** (`character_rig.gd`): the wave has a hand on the hip and the forearm swinging over
  the head; the clap goes over the head for the second half; the dance is 4 s with two moves
  blended (arms up / arms rolling in front) and stepping knees. `tools/camp.tscn` checks the camp
  headless; `tools/shot15.tscn` photographs it.

## The owner's props: gate, fortress, generator, gallows, campfire
Five Meshy models (1-2.6 M triangles each) went through **`tools/prop_bake.py`** — the bake path of
the rig tool with no skeleton: placed in metres (`--width/--height`, `--yaw`, `--depth` squashes
front to back, `--shift` moves the origin), collapsed with `tools/simplify.cpp`, a new atlas,
colour / metal-rough / normal baked from the sculpt, **a glow map** (`--emit LO,HI` on the
brightest channel, `--emit-red R`, `--emit-white`, or after the fact `--reglow --emit-box ...` to
light only what sits inside a box), and `--split X,Y` cuts the gate's two leaves into their own
nodes. `NightWorld.prop_glow(root, colour, energy, own)` turns the glow on in the game
(multiply operator: glow map x colour); `own` gives one instance its own material.
- `assets/props/gate.glb` (16k, 14.7 x 9.9 m, opening 6.8 m): the frame on the wall line, the
  leaves `leaf_l`/`leaf_r` moved onto the two sliding door bodies, so `set_gate_state` slides them
  as before; the EXIT sign and beacons are the gate's `mat`, red, green when powered. The
  concrete towers, header and walls of the gate stay as collision, hidden.
- `assets/props/wall.glb` (6k, a 16 m section, squashed to 2.2 m deep): `_build_fortress` lines
  every side with it, one MultiMesh per run (4-6 runs), each section on the lowest ground under
  it, inside face toward the map, 0.4 m outside the collision line; 1.35x on the Empty Quarter.
  The concrete perimeter is collision only now.
- `assets/props/generator.glb` (10k, 2.2 m): its work lamp and red beacons are the generator's
  `mat`: dark, blinking near the end, lit when done (the old bulbs are not built).
- `assets/props/hook.glb` (8k, 5.2 m gallows): the hook sits where survivors already hung (0.9 m
  in front of the hook point), the post 1.46 m behind it (`HOOK_POST_Z`, its collision moved
  there), and `hook_hang_y` drops from 0.62 to 0.43 so the shoulder meets the lower hook.
- `assets/props/campfire.glb` (8k, 1.6 m): the three burning barrels of each map are campfires
  now (`campfire_points`), and the camp's fire is the model plus the old core, sparks and smoke.
  The camp's hook is the gallows at 0.62x.
- `assets/props/tent.glb` (12k, the owner's Crimson Nomad Tent, 12.4 m wide, 7.8 m tall): drawn over
  every bedouin tent on the Empty Quarter (`_build_tent`, `tent_models`). Its cloth sits just
  outside the old 9 x 7 m tent walls, which stay as the collision (open front, vault gap on the
  left, the locker inside); the ember light moved up to 1.6 m. The fires outside the first three
  tents moved out to clear its guy ropes. No glow map: its lanterns are too small to bake one.
- `assets/props/car.glb` (12k / 4096, the owner's blood-stained Land Cruiser, 2 x 2.3 x 4.8 m, front +z,
  `prop_bake.py --faces 12000 --tex 4096 --width 2.0 --yaw 90`, then `glb_external.py`):
  every car in every map. `_car` (market cars, wrecks, fareej driveways) draws it at
  `CAR_SCALE` 0.9 so it matches the old 1.8 x 4.2 m boxes and their collision; the desert's
  `_wreck` draws it at full size, sunk into the sand like before; the garage's ~87 bays are one
  MultiMesh of its mesh (`_car_mesh`) in place of the three box ones, with the same hull boxes.
  `car_models` counts them (the garage counts as one).
`tools/props.tscn` checks all six maps headless; `tools/shot17.tscn` photographs each prop per map.

## The killer's car (`scripts/drive.gd`, `NFCar`)
**One** Land Cruiser per map that **only the killer** can drive. `world._place_drive_car()` puts
it at the end of `build()` (after two physics frames, because it asks the physics space for a
clear car-sized box, `_car_room`): on the garage **on the roof**, nose toward the top of the ramp;
everywhere else a few metres from the killer's spawn, nose toward the middle, clear of the
objectives and out of the lagoon. Every phone runs the same search, so they all agree.
- The car is a `CharacterBody3D` (two capsule "skids" + a cabin box), arcade handling: stick up =
  gas (11 m/s top, the killer runs 4.6), down = brake then reverse, sideways = steer; head-on
  crashes stop it and shake the camera. Headlights (one spot) and a red tail glow while driven.
- `main`: next to it the interact button is «اركب» (`car_in`), at the wheel it is «انزل»
  (`car_out`); attack and power are off while driving, the killer cannot get in while carrying,
  and a pallet stun stops the car. The camera leaves first person for a chase camera (drag to
  look round, it swings back behind the car). The killer's own body rides with the car, so his
  position, terror radius, heartbeat and the server's distance checks all use the car.
- **No server change**: the killer's `st` carries the car's position and heading and the
  animation name `drive`; other phones hide him and move the car (`NFCar.follow`).
- Running a survivor down sends the ordinary `hit` input (2 s per survivor on the phone, the
  rules' own cooldown): ok -> hurt, hurt -> down, as the owner chose.
- The killer's map shows the car (orange, «سيارتك», with ▲ on the roof); survivors' maps do not.
- **The killer's own car is `assets/props/car_drive.glb`**: the same sculpt at 45k / 4096 with the four
  wheels cut out on their axles (`prop_bake.py --faces 45000 --tex 4096 --width 2.0 --yaw 90 --wheels
  0.47,1.48,0.42,-1.22,0.46,0.52` -> nodes `frame`, `wheel_fl/fr/rl/rr`). `NFCar._animate()` rolls
  them with the speed (`WHEEL_R` 0.41 x the 0.9 scale), steers the front pair (`STEER_MAX` 0.55
  rad) and leans the body (`frame` and the cabin, not the wheels) out of turns and on the brakes;
  other phones get the speed sign and the steering from how the car moves and turns. Steering is
  gentler flat out. The parked cars keep `car.glb` (one mesh: the garage draws it as a MultiMesh).
- **Carrying in the car**: the killer can get in while carrying («حطّه بالسيارة»); the survivor rides
  **slumped in the passenger seat** on every phone (`NFCar.seat_spot()`, hips at `SEAT_HIPS`, the
  `slump` pose posed in code in `character_rig.gd` like the emotes, at `VICTIM_SCALE` 0.82: our
  characters are 1.9 m and the car is 0.9 of a real one, and at that scale head and feet stay
  between the floor and the 1.68 m roof — measured offline on every character), through
  `main._in_car()` / `_carry_spot()`; the node or rig scale goes back to 1 outside the car. Near a free hook (4 m) the button is «انزل وعلّق» (`car_hook`): it sends `hook`
  first, while the server still has the killer at the car (its reach is 4.5 m), then gets out.
  No server change. A pallet stun while carrying still drops them, as on foot.
- **The cabin**: `assets/props/cabin.glb` (120k, 4096, the owner's Mud-Caked Toyota Cabin, baked with
  `prop_bake.py --faces 120000 --tex 4096 --width 1.5 --yaw 180 --part
  steer,0.394,0.48,0.079,0.25,0.004,-0.39,0.921,0.07`: the **steering wheel is its own node `steer`**
  on its column axis `NFCar.STEER_AXIS`, turned `STEER_TURNS` 2.3 rad at full lock; left-hand
  drive). The model has **no seats**: `NFCar._seats()` builds both front seats (cushion, reclined
  back, headrest). `_hands()` puts the killer's gloves on the rim at ten to two (they ride with
  the wheel) and `_arms()` re-aims the crimson sleeves from the shoulders every frame. sits in the body at
  `NFCar.CABIN_AT` (floor 0.5 m, dashboard against the windscreen). The killer drives **from the
  seat** by default (`NFCar.EYE`, 1.5 m up under the 1.68 m roof): the body's own faces point
  outward and are culled from inside, so the windows are clear and the bonnet stays in view;
  `_trim()` adds the headliner and the pillars. Only the driver's phone shows the cabin. While he
  drives, the attack button is «الكاميرا»: seat <-> chase camera.
- **The radio**: `assets/sfx/radio.mp3` is the owner's song (his m4a, mono 112k, loudness-normalised),
  looped on an `AudioStreamPlayer3D` in the dashboard on the **Music** bus, muffled and fading with
  distance (48 m reach), so survivors hear it as the car comes close. At the wheel the power button
  is «الراديو» / «سكّر الراديو» (green ring while it plays); off by default, and off pauses it.
  It plays only while someone is at the wheel. **No server change**: the killer has no torch, so
  his `st` `f` flag carries the radio switch and every phone plays it from the car.
- **Feel**: a stronger pull off the line that tapers near top speed; the body sits on a damped spring
  (`bob`) kicked by bumps, shivers with the engine, and the driver's eye (`eye()`) rides with all of
  it and with the lean; dust (`_puffs`, the map's colour, not in the car park) off the rear when
  over 2.5 m/s, exhaust smoke while it runs. **Speedometer** (`main._draw_speedo`): a 0-60 km/h
  dial bottom centre while driving, red band at 50, eased needle, figures and D / R.
- **Getting in and out, and the car's sounds** (the owner's three clips): `car_drive.glb` has the
  driver's door as its own node `door_l` on its front hinge (`prop_bake.py --box door_l,0.78,0.55,-0.07,
  1.2,1.42,0.85,0.98,1.1,0.85 --box door_l,0.6,1.42,-0.05,1.2,1.66,0.83,0.98,1.1,0.85`: two boxes,
  because the window frame leans in; a `--box` piece gets at least `--box-faces` 3500 triangles). The sculpt is a shell, so the door's inside is its back faces drawn again dark (`door_card`). `NFCar` wraps it in a `door_hinge` node and drives it with an
  **AnimationPlayer** (`door_anim`, clips `get_in` / `get_out` built in `_door_clips()`: a value track
  on the door's yaw, and on `get_in` a method key that calls `_turn_key`). `NFCar.begin("in")`: the
  door swings open, the camera glides from outside the door into the seat, the door shuts by 1.5 s,
  and at 1.8 s the key turns —
  `assets/sfx/car_start.mp3` plays and `engine.ogg` (a seamless loop cut from his driving clip; OGG
  because an MP3 clicks at the seam) fades in under it, pitch following the speed. No gas until
  `seated()` is 1. `begin("out")`: key off, door opens, he steps out 0.5 s later (`main.car_leaving`),
  door shuts. Other phones play the same when the killer's `st` animation turns to / from `drive`
  (`main.car_remote`), and the cabin shows through the open door. `car_pass.mp3` (`NFCar.whoosh`,
  trimmed so its peak is 1.2 s in) plays when the car is about to go past a survivor at over 6 m/s —
  on that survivor's phone and at the wheel (`main._car_pass`, once per 5 s). No server change. `tools/drive.tscn`
  tests the whole loop (wheels, steering wheel, hands, speedometer, the seat, hooking from the
  seat); `tools/shot19.tscn` photographs the driver's seat through Forward+.
- **Second pass on the owner's phone feedback**:
  - **She drives herself**: the killer's own rig sits in the driver's seat (`NFCar.driver_spot()`,
    `DRIVER_HIPS`, the `drive` pose posed in code like `slump`) on every phone, and
    **`scripts/reach_mod.gd` (`NFReach`, a `SkeletonModifier3D`)** is a two-bone IK that puts both
    wrists on the rim at ten to two (`NFCar.grips()`: the old glove points, which turn with the
    wheel; elbows toward poles down and out) after the animation. Everyone else always sees her
    there, and so does the driver from the chase camera; **from the seat** her body is hidden on the
    driver's own phone and the gloves and sleeves on the wheel show instead (a camera in her head
    looked out through her hair and shoulders). `hide_head` (the neck scaled to nothing) is still
    in `NFReach` but unused. `CharacterRig.reach()` / `reach_clear()`.
  - **The victim fits**: seated, every character is at most 0.81 m from hips to head top
    (measured offline, `_hi` models too); at the old 0.82 scale with the hips at 1.0 m the head
    reached 1.66 m, through the 1.645 m headliner and the roof. Now `VICTIM_SCALE` 0.72 and the
    seat hips at 0.95 m (head 1.53 m, feet on the 0.5 m floor), the same scale for the driver.
  - **The door's inside panel** (`door_card`) is only the part under the window (`DOOR_SILL`): the
    dark back faces of the glass, its frame and the mirror blocked the side window from the seat.
  - **No heartbeat, breathing or chase music while she drives** (`k_driving` in `main`), on any
    phone; on foot all of it as before. The engine and the radio give the car away instead.
  - **The radio stays on** after she gets out if she left it on: it plays from the parked car, and
    her `st` `f` flag is the radio switch whether or not she is at the wheel.
  - **Three gears** (`NFCar.gear`, `GEAR_TOP` 11 / 19.5 / 25 m/s = 40 / 70 / 90 km/h; the third at the
    owner's request): a «غيار 1 / 2 / 3» button beside the speedometer (icon `shift`, 1 -> 2 -> 3 -> 1),
    each gear up pulls a little softer (1.0 / 0.85 / 0.72), engine pitch drops on the shift up; the
    speedometer reads 0-100 with the red band from 90 and shows 1 / 2 / 3 / R.
- **Every parked car can be taken** (the market's, the random ones, the car park's ~87 bays):
  `world.parked` lists them, the interact button is «اركب» next to any of them (`main._car_near`:
  -1 the driving car, 0.. a parked one), and `world.take_parked(i)` **swaps** the one `NFCar` with
  that parked car (`NFCar.put`): the driving car takes its spot, the parked car (its `_car` body, or
  its MultiMesh instance and hull box in the car park) takes the driving car's, so a car is left
  wherever she last got out. No server change: other phones see her `st` turn to `drive` at a spot
  away from their NFCar and run the same swap with `nearest_parked`. The fareej driveway cars are
  left out (walled yards, the gate too narrow to turn out of), and the Empty Quarter has only its
  half-buried wrecks. Switching cars turns the radio off.
- Every `prop_bake.py` output now carries its own command line in `asset.extras.bake`.

## Quality and interface pass (the owner: "enhance it with quality", interface additions)
- **Every character, the driven car, its cabin and the parked car keep their maps beside the GLB**
  (`tools/glb_external.py`: the embedded JPEGs moved out byte for byte, so nothing is re-encoded
  and the repository does not grow; the GLB points at them by `uri`). Their committed `.import`
  files give colour and normal maps `compress/high_quality=true` — **ASTC 4x4 on the iPhone** in
  place of ETC2, which was blocky on normal maps and banded on skin — and leave metallic-roughness
  at normal quality (memory and download size). `.gitignore` lets `assets/chars|props/*.jpg|png.import`
  through. Run the tool on any new baked model.
- **Anisotropic filtering on the whole map** (`world._sharpen()`, last in `build()`): every
  textured material (procedural surfaces, the owner's models, the car-park pieces, MultiMeshes,
  the killer's car) and the foliage / palm shaders. `aniso_mats` counts them.
- **Interface edges**: `Gfx.apply()` turns on 2D MSAA (4x on «فائق», 2x from «عالي»), the HUD
  buttons are drawn anti-aliased with 64-point rings, and each one dips and ripples when pressed
  (`main.pop`).
- **The car**: other phones **predict** the driven car between the killer's 15 updates a second
  (`NFCar.follow`: velocity and turn rate from the last two updates, at most 0.25 s ahead, and a
  snap when it jumps more than 12 m, e.g. a parked-car swap) instead of easing toward a stale
  point; **brake lights** (the tail light brightens while it slows hard, worked out from the speed
  on every phone) and a white **reversing light**.
- **Event feed** (`main._feed` / `_feed_watch` / `_draw_feed`, top right under the settings): who
  went down, got hooked, was saved (and by whom), got out or died, the killer pulling someone out
  of a locker, each generator done («اشتغل مولد — 3 من 5») and the gates opening. Five lines,
  6 s each, sliding in and fading out. Deaths, escapes, downs, generators and gates come from
  watching the round's state, the rest from the events, so it is the same offline and online.
- **Hit direction** (`_draw_hit`): when I am struck, a red blade on the ring points back at where
  the blow came from (the killer, or the car) for 1.6 s. **Gate arrow** (`_draw_gate`): once the
  gates have power, survivors who can still run get a green arrow to the nearest gate with its
  distance.
- **Controls in the settings panel** («التحكم»): «حساسية الكاميرا» (40-200%, `Gfx.look_sens`),
  «مجال الرؤية» (-10..+15°, `Gfx.fov_add`, live: `main._base_fov()`), «حجم الأزرار» (80-130%,
  `Gfx.btn_scale`) and «وضوح الأزرار» (35-100%, `Gfx.btn_alpha`), saved in `graphics.cfg`.
- **«طريقة اللعب»** (menu page `help`, `GameMenu.HELP`): a tab for the survivors and one for the
  killer, each tip a drawn icon, a title and a line or two.

## The high-end pass (Forward+, `scripts/look_hd.gd`, `NFLook`)
The owner asked for a high-end look. The project now runs **Forward+ on the phone too**
(`rendering_method.mobile="forward_plus"`), and everything Forward+ adds goes through `NFLook`:
- `NFLook.apply(env, kind)` on every environment: the maps (`world.look_kind()`: night / fog /
  day / garage), the camp ("camp") and the results stage ("stage"). By «جودة المؤثرات»:
  0 glow; 1 + SSAO, **volumetric fog** (beams from lamps, torches, headlights), torch and headlight
  shadows; 2 + SSR in the car park. **SDFGI and SSIL are off everywhere**, and the moon/sun have
  **no soft (PCSS) shadow**: on the owner's iPhone (Metal) the Empty Quarter's dunes came out as
  black squares with hatching that moved with the camera (shadow acne), although the lavapipe
  screenshots were clean. `soft_sun()` now gives hard shadows with more bias (0.12 / normal 2.2).
  A clean CI shot does not prove an effect works on the phone — ask the owner for a recording. The governor drops effects first when the
  frame rate falls, so the heavy ones go first. `Gfx.apply()` sets their quality (half-size
  SSAO/SSIL, SDFGI 16 rays / 15 frames, fog volume 64 or 48).
- `NFLook.soft_sun` (moon / sun / camp moon: hard shadows, extra bias against acne),
  `shadows_on` (my torch, the car's headlights, the camp key light; also a 3.5 fog beam),
  `halo` (every map lamp through `world._amb_light`, the camp fire: a glow in the fog).
- **Skin**: `NFLook.skin(model, file)` turns on subsurface scattering, masked by
  `assets/chars/<file>_skin.png` (made by `tools/skin_mask.py` from the colour map — warm or rosy,
  moderately saturated; **re-run it after every re-bake**, the atlas changes). No mask, no effect.
- Full HDR: `tonemap_white` goes to 11 on every night environment, or moonlit white plaster burns out.
- **«محرك الرسم»** in the settings: «خفيف (أسرع)» writes `user://override.cfg` (read at start-up
  through `application/config/project_settings_override`) and the next launch runs the old Mobile
  renderer, where none of the above runs and the game looks as it did. «عالي (فخم)» deletes it.
- **Sharper bakes** (same switches as before, only resolution): killer and survivors 4/5/7 at
  2048 in the round and 4096 / 100k triangles for `_hi`; the cabin 60k / 4096; the gate 4096 (every map
  at full size: the IPA is ~525 MB, too big to send in chat, so the owner downloads it from the
  GitHub release. `tools/glb_texsize.py --max 2048 --keep-color` halves the normal and metal-rough
  maps and brings it to ~400 MB if it ever has to be smaller); the
  gallows, campfire and fortress wall at 2048. Survivors 1/2/3/6/8, the car, the tent and the
  generator keep their old files: their sculpts (or their exact bake switches) are not here.
- `tools/shot18.tscn` photographs the camp, the stand and every map (a survivor at a generator,
  the car with its lights on); `check.yml` renders it through Mesa's software Vulkan (lavapipe):
  `NF_LOOK="hd lo"` gives the new look and the old one side by side (off by default: ~13 min each).

## Strong devices (`Gfx.strong`)
The owner and his friends play on the iPhone 18 Pro Max and an M2 iPad Pro. `Gfx.detect_strong()`
(iPhone16,x = 15 Pro and later, iPad13,x = M1 and later, from `OS.get_model_name()`; `NF_STRONG=1`
fakes it) makes the phone start on «فائق» once (`tier` in graphics.cfg; afterwards the player's
choice stands), and while it is on «فائق» (`Gfx.maxed()`):
- high SSAO, medium subsurface scattering, 16x anisotropic filtering, moon/sun **4 shadow
  cascades**, grass 1.6x thicker and drawn to 62 m, and **every character in the round uses its `_hi` model**
  (`main.hd_chars()`; the 100k close-up with the 4096 colour map).
- **A locked 60** (the owner's choice: "really smooth, always, on ultra"): strong devices start on
  «فائق» at 60 fps with MSAA 2x (`TIER` 2 re-applies this once). The 120 Hz Info.plist key was
  taken out again, so iOS paces the app at an even 60. Below 100% the picture is upscaled with FSR.
  On «فائق»: SSAO high at half resolution, volumetric fog 64³, 4 shadow cascades to 100 m,
  `mesh_lod_threshold` 0.7. The governor gives up the resolution first (to 85%, FSR), then shadows,
  then effects — and now brings them back again after a long smooth stretch (`_step_up`).
- The app is still **iPhone only** (`targeted_device_family=0`): on the iPad it runs in the iPhone
  window. Native iPad (2) needs the 4:3 layout checked first.
`check.yml` runs `drive` a second time with `NF_STRONG=1`.

## Older phones (`Gfx.weak`: the owner's friends on the iPhone 13 / 14 / 15)
Every iPhone or iPad that is not strong (A16 and older: iPhone15,x and below, iPad12,x and below;
`NF_WEAK=1` fakes it) gets, **once** (`weak` / `WEAK_TIER` in graphics.cfg; the player's own choices
stand afterwards):
- **the Mobile renderer from the next launch** (`set_engine(false)`, i.e. «محرك الرسم: خفيف»):
  Forward+ draws its depth pre-pass, SSAO and volumetric fog in passes these GPUs pay dearly for,
  and with its effects off it looks nearly the same. The renderer only changes at start-up, so the
  first launch after the update stays on Forward+ with its effects held off (`_transit`). A player
  who wants the full look picks «عالي (فخم)» in the settings.
- «عالي» with moon shadows, MSAA 2x (resolved in tile memory on the Mobile renderer), 85%
  resolution through FSR, a locked 60 (the 13 Pro and 14 Pro have 120 Hz screens and would heat up).
- always, whatever the settings: the governor may take the resolution to **70%** (`scale_floor()`,
  85% elsewhere) and, as its very last step, cap the frame rate at a **steady 30** for the rest of the
  session; models switch to their simpler level of detail sooner (`mesh_lod_threshold` 2.0),
  anisotropic filtering 2x, grass 0.75x as thick, every map light fades out from 32 m (45 m
  elsewhere) and the wall-wash spots from 38 m.
`tools/weak.tscn` (run with `NF_WEAK=1` in check.yml) checks all of it and plays a short round.


## Lighter nights and «السطوع»
The owner found the maps too dark. `world._build_environment` now multiplies every night map's
ambient by 2.0, its fog by 0.65 and its moonlight by **0.6** (it was 1.4 until the owner found the moonlight far too bright), with exposure 1.32 (the Empty Quarter
is untouched: it is daylight). On top of that the settings panel has «السطوع» (60-160%,
`Gfx.brightness`, saved in `user://graphics.cfg`): it multiplies the exposure live on the map and
the camp through `Gfx.look_changed`. `tools/shot16.tscn` shoots three maps before and after.
`.github/workflows/check.yml` runs the headless tests and these screenshots on every
`claude/**` branch and pushes them to the `check-shots` branch (artifact downloads are blocked
from the agent's machine).

- `survivor8` «وردة الليل» is the first character with the owner's own textures (colour + normal +
  metallic-roughness from the sculpt). The others are still painted by body zones.
- Models other than the characters and the car-park module are boxes/cylinders built in code;
  textures are procedural noise.
- The garage has no doors to swing (the model's cores are solid, a leaf would float against a wall)
  and no windows: vaulting there is over the concrete crash barriers.
- No baked lighting (needs the editor on a GPU machine).
- Player positions are client-reported (server only checks distances for interactions).
- Friends list, XP, escapes and kills live on the phone; usernames are not reserved.
- No UI click sound until the owner supplies `assets/sfx/ui_click.mp3`, and no door sound until `assets/sfx/door.mp3`.
- Haptics cannot be verified off-device: `Input.vibrate_handheld` does nothing on desktop or in headless runs.
- The emotes are posed by hand in code, not Mixamo clips. Mixamo needs an Adobe login, so nothing could be downloaded
  here: **wave.glb, dance.glb and clap.glb are the missing files** — export them from Mixamo as glTF with the same
  skeleton as the others, drop them in `assets/anims`, and they replace the hand-made ones with no code change.
- Desert animals have no leg animation (single merged mesh, so they bob and sway instead).
- Team-bar portraits are drawn avatars in each character's colour, not renders of the models.

## The road chase (the owner: "they reach the first gate, get into the car, 600 m to the second gate")
- **The road**: `NightWorld.ROAD_LEN` is 600 m behind each gate (it was 60), `LANE_W` 12 m so her car
  can come up beside theirs, built in 50 m pieces (each light only reaches its neighbours, culling
  works) with 9 m walls, a lamp every 40 m, the centre dashes as one MultiMesh, a crash barrier half
  across the lane every 60 m between the hooks (first one side, then the other: the car has to weave),
  «500 م … 100 م» on the wall, and **the last gate** («البوابة الأخيرة») at the end. On the car park the
  roof gate's road runs out at roof height. `road_d / road_left / road_at / esc_start / road_end`.
- **Hooks all along it**: 9 per road, one every 60 m on alternating sides (`_plan_road`, appended after
  the map's own so those keep their numbers; `road_hook0` is where they start). The map does not draw them.
- **One shared escape car per gate** (`world.esc_cars`, an `NFCar` from `car_drive.glb` with no cabin,
  `limit` = `ESC_TOP` 14 m/s = 50 km/h; her second gear is 19.5, so she can catch it), 16 m past the
  gate, nose down the road. Once the gates have power the interact button next to it is «اركب وسوق»
  (first one in drives) or «اركب معهم». The door and the key play on every phone, no gas until the
  key has turned. The driver uses the stick like her car; everyone in it gets the chase camera; the
  car **seats six** (`NFCar.seats`, `ROWS`: the front pair, a middle row and a third row over the rear
  axle; `Rules.CAR_SEATS` / `CAR_SEATS` in `rules.js` turn a seventh away and the button hides), and
  everyone in it is drawn on their own cushion (`NFCar.seat_at(k)`, `drive` pose, the driver's hands
  on the rim through `NFReach`). The killer's car keeps its two seats. `st` animation `edrive` / `eride`: other phones
  move the car with the driver's position (`NFCar.follow`).
- **Rules** (both files): `roads[i]` = `{st 0 waiting / 1 on the road / 2 caught / 3 out, drv, who, t,
  why}`, a survivor's `car`. `board` starts the clock (`ROAD_TIME` 120 s); riders are not `free_now`
  (no hits, heals, repairs) and **the moon does not kill them**. The driver's phone sends `arrive` at
  the last gate (server: within 14 m of `layout.e`) and everyone in the car is `escaped` (+200).
  The killer's phone sends `ram` when her car touches theirs (server: within 8 m of the car); `ram`
  or the clock reaching 0 is `caught`: the car stops dead, the door opens, and everyone in it is
  **down** on the road beside it (`main._esc_leave`), for her to carry to the road hooks. On foot,
  reaching the last gate still counts (`escape`, server: within 10 m of a road end).
- **HUD** (`main._draw_road`, in place of the moon ring while you are in the car, on the road, or
  watching someone in it; for the killer while a car is on its way): the metres left in big figures,
  «للبوابة الأخيرة», the road's clock (red in the last 30 s), a strip from gate to gate with the car and
  her red dot, «القاتلة وراكم!» when she is right behind, a buzz when she is within 22 m, and the
  speedometer for the driver. The gate arrow turns into «السيارة %d م» once you are past the gate. The
  feed reports boarding, arriving and being caught; the team bar puts a car badge on whoever is in one.
- `tools/road.tscn` tests it; `tools/shot21.tscn` photographs the car waiting, driving with her behind,
  and the last gate (both in check.yml).

## The extreme pass (the owner: "improve the game to an extreme"; he picked these)
- **The beach's north gate** stood behind the lagoon's wading wall, out of reach. A **pier**
  (`world._build_pier`, `PIER_Y` 0.45, `PIER_W` 8 m, from `PIER_FROM` 34 m on the sand to the wall,
  a ramp up from the sand, rails, posts, three lanterns) now carries you over the water to it; that
  gate stands at `PIER_Y`, the wading wall has a gap above the deck only. Drawn on the map.
- **A perk for every survivor** (`Rules.PERK` / `PERK_INFO`, mirrored in `rules.js`): survivor1
  «نفس ثاني» (longer, faster burst after a hit or off a hook — phone), survivor2 «يد المصلّح» (repairs
  x1.3), survivor3 «الحامي» (pulls off a hook like 1.8 people), survivor4 «جناح الفالكيري» (down 20 s
  without being picked up: gets up hurt, once), survivor5 «جلد قاسي» (the first blow of the round does
  nothing: `shield` event), survivor6 «عين الليل» (a red eye on the ring points at the killer within
  28 m — phone), survivor7 «طب ميداني» (heals others x1.6), survivor8 «خطوة شبح» (on the killer's phone:
  no scratch marks, steps 14 dB quieter). Shown under the name on the character stand, as a chip
  under the minimap in the round (`main._draw_perk`, greyed once spent), and on «طريقة اللعب».
- **The killer's tools**: a new layout button `trap` (`NFControls.DEF`). Off the roads it lays a
  **bear trap** at her feet (`trap` input with `p:[x,z,y]`; `Rules.TRAPS` 4 armed, a fifth takes the
  oldest slot). Survivors see one only within 7 m (a faint glint); walking into it (their own phone
  sends `snap`) holds them `HELD_TIME` 4 s — no moving, a ring that empties — and gives her an arrow
  to it (`_add_sig` kind 4 «فخ»); within 2 m the interact button is «فك الفخ» (`disarm`). On an escape
  road the same button lays a **strip of spikes** 6 m wide across it (`spike`, one per road, moved if
  laid again): if the escape car's driver goes over it his phone sends `pop` and the road is `flat` —
  the car's limit drops to 45%. `main._tools()` keeps the trap and spike nodes in step with the rules.
- **Nitro**: the escape car's driver gets a «نيترو» button by the speedometer, once per run:
  `NFCar.nitro` = `NITRO_TIME` 3.5 s at `NITRO_MUL` 1.6x top speed and 2.6x the pull, flames out of the
  exhaust (`_build_flames`), engine pitch up. Other phones light the flames from the driver's `st` `f`
  flag (which is the torch on foot).
- **The computer killer** (`scripts/bot.gd`, `NFBot`): trial mode as a survivor has «قاتلة كمبيوتر»
  (on by default, `GameMenu.off_bot`), a killer player with `bot: true`. She bakes a navigation mesh
  from the map's static colliders when the map is ready (threaded; `nav_ok`), patrols generators
  being worked on, sees within 30 m in a 140° cone with a clear line, hears within 10 m, chases at
  4.6 m/s, swings (0.35 s wind-up, 2.2 s recovery, slowed after a hit), picks up, carries to the
  nearest free hook (road hooks only on a road), searches a locker she saw you enter, breaks dropped
  pallets and opens shut doors that block her, goes to blown generators and sprung traps, is stunned
  by a pallet dropped within 2.4 m. Every action goes through `Rules.handle` as her; she sets her
  remote's `pos / yaw / anim` each physics frame. Off the map (the roads) she steers straight.
- **The final shot**: when a survivor goes down (or an escape car is caught) and nobody is left on
  their feet or in a car, every phone slows to `FIN_SCALE` 0.3 for `FIN_TIME` 1 s of game time (3.3 s)
  and a camera circles the fallen one, with black bars and «آخر واحد طاح — name» (`main._final_check`).
- **Friends' board**: «الترتيب وسجل جولاتي» on the friends page (menu page `board`): me and every
  friend sorted by escapes / kills / level (`Net.board`, rows from `Net.fstats`), and my last 8 rounds
  (`Net.history`, 20 kept, with date, map, result and points; `Net.rounds`). See `stats` in Protocol.
- `tools/extreme.tscn` tests all of it (its own CI step: the bot's chase takes a while).

## The smoothness pass (the owner: "lagging and not stable", stutters and slow from the start of
## every round on every phone, and black dots)
- **MSAA always matches the project setting.** Godot compiles its pipelines ahead only for the MSAA
  level in `project.godot`; the viewport used another one, so everything new on screen compiled
  again when first drawn. `msaa_3d` is 0 in the project and on Forward+ (edges smoothed after the
  frame: SMAA on «فائق» / «عالي» AA, FXAA otherwise); the Mobile renderer's `override.cfg` carries
  `msaa_3d=1` and it uses 2x only when the project says so. 2D MSAA is off (a full-screen resolve).
- **The governor**: quiet while the map builds (`Gfx.quiet`) and for 5 s after the loading screen,
  drops effects before resolution, the resolution in one step, and **never steps back up** — going
  up and down every 20 s rebuilt buffers and recompiled pipelines each time.
- **In the round**: only my own character is the 100k close-up (others 30k); no subsurface skin
  pass (`setup(..., sss=false)`, `NFLook.no_skin`; the stand and the victory shot keep it); escape
  cars hidden until the gates have power; road floor/walls cast no shadow, road pieces and road
  hooks are not drawn past 170 / 150 m, road lamps have no fog halo or flicker; the bot's navmesh is
  read under the loading screen.
- Strong phones start at 90% with FSR (`TIER` 3); SSAO is softer (a suspect for the dark specks).
- **If the black dots stay**, ask the owner for a screenshot: they were never seen in CI.

## Gun mode, team names, friends and profiles, map icons (the owner's next requests)
- **«وضع السلاح»** (room option `set {gun}` → `room.gun`, `started.gun`; trial mode `GameMenu.off_gun`):
  every survivor has a stun gun, `GUN_SHOTS` 3 a round (`ammo`, snapshot row index 13, `gn` flag).
  The `gun` layout button fires where the camera looks (`main._shoot`: within `GUN_RANGE` 22 m, near
  the middle of the screen, clear line); input `shoot {hit}` — the server re-checks the range — a hit
  is `GUN_STUN` 3 s of `stun` (she drops whoever she carries) and events `shot` + `stun {by:"gun"}`.
  A short beam shows the shot on every phone (`_beam`). No gun sound file yet.
- **Team names**: survivors see every teammate still in the round with a name over the head and a
  soft see-through overlay (`esp_nodes[n].name` / `tmat` in `_update_esp`); the killer sees none.
- **Friends**: the server tells each friend where you are (`presence.st`: `menu` / `room` / `game`,
  `friends.status`) and when you were last seen (`seen`); the friends page lists online first with a
  coloured status line, «دعوة» works without a room (one is made first) and to an offline friend
  (kept 20 min, delivered on `hello` with `later`). **Profiles** (menu page `profile`): portrait in the
  character's colour with a status ring, level, character, numbers and a 60-character line
  (`Net.bio`, sent in `stats` as `bio`, with `ch`). «ملفي» edits mine.
- **Map icons** (`NFIcons`: `bolt` ⚡ generators with a repair ring, `gate`, `hook`, `locker`, `plank`,
  `hatch`, `trap`): drawn on the minimap and the big map, with a legend of the same icons.
- **Six seats** in the escape car and the **beach killer spawn** on the sand (it was in the lagoon past
  the wading wall) — see the road chase and the beach above. `tools/gun.tscn` tests the gun, the names,
  Vanish and the passkey; `node server/test.js` runs in CI now.

## The graphics pass (`scripts/decor.gd`, `NFDecor`; the owner brings models and textures next)
- **MetalFX** (`Gfx.on_metal()`, `metalfx_temporal()`): «تنعيم الحواف» has a fourth choice «MetalFX
  (الآيفون)» — Apple's temporal upscaler (`SCALING_3D_MODE_METALFX_TEMPORAL`, no SMAA on top); strong
  phones start on it (`TIER` 4). Below 100% on Metal the spatial one replaces FSR. Off elsewhere.
- **Colour per map**: a little more or less saturation and contrast per map in `_build_environment`.
  `NFDecor.grade()` (a colour-correction curve) is **not used**: in the screenshots it crushed the
  darks and burnt the colours — the environment reads the curve's 8-bit texture as sRGB.
- **Decals** (`world._build_decals`, `decals` counts them): blood under every hook (every other one
  on the roads) with a drag mark, oil under the generators, grime and stains about the map, puddles
  with their own roughness map on the rain night and in the car park. Textures drawn in code, 128 px.
  The older phones (Mobile renderer, 8 decals per mesh) get only the hook and generator ones.
- **Fire** (`NFDecor.fire`, `fire_fx`): flames, embers and (not on older phones) smoke on every map
  campfire.
- **«مطر»** — a fifth weather (menus, `THEMES` in `server.js`): streaks following the camera
  (`world.rain`, not under the car park's slab), wet materials (`_wet`: rougher surfaces glossier and
  darker), SSR on «فائق» effects (`look_kind` "rain"), denser blue fog, and lightning every 9-25 s
  (`_step_lightning`, two strokes on the moon and the ambient). **No rain or thunder sound until the
  owner sends files.**
- Not doable without the owner's files: hair that swings and eyes that blink need **bones in the
  hair and eyelids** (our characters are on the Mixamo skeleton, which has neither).
`tools/gfx.tscn` tests it; `tools/shot22.tscn` photographs the rain, a hook, a campfire, two grades.

## The owner's pictures and models (his button sheet, his map-icon sheet, moon, horses, camel, dunes, forest floor)
- **Buttons** (`main._draw_btn`): his look — black plate, silver bevel, glowing red ring, white icon,
  the name on a dark pill with a red edge and a red chevron. His nine drawn icons are cut out of his
  sheet into `assets/ui/btn/` (`gun bag vault crouch torch sig heal hand sprint`, mapped from the icon
  names by `BTN_PIC`); every other button keeps its drawn icon in white. The layout editor still
  draws its own simple circles.
- **Map** (`main._map_pic`, `assets/ui/map/`): his generator (grey, or orange with a green glow when
  done), market, bloody hook, red north gate ↑ / blue south gate ↓ (green ring once open) and hatch,
  cut out of his sheet (background keyed out); the legend uses them too. The drawn icons stay as the
  fallback.
- **Moon** (`assets/sky/moon.jpg`): his `moon.glb` is a 1.5 M-triangle cube-sphere with one 4096
  texture; its near side was rendered face on into a 1024 disc and the sky shader draws it
  (`moon_tex`, `has_moon_tex`), tinted red under the blood moon. Same in the camp.
- **Animals** (`assets/animals/`): `arabian-horse`, `bay-horse`, `paint-horse` (vinish.dev, CC BY 4.0
  — the credit is on «طريقة اللعب» and in `HORSES_CREDITS.txt`; ~100k skinned triangles each, with
  Walk / Graze / Idle clips: they walk on their own legs at a matching pace and look up from grazing)
  and his `camel.glb` (no clips: it still bobs). 9 on the Empty Quarter, 5 on older phones.
  `world._animal_node`, `animal_models`.
- **Scenery** (`world._build_scenery`, `scenery` counts): his `dune.glb` (120 m) ringed outside the
  Empty Quarter's wall and behind the beach, no shadows; `sand_blob.glb` patches on the beach;
  `forest_floor.glb` (leaf litter, ferns, stones, a log) on flat spots of the forest, drawn to 70 m.
  Their textures were cut to 1024 with `tools/glb_texsize.py`. No collision: all low or outside.

## The pistol in the hand (`scripts/gun_hold.gd`, `NFGun`; «وضع السلاح» only)
- A 19 cm pistol built in code (slide with serrations and sights, polymer frame, raked grip, trigger
  and guard, the barrel's mouth), or the owner's `assets/props/gun.glb` the moment it exists (grip at
  the origin, barrel toward +Z, metres).
- **Held by the arms, over the animation**: `NFReach` (two-bone IK) now has `use` (per arm) and
  `aims` (turns the hand so the fingers run along the grip); `CharacterRig.reach_arms()` and
  `bone_at()`. **Lowered**: right hand by the hip, muzzle down ahead, the left arm free. **Raised**
  (the gun button; the shot leaves 0.16 s later, once the arms are up, then it stays up 1.4 s):
  both hands out at shoulder height, the left cupping the right, and the aim **follows the camera up
  and down** (`_gun_pitch()`); she turns to where the camera looks. **Recoil**: the muzzle jumps and
  the hands come back (`kick`). The beam starts at the muzzle.
- Out only while the arms are free (`GUN_POSES`: idle, walk, run, sprint, injured, crouch-walk), ok or
  hurt, with shots left, not in a car, a locker, a vault or a trap.
- **Everyone sees it**: my `st` carries `g` (0 away, 1 lowered, 2 raised) and `gp` (the tilt); the
  server relays both (Render must be on this version); other phones run an `NFGun` on that remote's
  rig and kick it on their `shot` event.
`tools/gun.tscn` checks the hold, the raise, up and down, and the lowering; `tools/shot22.tscn`
photographs it lowered and raised.

## The owner's corrections after the pistol
- **Chase music when she is close**: it now plays whenever the killer is within `CHASE_NEAR` 16 m on
  foot (seen or not), or within 26 m with a clear line, for survivors (also while down); the killer
  hears it when a survivor is in front of her within 24 m or within 16 m. **Never while she drives**
  (`k_driving`), as before; heartbeat and breathing unchanged.
- **The developer tools are easy to reach again**: in the round a real «أدوات المطوّر» button on the
  left edge (it was a faint dot in the bottom-left corner), its panel has «زر Vanish» too; and once
  this phone has unlocked them, the main menu shows «أدوات المطوّر».

## Sky, moon icon, grip and weight (the owner's next round)
- **The night sky is his photograph** (`assets/sky/milkyway.jpg`, the Milky Way): `sky.gdshader`
  `night_tex` / `has_night_tex` wraps it round the sky twice, mirrored (no seam), the horizon on its
  bottom edge; the drawn stars are off when it is there; his moon is drawn on top; over it the
  clouds are thinner, wispier and moonlit blue-grey (they used to cover 85%, now 62%) so the Milky
  Way shows through. Camp and every night map. The Empty Quarter's daylight is unchanged.
- **The countdown ring shows the moon on every map** (his moon picture, reddening as time runs out;
  the Empty Quarter too, and «ينزل القمر» in its warning).
- **The pistol sits in the real hand**: `NFGun` now places it from where the hand actually is
  (`bone_at` RightHand / RightForeArm), barrel straight on from the forearm, grip under the palm,
  1.12x. (The characters have no finger bones, so the fingers cannot curl round it.)
- **Weight in the movement** (`main._lean_rig`, every character on every phone): into a turn up to
  ~11° when sprinting, forward when pulling away and in a sprint, back when pulling up; pivots at
  the feet; only in `LEAN_POSES`, never carried / hung / seated / in a car.
- **The car**: roll in a hard fast turn ~7° (was 3), nose dive and tail squat ~5° (was 3), and a hard
  change of speed throws the body on its springs (`_prev_accel`, a threshold so it does not jitter).

## The November batch: «الوحش», Bloom, City Life, ravens, rain, the shot (the owner's next round)
- **«الوحش» (`killer2`)** — a second killer to choose (trial mode: in the character list; online: the
  killer's own stand shows both, `{t:"set", char}` with `KILLERS` in `server.js`). His sculpt is
  hunched with a tail, not a T-pose, so it went through **`rig_character.py --pose JOINTS.json`**
  (`tools/rig/monster_pose.json`, joints read off a grid render): the rest pose is still the donor's
  T-pose with his bone lengths (the clips play as on everyone), the bind pose is his posture, the
  weights go by the nearest bone segments (the tail rides on the hips). `scripts/hunch_mod.gd`
  (`NFHunch`, the first modifier on his skeleton) bends his back, lifts his head, bends his knees and
  sinks his hips over every clip; `CharacterRig.play` turns it off for seats, hooks and dying. When a
  chase starts he screams (`assets/sfx/scream_beast.mp3`, from where he is) and the survivors' screens
  shake a little (`main._beast_cry`, 14 s between screams). He uses the male pain voice (`MALE`).
- **Bloom (`survivor9`)** — the Midnight Starfall sculpt, `--sleeves 0.4` (new: past the elbow the arm
  owns the wide sleeve hanging under it) and the legs are now split by the nearer leg centre line
  (boots that touch no longer stretch into a sheet when she runs). Perk «تفتّح» (`mend`, both rules
  files): hurt and not hit again for `MEND_TIME` 45 s, she is back to ok (event `mend`).
- **`tools/pose_sheet.py`**: a pose sheet with no Godot — skins a character GLB with the Mixamo clips the
  way `character_rig.gd` does and splats it front and side. Run it after every rig.
- **City Life (`city`)**: 24 shop-front blocks (the village's buildings in concrete) on a grid of streets
  (`CITY_ROWS` / `CITY_COLS`, `on_street`), a tower over each (two MultiMeshes, world-space triplanar
  window textures, occluders), neon signs (one MultiMesh) with a little coloured light on the
  pavement, street lamps, his cars, and **his cyberpunk city model (`assets/props/city_skyline.glb`)
  six times round the outside as the skyline** (three on older phones). Same objectives as every map.
  In the room's map picker, `MAPS` in `server.js`, the loading picture, and a dressing in the camp.
- **His props everywhere** (`world._build_owner_props`, `owner_props`): the world-tree and the outpost in
  the forest, cars (ruined, vintage) in the village, fareej and city, crystal lantern trees (cold
  glow and light), the galleon run aground on the beach, saguaro cactus in the Empty Quarter, and his
  grass clumps (`_grass_chunks`: 4x4 chunks of MultiMesh, each culled past 55 m). The camp
  (`NFLobby._build_owner_models`) has the quiet nun crouched at the edge of the light, a raven on the
  ground and one in the lantern tree, the outpost and the great tree behind, and his grass round it.
- **Ravens** (`scripts/ravens.gd`, `NFRavens`): 7 perch on the gallows posts and the roofs (4 on older
  phones), 3 circle high; anyone within 8 m makes one take off; flapping wings are added in code
  (the model's are folded). His sounds: **crow caw when the bird is within 20 m of me, the raven's call
  when it is further**. None in the car park.
- **Rain sound**: `assets/sfx/rain.ogg` (his clip, loudness-matched, crossfaded into a seamless loop),
  on the Music bus while the weather is «مطر», quieter under the car park's slab.
- **The pistol's shot** (`main._beam`): his gunshot (`assets/sfx/gunshot.mp3`, the first of the shots in
  his clip), a muzzle flash and a 60 ms light, the bullet as a streak of fire flying to the target,
  smoke from the barrel that hangs and rises, a brass case thrown out, sparks where it hit, the stun's
  blue on a hit, a stronger kick. `NFDecor.burst()` makes the one-shot particles.

## The optimisation pass (the owner's checklist)
- **Occlusion culling** was already on (`use_occlusion_culling`); walls without openings carry box
  occluders, and now the city's towers too (`world.occluders` counts them).
- **Visibility ranges by size** (`world._apply_view_ranges`, re-run on every settings change): under
  1.6 m stops at half the preset's view distance (max 70 m), the rest at the view distance —
  `Gfx.VIEW`: Low 80, Medium 110, High 150, Ultra 200 (x0.85 on older phones). Only for things under
  30 m across (Godot measures to the middle of an instance). The "far" group is left alone.
  His grass clumps are chunked (HLOD-style: each chunk culled on its own).
- **LOD**: the GLBs are imported with Godot's automatic LODs (the default, no `.glb.import` is
  committed); `mesh_lod_threshold` goes 0.7 / 1.0 / 2.0 (older phones) / **3.0 on «منخفض»**.
- **Animation**: `CharacterRig.set_anim_rate(every)` — main poses a remote's skeleton every frame near
  and in view, every 2nd at 30-70 m, every 4th further, every 6th behind the camera (the skipped
  time is handed on, so the clip does not drift).
- **«منخفض»** — a fourth graphics preset (stored as 3, listed first): Medium's settings plus a shorter
  view, simpler models sooner and textures one mip softer (`texture_mipmap_bias` 0.6).
- **«مراقب الأداء»** in the settings: FPS, frame time, draw calls, objects, triangles, static and
  video memory, CPU time (Godot's own counters). Off, the corner shows the one FPS line it always did.
- `tools/city.tscn` tests all of it; `tools/shot23.tscn` photographs it.

## «مدينة الكويت» (Kuwait City, `kuwait`) — the owner's reference picture of the Gulf Road
- Laid out from his picture, without the far skyline: the **Gulf Road** north-south through the
  middle (`KW_ROAD_HALF` 16 m each side: his twin-highway tile stretched to 64 m long), the **median** of his
  grass planters end to end with palms every 20 m, his grass patches and tufts all along it and round
  every tree, twin-head street lights between the palms; **sidewalks** (his lamp-lit tile every 19 m,
  `KW_WALK` 5.8 m) with emerald canopies outside them, bins and his road signs; the **National
  Assembly** (`KW_ASSEMBLY`, 80 x 46 m, lit from its feet, an occluder) with lawns and trees on the
  west; a **car park** (`KW_PARK` 24-44 m) of his cars nose-in in two rows with aisles; the **corniche**
  (`KW_PROM`) with palms, benches facing the water, lights and his white car on its deck; **sand**
  (`KW_SAND` 56 m, his sand mounds) and a rock breakwater (his rocks and rock piles) at the water
  (`KW_SHORE` 62 m, the ground drops away under a sea plane, a wading wall at +8 m); the **Kuwait
  Towers** on a rock point to the south-east (`KW_TOWERS`, 90 m: looking south down the road you have his picture — the Assembly on the left, the sea and the towers on the right; blue lights in the spheres, warm floodlights at the
  base) and his warship at anchor. Traffic lights at the middle crossing, jersey barriers at the gate
  ends. The gates are the two ends of the road. No fortress wall on the sea side. The market sits
  behind the Assembly (north-west), 8 kiosks carry the lockers, doors and generators. The pieces are
  `assets/props/kw_*.glb` (prop_bake, `--soft` for grass, leaves and the cars), drawn as MultiMeshes
  through `world._kw_many` (one draw call per sub-mesh, optional box hulls). In snow his frost
  crystals hang glowing on the median lights. His locker model is `assets/props/locker.glb`, so it is
  every map's locker now.
- **The power box** (`world.power_box`, `KW_BOX` on the west sidewalk, his rusty control panel over a
  code-built cabinet, a lamp on top green / red): every street light of the map is on it (`_grid_light`,
  `_amb_light(..., on_grid)`, and the lamps' glow maps in `grid_mats`). The killer's interact button
  there is «اقطع الكهرباء» (`cut`); then survivors hold «صلّح الكهرباء» (`pfix`, `GRID_FIX` 12 s alone,
  faster together, points like a generator). Both rules files (`has_grid`, `grid`, `grid_p`,
  `grid_reps`; event `grid {on}`; snapshot `pb`); the server knows the box from `layout.b` and checks
  the distance. On every map view the box is a ⚡ square, yellow, blinking red while cut, with its
  name on the big map and in the legend. Feed lines and a flash for each side.
- `tools/kuwait.tscn` tests it; `tools/shot24.tscn` photographs it from the picture's angle.
- **Bloom's face** (the owner: "raise the details of Bloom's face"): her sculpt's face is 70k triangles
  and it shared the head's budget with her hair, so the round model kept a few hundred of them (a
  faceted nose, flat lips and eyelids). Re-rigged with her own face budget, like «حارسة الليل»:
  `python3 tools/rig_character.py bloom.glb assets/chars/survivor9.glb --faces 30000 --tex 2048
  --face-faces 9000 --chest 0.12 --hair 85 --sleeves 0.4 --arms 0.235,0.49,0.745 --hair-density 0.85
  --fringe --bake --external` (40k triangles) and `... survivor9_hi.glb --faces 100000 --tex 4096
  --face-faces 40000 ...` (140k; the bake is within 0.4 mm of the sculpt on average). The light
  streaks on her fringe and the grey on her nose tip are in the sculpt's own colours. Her skin masks
  (`survivor9[_hi]_skin.png`) are new: she had none, so no subsurface skin until now.
  **`tools/face_shot.py OUT.png a.glb b.glb[@yaw]`** renders a head front on with no Godot (colour,
  colour lit by the mesh, the bare mesh) to compare a rig's face with its sculpt.
- **Bloom's hands**: re-rigged with `--arms 0.235,0.49,0.745` (her bare shoulders and wide sleeves
  fooled the automatic arm fit, which put the shoulder joint at 0.315 m and turned the hands out).

## Kuwait City, second pass, and Halloween (the owner's next round)
- **The road is built in code now** (his twin-highway tile sat 0.67 m thick, so cars sank into it, and
  stretched it looked poor): fine asphalt flush with the ground the cars roll on, three lanes each way
  (dashed lines, solid edges, a yellow inner line), zebra crossings at z 0 and ±64, granite kerbs.
- **Raised walks** (`_paver_mat`: pavers drawn in code — rows of stones each a shade different, sunken
  grout, a normal map from it, world-space at 2 m a tile; warm stone on the corniche): sidewalks 15 cm,
  median 20 cm (ends at `KW_MEDIAN` 92 m, clear of the gates), promenade 20 cm. Each is a `_kerb_body`:
  a top box plus a 0.5 m **ramp of collision** on both long sides, so feet and tyres ride up the kerb,
  and `main._kerb_ctx` lights the **jump button** at every kerb edge (`world.kerbs`).
- **Street lights burn yellow**: his twin-head lights along both kerbs, the median and the corniche,
  each head a glowing lamp (`KW_HEADS` / `KW_HEAD_Y`, measured off the model) and a yellow light on the
  power grid. **Trees every 4 m** down both sides of the street (6 m on older phones). Grass and
  planters only along the median, never near the gates.
- **The mosque** (`assets/props/kw_mosque.glb`, his Golden Crescent Mosque, 34 m) replaces the market
  (the shops, the restaurant, the dry cleaner's: `_build_market` is skipped there), set back so the two
  generators stand on its forecourt; its two lockers stand either side; no market door or window.
  Gold on the map, «المسجد».
- **Yellow light inside the Assembly** (two rows of warm lights behind the glass).
- **The power box**: his panel at 1.25x with a yellow work lamp; **cut twice a round at most**
  (`GRID_CUTS` 2) and **not again until 60 s after the repair** (`GRID_GAP`; both rules files; `pb` now
  carries the cuts and the wait). While it is out the ambient falls to 30% and the moon to 35%: only
  the torches help. The killer's button reads «اقطع الكهرباء (1/2)», and a line says how long it cools.
- **The pistol moves**: drawn up from the hip when it comes out, swings with the stride at low ready
  (`NFGun.spd`, set by main for me and for every remote), sways with breathing while aimed (more on
  the move), recoil as before.
- **Halloween is darkness, not red**: neutral ambient at 0.22, a faint grey moon, dark grass and leaves;
  `set_blackout(true)` for the whole round (it ignores being turned back on), so every street, house
  and market lamp is out and only the torches and the pumpkins light anything. **His pumpkin**
  (`assets/props/pumpkin.glb`) is everywhere: 70 about the map (40 on older phones), by every door,
  generator and hook, and down both escape roads — one MultiMesh, a light in every third
  (`pumpkin_lights` are spared by the dark).

## Kuwait City's lights, matched to the owner's photograph
- **Sodium gold** (`NightWorld.KW_SODIUM`): every street-light head throws a **cone straight down**
  (`_street_cone`, a `SpotLight3D` on the power grid), so the asphalt gets warm pools under each lamp
  and darker road between them, as in his picture. The heads glow hot enough to bloom, and each
  carries a soft glare billboard (`grid_glare`, one MultiMesh) that goes with the power and the dark.
- The median's palms and every other corniche palm are **uplit from their feet** (`_uplight`).
- `_kw_look()` (not on Halloween): navy shadows and fog, ambient and moon at ~0.6 of the theme's,
  stronger bloom (threshold 0.85), a touch more saturation and contrast.
- `_amb_light` takes any `Light3D` now (spots included; only omnis flicker).
- **The long ground pieces are cut into 16-32 m pieces** (`_strip`; the markings in 32 m chunks):
  the Mobile renderer lights a mesh with its 8 nearest lights only, so one 224 m road was lit by
  8 lamps. All the ground materials are world-space, so the cuts do not show.
- Kuwait City's air: thin flat fog (x0.35), the moon lights no volumetric fog (no blue haze), the moon at 0.75 of the other maps'. `_kw_look` runs its one-off part once (`_kw_set`). The camp's moon is x0.6 too.

## Blood (`scripts/blood.gd`, `NFBlood`; the owner's three Meshy models)
- His models, through `prop_bake.py` (new switches `--pitch` to lay a sculpt from the XY plane flat
  and `--keep` to take one piece out of a sheet of them): `assets/props/blood_pool.glb` (his splash /
  puddle, 2.6k triangles, 1 m), `blood_smear.glb` (his drag trail, laid flat with `--pitch -90`) and
  `blood_drop.glb` (the big teardrop out of his sheet of drops, `--keep`, 300 triangles).
- **One `NFBlood` per round** (`main.blood`, made when the map is ready, under the world): **drops** are
  his droplet in one MultiMesh (`max_drops` 48, 24 on older phones), simulated on the CPU with gravity
  and drag, tail up the way they came, **one physics ray per drop per step** (the local player's own
  capsule excluded) — where a drop lands it leaves a mark on that surface. **Marks** are three
  ring-buffered MultiMeshes (`caps`: pool 110, smear 40, wall 30; about half on older phones) drawn
  with `shaders/blood.gdshader`: per instance (INSTANCE_CUSTOM) how far it has spread, how dry it is,
  how much is left and a seed. Fresh: dark crimson, glossy, its surface moving a little; then it dries
  dark brown, matte and flat from 30% of `MARK_LIFE` (80 s) and dithers away over the last 15%. A drop
  that lands on a fresh pool makes that pool spread instead of adding a spot (so blood gathers under
  someone standing still). Opaque (dithered fade), no shadows, no node made after `setup()`.
- `bleed(name, feet, kind, cam)` every frame for every survivor on every phone (`main._blood_trail`):
  hurt = drips from the wound, slow while still, now and then walking, often (two at a time) running,
  with the runner's speed so they land along the path; running hard also smears now and then. Down =
  a smear every 0.65 m as they crawl. Fine, healed, hooked (the hook keeps its own drip and pool, now
  his droplet and his puddle), dead, out, in a car or vanished = nothing. Further than 45 m from the
  camera the drop is not flown: its mark is laid where it would land.
- `splash(at, dir, cam)` on every blow (`main._slash`): a spray out of the far side, a splash on a wall
  within 2.6 m behind them (ray), a pool spreading under them, plus the old GPU mist.
- `tools/city.tscn` tests it (drops in the air, landing, on the ground, along the path, spreading,
  drying, fading, a wall, the crawl smear); `tools/shot25.tscn` photographs it.

## The power box everywhere, the old Halloween dark, and «بين العصر والمغرب»
- **A power cut is the old Halloween night, exactly** (`NightWorld.DARK_*`: ambient (0.09, 0.09, 0.11)
  at 0.44, a grey moon at 0.14, black fog): `set_grid(false)` tweens to it and back (`_lit` keeps the
  night's own colours), on every map with a box; lightning and the blackout event keep to it.
- **Halloween**: every light is **on** to begin with (no more permanent blackout) on a grey night;
  every map has a power box (`world.has_power_box()`, `_plan_power_box`: decided in `configure`, in
  front of the market or on a seeded free spot, so it goes out with the layout as `layout.b`), and
  **the whole map hangs on it** (`grid_all`: every lamp but the pumpkins, and the market). A
  **survivor** can switch it off («اطفي الكهرباء», input `off`, both rules files, `grid_mode` 1; not
  for 15 s after a repair, `GRID_OFF_GAP`); the killer can still cut it (2 cuts, 60 s apart); anyone
  survivor repairs it as before.
- **«بين العصر والمغرب»** (theme `sunset`, its own row under the weathers, `THEMES` in `server.js`;
  the camp is at dusk while it is picked): `world._step_sunset` every frame from the round's clock
  (`round_t` = `rules.clock`, now in the snapshot as `ck`): the sun (the moon's light and the sky's
  disc, `sun_disc` in `sky.gdshader`, with day / gold / red clouds) goes from 38° to below the horizon
  over `SUNSET_TIME` 300 s — afternoon light, gold, red, dusk — then pitch dark (DARK_*). The street
  lights start **off** (`grid_mode` 2, `Rules.set_grid_mode`; the server reads the room's theme) and
  the whole map hangs on the box: survivors «شغّل أنوار الشارع» (the repair), the killer can cut them
  again. The HUD counts down «☀ المغرب بعد m:ss», a warning a minute before and a call at dark.
  **The sun moves** (down and drifting round, the light and the disc with it), and once it is gone
  **the moon comes up** on the other side of the sky over `MOON_RISE` 150 s (the sky's disc becomes his
  moon picture; its light is cold, and faint — `DARK_MOON_E` — while the power is out). `moon_now`.
- `tools/kuwait.tscn` tests Halloween and the sunset; `tools/shot25.tscn` photographs them.

## «وضع القنّاص» (the sniper mode; Kuwait City only) and the car's headlights
- **The mode**: room option `set {sniper}` (`room.sniper`, `started.sniper`; turning it on sets the map to
  Kuwait City, picking another map turns it off — `server.js`), trial mode `GameMenu.off_sniper`. Both
  rules files (`sniper`, `rules.js` from the room's `opts.sniper`): **one gate** — when the generators
  are done only gate 0 (south, the Kuwait Towers' side) opens, nobody boards road 1's car — and **no
  moon** (`doom` stays -1): the round runs until everyone is dead or out. Input `snipe {n, p}` (the
  killer's phone says whom the bullet hit and where it struck; `SNIPE_CD` 1.2 s, no limit): a
  survivor on their feet is **down at once** (`_down`; «جلد قاسي» does not save them) and bleeds out
  in `BLEED_TIME` unless healed. Event `snipe {by, n, p}`.
- **The tower** (`world._build_sniper_tower`, `world.sniper` set before `configure`, which keeps its
  ground free of objectives): a 30 x 12 x 13 m block across the north end of the Gulf Road in front of
  the shut north gate (`SN_FACE` 96 .. `SN_BACK` 108, `SN_HALF` 15, roof `SN_H` 13), a steel stair
  along its south face — two flights (collision = sloping slabs, 32°; the steps drawn on them as one
  MultiMesh each) with a landing between and one at the roof's corner, a yellow rail and its wall
  on the open side. At the foot a red-and-white barrier on `SN_LAYER` (only survivors' bodies collide
  with it: `main` adds the layer to their mask) and two bollards that keep the cars off. On the roof a
  0.3 m parapet (lying down she sees over it) with an invisible 2.2 m edge on `SN_EDGE` (bodies only:
  the rifle's ray and the bot's sight use layer 1), sandbags, a water tank, an AC unit, a mast with a
  red light, two landing lamps, and **the rifle on its crate** (`snipe_rifle`, `rifle_stand`).
  `on_stairs(p)`, `on_roof(p)`. The north gate-end barriers are not placed. The killer starts at the
  foot of the stairs (`spawn_point`). Survivors' map: the tower with a red crosshair, the stair line;
  the north gate and its road are not drawn, the gate arrow points only at gate 0.
- **Climbing**: on the stairs the killer moves at 2.2 m/s and plays **`climb`** — made in
  `CharacterRig._climb_anim()` from the walk (thigh swing x1.55 about its average, knee bend x1.7 from
  its straightest key, hip bob x1.6); a `climb.glb` in `assets/anims` would replace it. Her first-person
  eye rises and dips with each step (`main._killer_eye`).
- **The rifle** (`scripts/sniper.gd`, `NFSniper.rifle()`: built in code, bolt-action, scope, bipod):
  «خذ القنّاصة» at the crate → `main.sniping`: she lies down (eye 0.55 m), crawls at 1 m/s (`crawl`,
  frozen when still — every phone freezes a remote crawl under 0.15 m/s), the rifle in her hands in
  first person; attack = «اطلق», power = «سكوب ×4 / ×8 / بدون سكوب» (`scope`, `NFSniper.ZOOMS`; FOV
  /4 and /8, look speed slowed the same, `NFSniper.draw_scope`: black round the eyepiece, posts, a
  fine cross, mil dots, a red point, ×4/×8), interact = «قوم». The shot (`_snipe_fire`): from the
  camera down the middle of the screen, whoever it passes within 0.42 m of (feet to head, nothing in
  between) is hit. Every phone (`_snipe_fx`): the pistol's tracer and flash (`_beam`) plus the
  rifle's crack (his gunshot at 0.62 pitch, heard across the map), blood on whoever it dropped,
  «انقنصت!» and a hard shake for them, «رصاصة جنبك!» for a near miss. Other phones see her lying
  with the rifle in front of her (`r.rifle`), and the crate empty.
- **The computer killer** (`NFBot._sniper`): walks the navigation mesh up the stairs to the rifle,
  then lies along the front of the roof crawling slowly side to side, and every 2.6-4.8 s fires at the
  nearest survivor she has a clear line to (hit chance 0.6 - distance/450, at least 0.15).
- **The car's headlights** (`NFCar`): the light used to sit inside the bonnet, so with shadows on the
  car's own body blacked it out. Now a wide low beam (`lights`, 40°, 55 m, 22) and a narrow long one
  (`beam`, 15°, 95 m, 30) start in front of the bumper; the lamps glow (additive billboards, with a
  2 m glare seen from far off — hidden from the driver's seat) and the tail lamps glow red.
- `tools/sniper.tscn` tests it; `tools/shot26.tscn` photographs the tower, the stairs, her view, both
  scopes and the headlights in the dark.

## The online fix (November: "generators and hits do nothing online")
- **The cause**: the Vanish change replaced the `"ev":` line in `main._on_net` with its own line, so the
  server's `ev` messages (the snapshot `gs` and every event) fell inside the `st` branch and were never
  read: positions moved, nothing the rules decided reached any phone. Restored; never fold a `match`
  branch into the one above it.
- **Server hardening** (`server.js`): every handler and every room's tick run inside try/catch (one
  bad message or room cannot take the server down); a socket that misses a ping (15 s) is closed; a
  phone coming back after a dropped connection takes its own name over (`STALE_MS` 6 s silent, or the
  same address) instead of getting «name taken» — and `Net` retries its own name a few times instead
  of stopping for good; an oversized layout is cut, not refused (a refused layout meant no rules at
  all); `maxPayload` 64 KB.
- **A struck survivor lets go** of repair / heal / unhook / the power box on their phone too
  (`_end_hold()` on my `hurt` and `snipe`): the rules had already dropped it.
- **CI online round** (`check.yml`): the real server, this game headless (`tools/online.tscn`,
  `NF_MODE` forest / forest-surv / kuwait-sniper) and a second phone in node (`tools/online_bot.js`),
  with `O ok` / `O FAIL` checks; its output is at the top of `all.log` on `check-log`. Manual runs take
  `tests`, `shots`, `shotlist` and `online` inputs; push with `[skip ci]` when dispatching.
- **The sniper stairs**: physics stopped her at the landing every time, so the killer and the
  computer killer now walk the stair line itself (`world.stair_y` / `stair_step`); the walk surface
  is on `SN_EDGE` (bodies only) so bullets pass over the top landing.
- **Stable checkpoint 2026-11-26: commit `5997812` on main** (the online fix and hardening, the sniper
  mode finished). All headless tests and the three online rounds passed on CI; nothing yet on phones.
  Tags cannot be pushed from the agent's machine (the proxy refuses them): tag it on GitHub if wanted.
  Known flaky test: `drive`'s garage leg ("drove down the ramp") fails when the roof car is placed
  turned away from the ramp (its spot depends on where the roof generator and hook fell).

## The November batch, second round (the owner's list)
- **Sunset** over four minutes (`SUNSET_TIME` 240). **No chase music while vanished.** **Gate countdown**:
  `GATE_DELAY` 10 s after the last generator before the gates get power (`gate_t`, snapshot `gt`; tests
  set `rules.gate_delay = 0`), shown on the HUD (`main._draw_gate_count`).
- **The sea** (`shaders/ocean.gdshader`, `world.ocean_mat`, `wave_y`): Kuwait City's sea and the beach's
  lagoon on subdivided planes with moving waves.
- **Kuwait City** (`world._build_kw_extras`, `_step_kw`): his billboard with his ad picture always on
  (`AdScreen`), his promo video (`assets/ads/promo.ogv`, Theora: Godot plays nothing else) only from the
  developer tools' button, for everyone (`{t:"ad", on}` relayed by the server); the police cars with
  their light bars on and the siren (`assets/sfx/siren.ogg`) only once the gates open
  (`world.set_sirens`); a bus stop, drains, boats along the coast; his new cars in the parking, never two
  of a kind side by side.
- **His new rifle** in the sniper mode (the scope is unchanged).
- **«المسعف»** (perk `aid`): a player picks it on the character page (`Net.perk`, sent with `set {perk}`);
  it replaces the character's own perk and he carries the first-aid kit: heals others at `AID_MUL` 2x,
  heals himself in `AID_SELF` 8 s and keeps the kit.
- **The rescue helicopter** (`scripts/heli.gd`, `NFHeli`; both rules files, snapshot `hl`): when one
  survivor is left it flies to `world.heli_spot` and lets a rope ladder down; climbing (`ladder`) takes
  `CLIMB_TIME`, the killer cannot hit past `CLIMB_SAFE`; downed before the ladder, it leaves.

## The cat and the dog (`scripts/animal.gd` `NFAnimal`, `scripts/catdog.gd` `NFCatDog`)
- His two Meshy models (no skeleton) went through `prop_bake.py` and then **`tools/rig_animal.py`**:
  `python3 tools/rig_animal.py baked.glb tools/rig/<cat|dog>_joints.json assets/animals/<cat|dog>.glb`
  (`--sheet out.png` draws the grid pictures the joints are read from). Bones: root, hips, spine1-2,
  chest, neck1-2, head, jaw, tail1-5, each leg top/mid/low/paw; weights by region (legs, tail, head,
  jaw, body), smoothed on the welded surface. `tools/animal_poses.py rig.glb out.png cat|dog` renders
  rest / walk / mouth / sit or stalk / shake with no Godot. Maps moved out with `glb_external.py`
  (ASTC 4x4). Cat 60k triangles, dog 70k.
- `NFAnimal.pose(dt)` animates in code from `speed` (walk / trot / gallop, stride sized from the
  speed), `look`, `sit`, `crouch`, `pounce`, `swipe`, `jaw`, `shake`, `swallow`, `wag`, `limp`.
- `NFCatDog` (made by `main` once the blood is ready): the first generator anyone repairs brings the
  cat (circles the people there, sits, washes, pounces, bats, meows — `assets/sfx/meow0-5.ogg` cut from
  his clip); when that generator is done the dog stalks in from 15 m, freezes, barks
  (`dog_bark.ogg`), sprints, bites (the cat makes no sound: the owner took the scream out), shakes it 2.4 s with his blood
  (`NFBlood.splash`), swallows it over 6 s — `dog_eat.ogg` and, started and stopped with it, his dark
  sound `dog_eat_dark.ogg` (cut from his clip, 2.8-8.8 s) — and runs off. Once a round. **No server change**: it starts from the generators in
  the snapshot, every place and choice comes from `layout_seed` and the generator's number.
  `tools/catdog.tscn` tests it, `tools/shot28.tscn` photographs it.
