extends Control
## Playable 3D perspective on the same world: equirectangular globe for the mainland,
## floating, raised island meshes for Skyfall. Uses the original province index for picking.

signal province_clicked(id: int)
signal province_right_clicked(id: int)
signal province_hovered(id: int)

const RADIUS := 4.5
# The original rectangular artwork is not a polar equirectangular map.
# Reserve ocean caps instead of collapsing the artwork into needle-like poles.
const GLOBE_POLAR_PAD := 0.11
# The Skyfall islands occupy a much wider 3D play space than their 2D atlas.
const SKY_WIDTH := 23.0
const SKY_HEIGHT := 12.56
const SKY_Y := 1.10
const TILE := 6  # Coastline sampling resolution in source-map pixels

var layer := "ground"
var _view: SubViewport
var _camera: Camera3D
var _screen: TextureRect
var _planet: MeshInstance3D
var _atmosphere: MeshInstance3D
var _sky: Node3D
var _cloud: MeshInstance3D
var _cloud_far: MeshInstance3D
var _starfield: MeshInstance3D
var _environment: Environment
# Each connected island has its own visual size and offset. Original atlas UVs,
# province IDs and game state remain unchanged.
var _sky_region_centres: Array[Vector2] = []
var _sky_region_scales: Array[float] = []
var _sky_region_offsets: Array[Vector2] = []
var _sky_region_flights: Array[float] = []
var _sky_component_ids := PackedInt32Array()
var _sky_cols := 0
var _sky_rows := 0
# Original atlas UVs for every collider triangle: correct province selection
# even on enlarged / displaced sky islands.
var _sky_pick_vertices := PackedVector3Array()
var _sky_pick_uvs := PackedVector2Array()
var _world_materials := {}
var _cloud_material: ShaderMaterial
var _sky_material: ShaderMaterial
var _rock_material: ShaderMaterial
var _water_material: ShaderMaterial
var _atmos_material: ShaderMaterial
var _indexes := {}
var _terrain_images := {}
var _yaw := 0.0
var _target := Vector3.ZERO
var _pitch := 0.22
var _distance := 13.2
var _press := Vector2.ZERO
var _drag := false
var _holding := false
var _pressed_button := 0
var _hovered := 0
var _selection := -1
var _moon := false


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _view = SubViewport.new()
    _view.size = Vector2i(get_viewport_rect().size)
    _view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _view.own_world_3d = true
    add_child(_view)
    _screen = TextureRect.new()
    _screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _screen.stretch_mode = TextureRect.STRETCH_SCALE
    _screen.texture = _view.get_texture()
    add_child(_screen)

    var world = Node3D.new()
    _view.add_child(world)
    var environment := WorldEnvironment.new()
    _environment = Environment.new()
    environment.environment = _environment
    _environment.background_mode = Environment.BG_COLOR
    _environment.background_color = Color(0.02, 0.03, 0.05)
    _environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    _environment.ambient_light_color = Color(0.42, 0.48, 0.62)
    _environment.ambient_light_energy = 0.72
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-51, -33, 0)
    sun.light_energy = 1.18
    world.add_child(sun)
    _camera = Camera3D.new()
    _camera.current = true
    _camera.fov = 57.0
    world.add_child(_camera)
    for l in ["ground", "sky"]:
        # Load as Texture2D explicitly: `load()` otherwise has the broad Resource type.
        var index_texture: Texture2D = load("res://map/%s_index.png" % l) as Texture2D
        if index_texture == null:
            push_error("Missing province index texture for layer: " + l)
            return
        var index_image: Image = index_texture.get_image()
        if index_image.is_compressed():
            index_image.decompress()
        _indexes[l] = index_image
        var terrain_texture: Texture2D = load("res://map/%s_terrain.png" % l) as Texture2D
        if terrain_texture == null:
            push_error("Missing terrain texture for layer: " + l)
            return
        var terrain_image: Image = terrain_texture.get_image()
        if terrain_image.is_compressed():
            terrain_image.decompress()
        _terrain_images[l] = terrain_image
        var mat := ShaderMaterial.new()
        mat.shader = load("res://shaders/globe_world.gdshader")
        mat.set_shader_parameter("terrain_tex", terrain_texture)
        mat.set_shader_parameter("index_tex", index_texture)
        mat.set_shader_parameter("polar_padding", GLOBE_POLAR_PAD)
        _world_materials[l] = mat
    _planet = MeshInstance3D.new()
    # Godot's tested sphere topology avoids the handmade UV/pole triangle artifacts.
    var planet_mesh := SphereMesh.new()
    planet_mesh.radius = RADIUS
    planet_mesh.height = RADIUS * 2.0
    planet_mesh.radial_segments = 256
    planet_mesh.rings = 128
    _planet.mesh = planet_mesh
    _planet.material_override = _world_materials["ground"]
    world.add_child(_planet)
    _atmosphere = MeshInstance3D.new()
    # The transparent atmosphere shell rendered as a diagonal polygon across the
    # mainland on the Compatibility renderer. Atmospheric rim is now in the globe shader.
    _atmosphere.mesh = null
    _atmos_material = ShaderMaterial.new()
    _atmos_material.shader = load("res://shaders/globe_atmosphere.gdshader")
    _atmosphere.material_override = _atmos_material
    _atmosphere.visible = false
    world.add_child(_atmosphere)
    _sky = Node3D.new()
    world.add_child(_sky)
    _build_starfield(world)
    _build_sky()
    _sky.visible = false
    Game.doomsday_changed.connect(func(_active): _sync_moon())
    Game.game_started.connect(_sync_moon)
    Game.date_changed.connect(_sync_moon)
    _update_camera()
    visible = false


