# The lunar outpost, split into parts

The owner's Meshy model (`export_Meshy_AI_2026-11-28_b7b06b.glb`, one fused mesh of 3,146,738
triangles, one material, a 4096 colour / metal-rough / normal map) split by geometry into ten parts.
Every triangle went to exactly one part, unchanged: same positions, normals, UVs and material.
Each part stays where it stood in the outpost, so loading all ten together rebuilds the whole outpost.
His three maps are copied byte for byte, and every GLB points at them (`outpost_col.jpg`,
`outpost_mr.png`, `outpost_nrm.png`).

| part | triangles |
|---|---|
| platform (the oval base, its rim, ramps and railings) | 1,022,720 |
| dome_lab (the glass dome research facility, with its side module) | 527,002 |
| garage (the vehicle garage) | 344,580 |
| comms_tower | 303,665 |
| corridors (the tunnels between the buildings) | 280,180 |
| energy_storage | 160,503 |
| cargo (containers and equipment on the deck) | 149,326 |
| research_lab | 129,996 |
| dish_station | 124,801 |
| medical (the red-cross building) | 103,965 |

`outpost_full.glb` is the complete outpost (the same triangles, maps beside it). The original upload
is 138 MB, over GitHub's 100 MB limit for one file, so it is not stored here.

The seven buildings are in `assets/props/outpost/` (with the same three maps); the platform, corridors and cargo are here. The game uses the seven buildings, scaled x32 on the
Moon (`world._outpost_buildings`). This folder has a `.gdignore`: Godot does not import it, and it is
not in the IPA. How it was split: `tools/outpost_split.py`.
