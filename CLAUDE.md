# NightFall — project notes for whoever continues the work

Asymmetric horror game (1 killer vs up to 6 survivors, Dead-by-Daylight style) for iPhone.
Owner: Rashid (Arabic UI, plays with friends, installs the IPA with Sideloadly).

## Stack
- **Godot 4.5**, Mobile renderer, everything built in GDScript at runtime (no hand-made scenes; `scenes/main.tscn` only attaches `scripts/main.gd`).
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
- `scripts/menu.gd` (`GameMenu`) — menus: name, main, friends, lobby, character select, trial mode; the player card and the swipe area.
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
- `assets/chars` — the owner's 5 characters (SF3D meshes rigged to the Mixamo skeleton). `assets/sfx` — the owner's sounds (mp3) plus synthesized ones (wav).
- `tools/*.gd|tscn` — headless tests (not exported).

## Protocol (JSON over WebSocket)
`hello`, `friends`, `create`, `join`, `leave`, `set`, `invite`, `start`, `lobby`, `layout` (object positions from clients), `st` (position/anim/flashlight, relayed), `ev` (player input → server; server → everyone as `{t:"ev", n:"", d:event|snapshot}`).
`ev` input `door` (`{k:"door", i, on}` → the server checks you are next to it and sends `{k:"door", i, on, by}` to the room).
`emote` (`{t:"emote", k:0..2}` → the server sends `{t:"emote", n, k}` to the rest of the room; campfire only).
`sig` (quick signal: `{t:"sig", k:0..2, p:[x,z]}` → the server relays `{t:"sig", n, k, p}` **to the sender's own side only**, so a survivor signal never reaches the killer).
Inputs (`d.k`): rep, skill, escape, hit, pickup, hook, rescue, struggle, heal, locker, search, pallet, break, power, door. Snapshot key `gs`.
Snapshot also carries `dr` (door states), `ek`/`et`/`en` (the round's event, seconds left, the survivor the alarm gives away) and `ad` (the call to prayer: 0 not yet, 1 playing, 2 done). The clients send the doorway positions in `layout.d`.

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
- Characters `survivor2/5/6/7` come from the owner's untextured Meshy sculpts (0.8–2.2 M tris): painted by body zones, decimated to 26k tris with baked colour+normal maps, rigged like the others. Blender's JPEGs inside the GLB must be re-encoded with Pillow or Godot fails to load them.

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
Every map keeps the same skeleton: perimeter wall, two gates with a long escape road, the market, 7 generators,
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
Locked by default. On a phone that has them, a small panel appears during a round with two switches:
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

## Known gaps
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