func set_layer(l: String) -> void:
    layer = l
    _planet.visible = l == "ground"
    _atmosphere.visible = false
    _sky.visible = l == "sky"
    if _starfield != null:
        _starfield.visible = false
    _pitch = 0.22 if l == "ground" else 0.47
    _yaw = 0.0
    _target = Vector3.ZERO
    _distance = 13.2 if l == "ground" else 25.0
    _camera.fov = 57.0 if l == "ground" else 50.0
    if _environment != null:
        if l == "sky":
            _environment.background_color = Color(0.98, 0.95, 0.83)
            _environment.ambient_light_color = Color(1.0, 0.94, 0.80)
            _environment.ambient_light_energy = 1.05
        else:
            _environment.background_color = Color(0.02, 0.03, 0.05)
            _environment.ambient_light_color = Color(0.42, 0.48, 0.62)
            _environment.ambient_light_energy = 0.72
    _update_camera()
    _hovered = 0
    province_hovered.emit(0)


func focus_province(id: int) -> void:
    if not Game.provinces.has(id):
        return
    var p: Dictionary = Game.provinces[id]
    if p["layer"] != layer:
        set_layer(p["layer"])
    var centre: Vector2 = p["centre"]
    if layer == "ground":
        var u := centre.x / float(_indexes["ground"].get_width())
        var v := centre.y / float(_indexes["ground"].get_height())
        _yaw = (u - 0.5) * TAU
        var globe_v: float = GLOBE_POLAR_PAD + v * (1.0 - 2.0 * GLOBE_POLAR_PAD)
        _pitch = (0.5 - globe_v) * PI
        _target = Vector3.ZERO
        _distance = minf(_distance, 10.0)
    else:
        var region := _sky_region_at(centre.x, centre.y)
        var flight := SKY_Y if region == 0 else _sky_region_flights[region]
        _target = _sky_pos(centre.x, centre.y, _sky_surface_y(centre.x, centre.y, flight), region)
        _distance = minf(_distance, 16.8)
    _update_camera()


func set_palette(texture: Texture2D, mode: String) -> void:
    for l in _world_materials:
        _world_materials[l].set_shader_parameter("palette_tex", texture)
        _world_materials[l].set_shader_parameter("colour_strength", 0.0 if mode == "terrain" else 0.54)
    if _sky_material != null:
        _sky_material.set_shader_parameter("palette_tex", texture)
        _sky_material.set_shader_parameter("colour_strength", 0.0 if mode == "terrain" else 0.54)


func select(id: int) -> void:
    _selection = id
    for l in _world_materials:
        _world_materials[l].set_shader_parameter("selected_id", id)
    if _sky_material != null:
        _sky_material.set_shader_parameter("selected_id", id)


func _sync_moon() -> void:
    var strength: float = 1.0 if Game.doomsday_active else 0.0
    _moon = strength > 0.0
    for l in _world_materials:
        _world_materials[l].set_shader_parameter("black_moon", strength)
    if _sky_material != null:
        _sky_material.set_shader_parameter("black_moon", strength)
    if _rock_material != null:
        _rock_material.set_shader_parameter("black_moon", strength)
    if _water_material != null:
        _water_material.set_shader_parameter("black_moon", strength)
    _atmos_material.set_shader_parameter("black_moon", strength)
    _cloud_material.set_shader_parameter("black_moon", strength)


func _process(_delta: float) -> void:
    if not visible:
        return
    var size := Vector2i(get_viewport_rect().size)
    if size.x > 0 and size.y > 0 and _view.size != size:
        _view.size = size


func _update_camera() -> void:
    _camera.position = _target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
    _camera.look_at(_target, Vector3.UP)


func _index_at(l: String, x: int, y: int) -> int:
    var img: Image = _indexes[l]
    if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
        return 0
    var c := img.get_pixel(x, y)
    return int(round(c.r * 255.0)) + 256 * int(round(c.g * 255.0))


func _sky_land_at(x: int, y: int) -> bool:
    var img: Image = _terrain_images["sky"]
    if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
        return false
    var c: Color = img.get_pixel(x, y)
    # Skyfall terrain is bright, nearly white islands over a blue sky backdrop.
    return c.get_luminance() > 0.72 and c.b < 0.97


