# 3D globe + Skyfall cloud archipelago merge

Merged the Skyfall Cloud Archipelago V2 (parser-fixed) project into the
newer official Arcadia repository upload `Arcadia-After-The-Incendium-main (7).zip`.
This updated official project is the base. Its recent multiplayer-save support,
events, diplomacy, UI, tests, and new `tools/farworld_events.py` are preserved.

- New `scripts/globe_view.gd`: 3D mainland globe; sculpted, separated Skyfall
  islands with grass, cliffs, waterfalls, rocks, ivy, interactive provinces.
- New `shaders/globe_*.gdshader`, `shaders/sky_*.gdshader` and starfield shader.
- Small integration patches to `scripts/main.gd`, `scripts/map_view.gd`,
  `scripts/ui/map_controls.gd`, `scripts/ui/help_overlay.gd`.
- Official doomsday API compatibility: use `Game.doomsday_active` for 3D visual tint.
- No changes to original 2D map textures, game data, `Game.act` and multiplayer systems.

## Use
Open `project.godot` in Godot 4.7. Start a game, then press **V** or use
**3D View** in map controls. **Tab** switches mainland and Skyfall. Skyfall
uses a warm cloud ocean and volumetric floating island meshes. Hover/click
landmasses to interact with provinces; right-click for province actions.

## Validation
Compared all files against the latest uploaded official archive. Only the four
existing integration files (`scripts/main.gd`, `scripts/map_view.gd`,
`scripts/ui/map_controls.gd`, `scripts/ui/help_overlay.gd`) were modified;
17 new 3D renderer, shader and documentation files were added. All unrelated
files (including official gameplay updates and the new farworld-events tool)
remain byte-for-byte identical to the newer source upload. All `res://`
references resolve. ZIP contents and extraction have been checked.
Godot runtime rendering, physics picking and multiplayer still need an
in-engine verification before release.
