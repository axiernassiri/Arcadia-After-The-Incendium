# Skyfall 3D island overhaul

The 3D Skyfall mode (`V` or the Globe control) uses live Godot meshes rather than a picture or a flattened/extruded copy of the 2D map. The terrain and index PNGs remain the authoritative source of island positions, province ownership, and clickable UVs; the strategic 2D map is untouched.

## Visual changes

- Each separate land mass gets its own deterministic altitude (rear islands float higher; the wide foreground landmass sits lower).
- The exposed coast has an overhanging stone rim, a mossy ledge, irregular rock sides, and an actual sculpted underbody. A coast-distance field and procedural noise shape the underside and pointed rock spires.
- Grassy top surfaces have subtle 3D rises, layered green/soil shader detail, and instanced stone outcrops.
- Some cliff rims have hanging ivy and animated waterfall ribbons. These are combined into only a few meshes and one stone MultiMesh.
- The lower Skyfall camera angle shows the cliffs and silhouettes instead of looking almost directly down onto the 2D map.

## Gameplay preserved

- Provinces retain their existing map coordinates and strategic data.
- Raycasting against the 3D terrain collider handles mouseover, left-click and right-click province identification. This replaces the incorrect single-plane intersection used for islands of different heights.
- Political/palette map modes, selected-province highlighting and hover highlighting now apply to the grassy 3D material as well.
- Ground-globe rendering and the 2D map are not modified.
- No external models, asset packs, network access, or add-ons required.

## Files changed

- `scripts/globe_view.gd`: generates the island components, top and underside meshes, rocks, waterfalls and ivy, and handles correct 3D picking.
- `shaders/globe_sky_islands.gdshader`: grass/soil shading and province overlay.
- `shaders/sky_rock.gdshader`: layered rock and moss textures.
- `shaders/sky_water.gdshader`: moving waterfall ribbons.

## Verify in Godot

Open `project.godot` in Godot 4.7 and start or load a game. Switch to Skyfall and press `V`. Orbit and zoom: the islands should have individually elevated, irregular cliff and underside shapes. Hover, select and right-click a province, then switch political/terrain map modes. Move back to the mainland to confirm its globe is unchanged.

*Visual reference:* `skyfall_3d_reference.png` is the requested illustrative target; it is not a texture pasted onto the game. The actual game scenery is rendered from geometry and shaders and will differ in detail from the concept image.