func _sky_pos(x: float, y: float, altitude: float = SKY_Y, region: int = 0) -> Vector3:
    var px := (x / 2000.0 - 0.5) * SKY_WIDTH
    var pz := (y / 1092.0 - 0.5) * SKY_HEIGHT
    if region > 0 and region < _sky_region_centres.size():
        var centre: Vector2 = _sky_region_centres[region]
        var cx := (centre.x / 2000.0 - 0.5) * SKY_WIDTH
        var cz := (centre.y / 1092.0 - 0.5) * SKY_HEIGHT
        var scale: float = _sky_region_scales[region]
        var offset: Vector2 = _sky_region_offsets[region]
        px = cx + (px - cx) * scale + offset.x
        pz = cz + (pz - cz) * scale + offset.y
    return Vector3(px, altitude, pz)


func _sky_region_at(x: float, y: float) -> int:
    if _sky_cols == 0 or x < 0.0 or y < 0.0 or x >= 2000.0 or y >= 1092.0:
        return 0
    var gx := clampi(int(x / float(TILE)), 0, _sky_cols - 1)
    var gy := clampi(int(y / float(TILE)), 0, _sky_rows - 1)
    return _sky_component_ids[gy * _sky_cols + gx]


func _sky_pick_inverse(world_pos: Vector3) -> int:
    # A fallback for cliff faces and physics engines with different face ordering.
    # Unwarp each independent 3D island to its original atlas coordinates.
    for region in range(1, _sky_region_centres.size()):
        var centre: Vector2 = _sky_region_centres[region]
        var offset: Vector2 = _sky_region_offsets[region]
        var scale: float = _sky_region_scales[region]
        var cx: float = (centre.x / 2000.0 - 0.5) * SKY_WIDTH
        var cz: float = (centre.y / 1092.0 - 0.5) * SKY_HEIGHT
        var px: float = (cx + (world_pos.x - cx - offset.x) / scale) / SKY_WIDTH * 2000.0 + 1000.0
        var py: float = (cz + (world_pos.z - cz - offset.y) / scale) / SKY_HEIGHT * 1092.0 + 546.0
        var sample_offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]
        for step in sample_offsets:
            var ix: int = int(px) + int(step.x)
            var iy: int = int(py) + int(step.y)
            if _sky_region_at(float(ix), float(iy)) == region:
                var id := _index_at("sky", ix, iy)
                if id > 0:
                    return id
    return 0


func _add_sky_tri(st: SurfaceTool, pts: Array[Vector3], uv: Array[Vector2], normal: Vector3) -> void:
    for i in range(3):
        st.set_normal(normal)
        st.set_uv(uv[i])
        st.add_vertex(pts[i])


func _build_starfield(parent: Node3D) -> void:
    _starfield = MeshInstance3D.new()
    _starfield.mesh = SphereMesh.new()
    var sphere := _starfield.mesh as SphereMesh
    sphere.radius = 30.0
    sphere.height = 60.0
    sphere.radial_segments = 48
    sphere.rings = 24
    var mat := ShaderMaterial.new()
    mat.shader = load("res://shaders/starfield.gdshader")
    _starfield.material_override = mat
    _starfield.visible = false
    parent.add_child(_starfield)


# Procedural Skyfall mesh.  The source map still controls ownership, UVs and
# province picking, but the islands are volumetric, terraced rock formations.
# Components get distinct flight heights; the distance-to-coast field rounds
# their undersides instead of making uniform-height, square extrusions.
func _sky_hash(x: float, y: float) -> float:
    return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)


func _sky_surface_y(x: float, y: float, flight: float) -> float:
    # Sweeping meadows, low hills and stone terraces: not a flat elevated atlas.
    var broad := sin(x * 0.014 + y * 0.006) * cos(y * 0.016 - x * 0.007)
    var rolling := sin(x * 0.038 + y * 0.021) * sin(y * 0.035 - x * 0.012)
    var detail := sin(x * 0.082 + y * 0.034) * cos(y * 0.075)
    return flight + 0.19 * broad + 0.075 * rolling + 0.023 * detail


func _sky_surface_normal(x: float, y: float, flight: float, region: int) -> Vector3:
    var scale: float = _sky_region_scales[region]
    var rise_x := (_sky_surface_y(x + 3.0, y, flight) - _sky_surface_y(x - 3.0, y, flight)) / (6.0 * SKY_WIDTH / 2000.0 * scale)
    var rise_z := (_sky_surface_y(x, y + 3.0, flight) - _sky_surface_y(x, y - 3.0, flight)) / (6.0 * SKY_HEIGHT / 1092.0 * scale)
    return Vector3(-rise_x, 1.0, -rise_z).normalized()


func _sky_bottom_y(x: float, y: float, flight: float, coast: float) -> float:
    # Broad rocky belly with sharp downward fingers and a shallow cliff rim.
    var interior := smoothstep(0.0, 10.0, coast)
    var strata := sin(x * 0.086 + y * 0.033) * cos(y * 0.097 - x * 0.029)
    var spear := pow(maxf(0.0, sin(x * 0.073 + y * 0.018) * sin(y * 0.063 - x * 0.037)), 5.0)
    var depth := 0.48 + 0.94 * interior + 0.23 * strata + 0.67 * spear * (0.35 + 0.65 * interior)
    return _sky_surface_y(x, y, flight) - maxf(0.34, depth)


