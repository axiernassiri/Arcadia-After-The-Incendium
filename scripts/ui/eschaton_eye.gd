extends Control
## The red eye: J82wC4's warning that the Eschaton is coming. Flashes over the whole screen a year
## before the end, then fades away in about three seconds. Drawn in code, no image needed.

const DURATION := 3.0
const RED := Color(0.86, 0.05, 0.07)

var _t := DURATION


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	Game.eschaton_warning.connect(flash)


func flash() -> void:
	var snd = get_tree().root.get_node_or_null("Sound")
	if snd != null:
		snd.play("doom")
	_t = 0.0
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= DURATION:
		visible = false
	queue_redraw()


func _alpha() -> float:
	# snaps open in a quarter second, holds, then fades out by three seconds
	if _t < 0.25:
		return _t / 0.25
	if _t < 0.9:
		return 1.0
	return clampf(1.0 - (_t - 0.9) / (DURATION - 0.9), 0.0, 1.0)


func _draw() -> void:
	var a := _alpha()
	if a <= 0.0:
		return
	var vs := size
	var c := vs / 2.0
	# the whole screen bleeds red, darker at the edges
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.25, 0.0, 0.01, 0.45 * a))
	for i in 6:
		var inset := float(i) * minf(vs.x, vs.y) * 0.03
		draw_rect(Rect2(Vector2(inset, inset), vs - Vector2(inset, inset) * 2.0), Color(0.0, 0.0, 0.0, 0.10 * a), false, minf(vs.x, vs.y) * 0.03)
	# the eye: an almond, opening wide, with a slight tremor
	var open := clampf(_t / 0.35, 0.0, 1.0)
	var w := minf(vs.x * 0.42, 620.0)
	var h := w * 0.36 * open
	var shake := Vector2(sin(_t * 61.0), cos(_t * 47.0)) * 2.0 * a
	var cc := c + shake
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in 49:
		var x := -1.0 + 2.0 * float(i) / 48.0
		var y := (1.0 - x * x) * 0.5   # a parabola from corner to corner
		top.append(cc + Vector2(x * w * 0.5, -y * h))
		bottom.append(cc + Vector2(x * w * 0.5, y * h))
	var almond := top.duplicate()
	for i in range(bottom.size() - 2, 0, -1):
		almond.append(bottom[i])
	# glow behind the eye
	for i in 5:
		draw_circle(cc, w * (0.22 + i * 0.08), Color(RED, 0.06 * a))
	if h > 2.0:
		draw_colored_polygon(almond, Color(0.06, 0.0, 0.01, 0.95 * a))
		# iris: rings of red, brightest at the rim, clipped to the eye's height
		var ir := minf(h * 0.47, w * 0.17)   # the almond is h/2 tall at its centre
		for i in 8:
			var rr := ir * (1.0 - i * 0.11)
			draw_circle(cc, rr, Color(RED.lerp(Color(1.0, 0.45, 0.2), float(i) / 8.0), (0.55 + 0.05 * i) * a))
		# a slit pupil
		var pw := ir * 0.18
		var ph := ir * 0.92
		draw_colored_polygon(PackedVector2Array([cc + Vector2(0, -ph), cc + Vector2(pw, 0), cc + Vector2(0, ph), cc + Vector2(-pw, 0)]), Color(0, 0, 0, a))
		# veins reaching in from the corners
		for k in 7:
			var side := -1.0 if k % 2 == 0 else 1.0
			var start := cc + Vector2(side * w * 0.48, (float(k) - 3.0) * h * 0.06)
			var mid := cc + Vector2(side * w * (0.30 - 0.02 * k), (float(k) - 3.0) * h * 0.12)
			draw_polyline(PackedVector2Array([start, mid, cc + Vector2(side * ir * 1.05, (float(k) - 3.0) * ir * 0.12)]), Color(RED, 0.55 * a), 1.5, true)
	# lids
	draw_polyline(top, Color(RED, a), 3.0, true)
	draw_polyline(bottom, Color(RED, a), 3.0, true)
	# the warning
	var font: Font = get_theme_default_font()
	var msg := "THE ESCHATON APPROACHES"
	var fs := 22
	var tw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - tw / 2.0, cc.y + w * 0.32), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.35, 0.3, a))