func _sky_is_land(mask: PackedByteArray, gx: int, gy: int, cols: int, rows: int) -> bool:
    return gx >= 0 and gy >= 0 and gx < cols and gy < rows and mask[gy * cols + gx] != 0


func _sky_coast_at_vertex(gx: int, gy: int, region: int, ids: PackedInt32Array, coast: PackedInt32Array, cols: int, rows: int) -> float:
    var d := 0
    for dy in [-1, 0]:
        for dx in [-1, 0]:
            var px: int = gx + int(dx)
            var py: int = gy + int(dy)
            if px >= 0 and px < cols and py >= 0 and py < rows:
                var i := py * cols + px
                if ids[i] == region:
                    d = maxi(d, coast[i])
    return float(d)


func _sky_bottom_vertex(gx: int, gy: int, region: int, flight: float, ids: PackedInt32Array, coast: PackedInt32Array, cols: int, rows: int) -> Vector3:
    var x := float(mini(gx * TILE, 2000))
    var y := float(mini(gy * TILE, 1092))
    var d := _sky_coast_at_vertex(gx, gy, region, ids, coast, cols, rows)
    return _sky_pos(x, y, _sky_bottom_y(x, y, flight, d), region)


func _add_sky_top_tri(st: SurfaceTool, pts: Array[Vector3], texcoords: Array[Vector2], flight: float, region: int) -> void:
    for i in range(3):
        var x := texcoords[i].x * 2000.0
        var y := texcoords[i].y * 1092.0
        st.set_normal(_sky_surface_normal(x, y, flight, region))
        st.set_uv(texcoords[i])
        st.add_vertex(pts[i])
        _sky_pick_vertices.append(pts[i])
        _sky_pick_uvs.append(texcoords[i])


func _add_sky_rock_tri(st: SurfaceTool, pts: Array[Vector3], direction: Vector3, moss: Array[float]) -> void:
    var normal := (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
    if normal.dot(direction) < 0.0:
        normal = -normal
    for i in range(3):
        st.set_normal(normal)
        st.set_color(Color(moss[i], 0.0, 0.0, 1.0))
        st.add_vertex(pts[i])


func _add_sky_cliff(st: SurfaceTool, p: Vector3, q: Vector3, pb: Vector3, qb: Vector3, outward: Vector3) -> void:
    # Mossy lip, stepped ledges, sharply receding stony sides.
    var rim_p := p.lerp(pb, 0.16) + outward * 0.13
    var rim_q := q.lerp(qb, 0.16) + outward * 0.13
    var mid_p := p.lerp(pb, 0.54) + outward * 0.035
    var mid_q := q.lerp(qb, 0.54) + outward * 0.035
    _add_sky_rock_tri(st, [p, rim_p, q], outward, [1.0, 0.83, 1.0])
    _add_sky_rock_tri(st, [q, rim_p, rim_q], outward, [1.0, 0.83, 0.83])
    _add_sky_rock_tri(st, [rim_p, mid_p, rim_q], outward, [0.83, 0.16, 0.83])
    _add_sky_rock_tri(st, [rim_q, mid_p, mid_q], outward, [0.83, 0.16, 0.16])
    _add_sky_rock_tri(st, [mid_p, pb, mid_q], outward, [0.16, 0.0, 0.16])
    _add_sky_rock_tri(st, [mid_q, pb, qb], outward, [0.16, 0.0, 0.0])


func _add_waterfall_strip(st: SurfaceTool, anchor: Vector3, width: float, drop: float) -> void:
    # Animated, two-sided water ribbons. The fades are in sky_water.gdshader.
    for segment in range(5):
        var v0 := float(segment) / 5.0
        var v1 := float(segment + 1) / 5.0
        var sway0 := sin(v0 * 7.0 + anchor.x * 9.0) * 0.018 * v0
        var sway1 := sin(v1 * 7.0 + anchor.x * 9.0) * 0.018 * v1
        var a := anchor + Vector3(-width * (0.5 - 0.09 * v0) + sway0, -v0 * drop, 0.0)
        var b := anchor + Vector3(width * (0.5 - 0.09 * v0) + sway0, -v0 * drop, 0.0)
        var c := anchor + Vector3(-width * (0.5 - 0.09 * v1) + sway1, -v1 * drop, 0.0)
        var d := anchor + Vector3(width * (0.5 - 0.09 * v1) + sway1, -v1 * drop, 0.0)
        _add_sky_tri(st, [a, b, c], [Vector2(0, v0), Vector2(1, v0), Vector2(0, v1)], Vector3(0, 0, 1))
        _add_sky_tri(st, [b, d, c], [Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)], Vector3(0, 0, 1))


func _add_sky_vine(st: SurfaceTool, anchor: Vector3, length: float) -> void:
    # Thin falling ivy silhouettes with small leaves, batched in a single mesh.
    var tip := anchor + Vector3(0.018 * sin(anchor.x * 13.0), -length, 0.01)
    var width := 0.011
    _add_sky_tri(st, [anchor + Vector3(-width, 0, 0), anchor + Vector3(width, 0, 0), tip], [Vector2.ZERO, Vector2.RIGHT, Vector2(0.5, 1)], Vector3(0, 0, 1))
    var mid := anchor.lerp(tip, 0.52)
    _add_sky_tri(st, [mid + Vector3(-0.03, 0.02, 0.0), mid + Vector3(0.028, 0.012, 0.0), mid + Vector3(0, -0.07, 0)], [Vector2.ZERO, Vector2.RIGHT, Vector2(0.5, 1)], Vector3(0, 0, 1))


func _build_sky() -> void:
    var cols := int(ceili(2000.0 / float(TILE)))
    var rows := int(ceili(1092.0 / float(TILE)))
    var count := cols * rows
    _sky_cols = cols
    _sky_rows = rows
    _sky_pick_vertices.clear()
    _sky_pick_uvs.clear()
    var mask := PackedByteArray()
    mask.resize(count)
    for gy in range(rows):
        for gx in range(cols):
            var cx: int = mini(gx * TILE + int(TILE / 2), 1999)
            var cy: int = mini(gy * TILE + int(TILE / 2), 1091)
            mask[gy * cols + gx] = 1 if _sky_land_at(cx, cy) else 0

    # One connected component is one flying landmass, not one rectangular sheet.
    var ids := PackedInt32Array()
    ids.resize(count)
    var flights: Array[float] = [SKY_Y]
    var sizes: Array[int] = [0]
    _sky_region_centres = [Vector2(1000, 546)]
    _sky_region_scales = [1.0]
    _sky_region_offsets = [Vector2.ZERO]
    var queue: Array[int] = []
    for start in range(count):
        if mask[start] == 0 or ids[start] != 0:
            continue
        var region := flights.size()
        queue.clear()
        queue.append(start)
        ids[start] = region
        var head := 0
        var amount := 0
        var total_x := 0.0
        var total_y := 0.0
        while head < queue.size():
            var cell := queue[head]
            head += 1
            amount += 1
            var gx := cell % cols
            var gy := int(cell / cols)
            total_x += float(gx * TILE + TILE / 2)
            total_y += float(gy * TILE + TILE / 2)
            for delta in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
                var nx: int = gx + delta.x
                var ny: int = gy + delta.y
                if _sky_is_land(mask, nx, ny, cols, rows):
                    var ni := ny * cols + nx
                    if ids[ni] == 0:
                        ids[ni] = region
                        queue.append(ni)
        var centre := Vector2(total_x / float(amount), total_y / float(amount))
        var latitude := centre.y / 1092.0
        var variation := (_sky_hash(float(region), 42.0) - 0.5) * 0.28
        var flight := SKY_Y + 0.72 * (1.0 - latitude) + variation
        if amount > 4000:
            flight -= 0.21  # Huge foremost landmass hovers beneath distant islands.
        flights.append(flight)
        sizes.append(amount)
        _sky_region_centres.append(centre)
        var smallness := clampf((1400.0 - float(amount)) / 1400.0, 0.0, 1.0)
        var scale := 1.16 + 0.31 * smallness
        _sky_region_scales.append(scale)
        var native := Vector2((centre.x / 2000.0 - 0.5) * SKY_WIDTH, (centre.y / 1092.0 - 0.5) * SKY_HEIGHT)
        # Push the separate islands away from the archipelago's centre to open
        # navigable air channels while retaining their relative map positions.
        var jitter := Vector2(_sky_hash(float(region), 23.0) - 0.5, _sky_hash(float(region), 79.0) - 0.5) * (0.25 + 0.3 * smallness)
        _sky_region_offsets.append(Vector2(native.x * 0.26, native.y * 0.31) + jitter)
    _sky_component_ids = ids
    _sky_region_flights = flights

    # Multi-source flood fill: each cell knows how far it is from exposed shore.
    var coast := PackedInt32Array()
    coast.resize(count)
    coast.fill(-1)
    queue.clear()
    for cell in range(count):
        if mask[cell] == 0:
            continue
        var gx := cell % cols
        var gy := int(cell / cols)
        if not _sky_is_land(mask, gx - 1, gy, cols, rows) or not _sky_is_land(mask, gx + 1, gy, cols, rows) or not _sky_is_land(mask, gx, gy - 1, cols, rows) or not _sky_is_land(mask, gx, gy + 1, cols, rows):
            coast[cell] = 0
            queue.append(cell)
    var head := 0
    while head < queue.size():
        var cell := queue[head]
        head += 1
        var gx := cell % cols
        var gy := int(cell / cols)
        for delta in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
            var nx: int = gx + delta.x
            var ny: int = gy + delta.y
            if _sky_is_land(mask, nx, ny, cols, rows):
                var ni := ny * cols + nx
                if coast[ni] == -1:
                    coast[ni] = coast[cell] + 1
                    queue.append(ni)

    var top := SurfaceTool.new()
    var rocks := SurfaceTool.new()
    var waterfalls := SurfaceTool.new()
    var ivy := SurfaceTool.new()
    top.begin(Mesh.PRIMITIVE_TRIANGLES)
    rocks.begin(Mesh.PRIMITIVE_TRIANGLES)
    waterfalls.begin(Mesh.PRIMITIVE_TRIANGLES)
    ivy.begin(Mesh.PRIMITIVE_TRIANGLES)
    var boulder_positions: Array[Transform3D] = []
    var water_count := 0
    for gy in range(rows):
        for gx in range(cols):
            var cell := gy * cols + gx
            if mask[cell] == 0:
                continue
            var region := ids[cell]
            var flight := flights[region]
            var x := float(gx * TILE)
            var y := float(gy * TILE)
            var x1 := float(mini((gx + 1) * TILE, 2000))
            var y1 := float(mini((gy + 1) * TILE, 1092))
            var a := _sky_pos(x, y, _sky_surface_y(x, y, flight), region)
            var b := _sky_pos(x1, y, _sky_surface_y(x1, y, flight), region)
            var c := _sky_pos(x1, y1, _sky_surface_y(x1, y1, flight), region)
            var d := _sky_pos(x, y1, _sky_surface_y(x, y1, flight), region)
            var ua := Vector2(x / 2000.0, y / 1092.0)
            var ub := Vector2(x1 / 2000.0, y / 1092.0)
            var uc := Vector2(x1 / 2000.0, y1 / 1092.0)
            var ud := Vector2(x / 2000.0, y1 / 1092.0)
            _add_sky_top_tri(top, [a, b, d], [ua, ub, ud], flight, region)
            _add_sky_top_tri(top, [b, c, d], [ub, uc, ud], flight, region)
            var ba := _sky_bottom_vertex(gx, gy, region, flight, ids, coast, cols, rows)
            var bb := _sky_bottom_vertex(gx + 1, gy, region, flight, ids, coast, cols, rows)
            var bc := _sky_bottom_vertex(gx + 1, gy + 1, region, flight, ids, coast, cols, rows)
            var bd := _sky_bottom_vertex(gx, gy + 1, region, flight, ids, coast, cols, rows)
            _add_sky_rock_tri(rocks, [ba, bd, bb], Vector3.DOWN, [0.0, 0.0, 0.0])
            _add_sky_rock_tri(rocks, [bb, bd, bc], Vector3.DOWN, [0.0, 0.0, 0.0])
            if not _sky_is_land(mask, gx, gy - 1, cols, rows):
                _add_sky_cliff(rocks, a, b, ba, bb, Vector3(0, 0, -1))
            if not _sky_is_land(mask, gx + 1, gy, cols, rows):
                _add_sky_cliff(rocks, b, c, bb, bc, Vector3(1, 0, 0))
            if not _sky_is_land(mask, gx, gy + 1, cols, rows):
                _add_sky_cliff(rocks, c, d, bc, bd, Vector3(0, 0, 1))
                var r := _sky_hash(float(gx), float(gy))
                if r > 0.92 and coast[cell] == 0:
                    var anchor := (c + d) * 0.5 + Vector3(0, 0.01, 0.055)
                    _add_sky_vine(ivy, anchor, 0.27 + 0.59 * _sky_hash(float(gy), float(gx)))
                if r > 0.985 and water_count < 21 and sizes[region] > 120:
                    _add_waterfall_strip(waterfalls, (c + d) * 0.5 + Vector3(0, 0.025, 0.079), 0.10 + 0.12 * _sky_hash(float(gx), 21.0), 1.25 + 1.25 * _sky_hash(float(gy), 73.0))
                    water_count += 1
            if not _sky_is_land(mask, gx - 1, gy, cols, rows):
                _add_sky_cliff(rocks, d, a, bd, ba, Vector3(-1, 0, 0))
            # Deterministic, instanced rocky surface details, no per-rock draw calls.
            if gx % 3 == 1 and gy % 3 == 1 and coast[cell] > 2 and _sky_hash(float(gx), float(gy)) > 0.59:
                var rx := (x + x1) * 0.5
                var ry := (y + y1) * 0.5
                var scale := 0.08 + 0.14 * _sky_hash(float(gx) + 13.0, float(gy))
                var angle := TAU * _sky_hash(float(gx), float(gy) + 9.0)
                var basis := Basis(Vector3.UP, angle).scaled(Vector3(scale, scale * (0.60 + 0.5 * _sky_hash(float(gy), 6.0)), scale * 0.83))
                boulder_positions.append(Transform3D(basis, _sky_pos(rx, ry, _sky_surface_y(rx, ry, flight) - 0.022, region)))

    _sky_material = ShaderMaterial.new()
    _sky_material.shader = load("res://shaders/globe_sky_islands.gdshader")
    _sky_material.set_shader_parameter("terrain_tex", load("res://map/sky_terrain.png"))
    _sky_material.set_shader_parameter("index_tex", load("res://map/sky_index.png"))
    _sky_material.set_shader_parameter("colour_strength", 0.0)
    var surface := MeshInstance3D.new()
    surface.name = "Grassy floating islands (clickable provinces)"
    surface.mesh = top.commit()
    surface.material_override = _sky_material
    _sky.add_child(surface)
    # Picking against the real 3D surface keeps province interaction accurate
    # even when islands sit at different heights or the camera is tilted.
    surface.create_trimesh_collision()
    if surface.get_child_count() > 0:
        var static_body := surface.get_child(0) as StaticBody3D
        if static_body != null:
            static_body.set_meta("sky_top", true)
            if static_body.get_child_count() > 0:
                var collision := static_body.get_child(0) as CollisionShape3D
                if collision != null and collision.shape is ConcavePolygonShape3D:
                    (collision.shape as ConcavePolygonShape3D).backface_collision = true

    _rock_material = ShaderMaterial.new()
    _rock_material.shader = load("res://shaders/sky_rock.gdshader")
    var cliffs := MeshInstance3D.new()
    cliffs.name = "Terraced cliffs and pointed undersides"
    cliffs.mesh = rocks.commit()
    cliffs.material_override = _rock_material
    _sky.add_child(cliffs)
    # Rock faces can also be clicked, not just grassy tops.
    cliffs.create_trimesh_collision()
    if cliffs.get_child_count() > 0:
        var cliff_body := cliffs.get_child(0) as StaticBody3D
        if cliff_body != null:
            cliff_body.set_meta("sky_cliff", true)

    if not boulder_positions.is_empty():
        var boulder_mesh := SphereMesh.new()
        boulder_mesh.radius = 1.0
        boulder_mesh.height = 2.0
        boulder_mesh.radial_segments = 7
        boulder_mesh.rings = 4
        var multi := MultiMesh.new()
        multi.transform_format = MultiMesh.TRANSFORM_3D
        multi.mesh = boulder_mesh
        multi.instance_count = boulder_positions.size()
        for i in range(boulder_positions.size()):
            multi.set_instance_transform(i, boulder_positions[i])
        var stones := MultiMeshInstance3D.new()
        stones.name = "Scattered stone outcrops"
        stones.multimesh = multi
        var stone_mat := StandardMaterial3D.new()
        stone_mat.albedo_color = Color(0.39, 0.40, 0.35)
        stone_mat.roughness = 1.0
        stones.material_override = stone_mat
        _sky.add_child(stones)

    var vine_node := MeshInstance3D.new()
    vine_node.name = "Hanging ivy"
    vine_node.mesh = ivy.commit()
    var vine_mat := StandardMaterial3D.new()
    vine_mat.albedo_color = Color(0.15, 0.29, 0.11)
    vine_mat.roughness = 1.0
    vine_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    vine_node.material_override = vine_mat
    _sky.add_child(vine_node)

    var water_node := MeshInstance3D.new()
    water_node.name = "Eden waterfalls"
    water_node.mesh = waterfalls.commit()
    _water_material = ShaderMaterial.new()
    _water_material.shader = load("res://shaders/sky_water.gdshader")
    water_node.material_override = _water_material
    _sky.add_child(water_node)

    # Dense, animated cloud ocean; never expose the space/planet background.
    _cloud = MeshInstance3D.new()
    _cloud.name = "Golden cloud sea"
    var plane := PlaneMesh.new()
    plane.size = Vector2(160, 160)
    plane.subdivide_width = 116
    plane.subdivide_depth = 116
    _cloud.mesh = plane
    _cloud.position = Vector3(0, -1.78, 0)
    _cloud_material = ShaderMaterial.new()
    _cloud_material.shader = load("res://shaders/globe_clouds.gdshader")
    _cloud.material_override = _cloud_material
    _sky.add_child(_cloud)

    _cloud_far = MeshInstance3D.new()
    _cloud_far.name = "Far-reaching cloud horizon"
    var plane_far := PlaneMesh.new()
    plane_far.size = Vector2(320, 320)
    plane_far.subdivide_width = 64
    plane_far.subdivide_depth = 64
    _cloud_far.mesh = plane_far
    _cloud_far.position = Vector3(0, -2.75, 0)
    _cloud_far.material_override = _cloud_material
    _sky.add_child(_cloud_far)
    _build_cloud_banks()


func _build_cloud_banks() -> void:
    # Lumpy cotton-like cloud volumes overlap the animated cloud sea. One
    # MultiMesh keeps hundreds of puffs inexpensive for the Compatibility renderer.
    var puff := SphereMesh.new()
    puff.radius = 1.0
    puff.height = 2.0
    puff.radial_segments = 12
    puff.rings = 8
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.mesh = puff
    multi.instance_count = 560
    for i in range(multi.instance_count):
        var seed := float(i)
        var x := (_sky_hash(seed, 11.0) - 0.5) * 76.0
        var z := (_sky_hash(seed, 19.0) - 0.5) * 58.0
        var height := -1.47 + (_sky_hash(seed, 29.0) - 0.5) * 0.43
        var width := 0.75 + _sky_hash(seed, 37.0) * 1.55
        var depth := 0.7 + _sky_hash(seed, 43.0) * 1.62
        var thickness := 0.17 + _sky_hash(seed, 53.0) * 0.29
        var basis := Basis().scaled(Vector3(width, thickness, depth))
        multi.set_instance_transform(i, Transform3D(basis, Vector3(x, height, z)))
    var bank := MultiMeshInstance3D.new()
    bank.name = "Rolling three-dimensional cloud banks"
    bank.multimesh = multi
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.975, 0.956, 0.866)
    mat.roughness = 1.0
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    bank.material_override = mat
    _sky.add_child(bank)


func _province_on_ray(pos: Vector2) -> int:
    var origin := _camera.project_ray_origin(pos)
    var dir := _camera.project_ray_normal(pos)
    if layer == "sky":
        # Intersect the actual island top, not a horizontal plane. Each flying
        # region has a different elevation, and a plane picks the wrong place.
        var world_3d := _view.get_world_3d()
        if world_3d == null or world_3d.direct_space_state == null:
            return 0
        var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 120.0)
        var hit: Dictionary = world_3d.direct_space_state.intersect_ray(query)
        if hit.is_empty():
            return 0
        var p: Vector3 = hit["position"]
        var collider: Object = hit["collider"]
        if collider != null and collider.has_meta("sky_top"):
            var face_index: int = int(hit.get("face_index", -1))
            var tri := face_index * 3
            if tri >= 0 and tri + 2 < _sky_pick_vertices.size():
                var a: Vector3 = _sky_pick_vertices[tri]
                var b: Vector3 = _sky_pick_vertices[tri + 1]
                var c: Vector3 = _sky_pick_vertices[tri + 2]
                var e0 := b - a
                var e1 := c - a
                var ep := p - a
                var d00 := e0.dot(e0)
                var d01 := e0.dot(e1)
                var d11 := e1.dot(e1)
                var d20 := ep.dot(e0)
                var d21 := ep.dot(e1)
                var denom := d00 * d11 - d01 * d01
                if absf(denom) > 0.00000001:
                    var v := (d11 * d20 - d01 * d21) / denom
                    var w := (d00 * d21 - d01 * d20) / denom
                    var uv: Vector2 = _sky_pick_uvs[tri] + (_sky_pick_uvs[tri + 1] - _sky_pick_uvs[tri]) * v + (_sky_pick_uvs[tri + 2] - _sky_pick_uvs[tri]) * w
                    var id := _index_at("sky", clampi(int(uv.x * 2000.0), 0, 1999), clampi(int(uv.y * 1092.0), 0, 1091))
                    if id > 0:
                        return id
        return _sky_pick_inverse(p)
    var b := origin.dot(dir)
    var discriminant := b * b - (origin.length_squared() - RADIUS * RADIUS)
    if discriminant < 0.0:
        return 0
    var t := -b - sqrt(discriminant)
    if t < 0.0:
        return 0
    var point := (origin + dir * t).normalized()
    var u := fposmod(atan2(point.x, point.z) / TAU + 0.5, 1.0)
    var globe_v: float = 0.5 - asin(clampf(point.y, -1.0, 1.0)) / PI
    if globe_v <= GLOBE_POLAR_PAD or globe_v >= 1.0 - GLOBE_POLAR_PAD:
        return 0
    var v: float = (globe_v - GLOBE_POLAR_PAD) / (1.0 - 2.0 * GLOBE_POLAR_PAD)
    return _index_at("ground", int(u * _indexes["ground"].get_width()), int(v * _indexes["ground"].get_height()))


func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventMouseButton:
        if event.pressed and get_viewport().gui_get_hovered_control() != null:
            return
        if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _distance = clampf(_distance * 0.88, 6.1 if layer == "ground" else 9.5, 44.0)
            _update_camera()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _distance = clampf(_distance * 1.12, 6.1 if layer == "ground" else 9.5, 44.0)
            _update_camera()
        elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
            if event.pressed:
                _holding = true
                _pressed_button = event.button_index
                _press = event.position
                _drag = false
            elif _holding and event.button_index == _pressed_button:
                _holding = false
                if not _drag:
                    var id := _province_on_ray(event.position)
                    if event.button_index == MOUSE_BUTTON_LEFT:
                        select(id if id > 0 else -1)
                        province_clicked.emit(id)
                    elif event.button_index == MOUSE_BUTTON_RIGHT and id > 0:
                        province_right_clicked.emit(id)
                _drag = false
    elif event is InputEventMouseMotion:
        if _holding and event.position.distance_to(_press) > 5.0:
            _drag = true
        if _holding and _drag:
            _yaw -= event.relative.x * 0.006
            _pitch = clampf(_pitch + event.relative.y * 0.005, -1.42 if layer == "ground" else 0.24, 1.43)
            _update_camera()
        elif not _holding:
            var id := 0 if get_viewport().gui_get_hovered_control() != null else _province_on_ray(event.position)
            if id != _hovered:
                _hovered = id
                for l in _world_materials:
                    _world_materials[l].set_shader_parameter("hovered_id", id)
                if _sky_material != null:
                    _sky_material.set_shader_parameter("hovered_id", id)
                province_hovered.emit(id)
