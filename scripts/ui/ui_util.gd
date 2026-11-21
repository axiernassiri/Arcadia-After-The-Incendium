extends RefCounted
## Shared look and small widget helpers. Usage: const UI = preload("res://scripts/ui/ui_util.gd")

const BG := Color(0.11, 0.125, 0.15, 0.95)
const BG_DARK := Color(0.07, 0.08, 0.10, 0.97)
const BG_CARD := Color(0.15, 0.17, 0.20)
const BORDER := Color(0.62, 0.53, 0.33)
const TEXT := Color(0.92, 0.89, 0.81)
const TEXT_DIM := Color(0.66, 0.64, 0.58)
const GOLD := Color(0.96, 0.80, 0.42)
const GOOD := Color(0.55, 0.85, 0.50)
const BAD := Color(0.93, 0.45, 0.42)
const DOOM := Color(0.78, 0.45, 1.0)
const INFO := Color(0.55, 0.75, 0.95)


static func box(bg: Color = BG, border: Color = BORDER, radius: int = 6, pad: int = 10) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


static func build_theme() -> Theme:
	var t = Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box())
	var normal = box(Color(0.20, 0.22, 0.26), Color(0.42, 0.38, 0.28), 4, 6)
	var hover = box(Color(0.27, 0.30, 0.35), BORDER, 4, 6)
	var pressed = box(Color(0.34, 0.31, 0.22), GOLD, 4, 6)
	var disabled = box(Color(0.15, 0.16, 0.18), Color(0.25, 0.25, 0.25), 4, 6)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, GOLD)
		t.set_color("font_disabled_color", cls, Color(0.45, 0.45, 0.45))
	t.set_stylebox("panel", "TooltipPanel", box(BG_DARK, BORDER, 4, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("separator", "HSeparator", _line())
	t.set_constant("separation", "HSeparator", 10)
	t.set_stylebox("normal", "LineEdit", box(Color(0.06, 0.07, 0.09), Color(0.42, 0.38, 0.28), 4, 6))
	t.set_stylebox("focus", "LineEdit", box(Color(0.06, 0.07, 0.09), GOLD, 4, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("panel", "PopupMenu", box(BG_DARK, BORDER, 4, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("hover", "PopupMenu", box(Color(0.27, 0.30, 0.35), BORDER, 3, 4))
	var bg_bar = box(Color(0.06, 0.07, 0.09), Color(0.3, 0.28, 0.22), 3, 0)
	var fill = box(GOLD.darkened(0.25), GOLD.darkened(0.25), 3, 0)
	t.set_stylebox("background", "ProgressBar", bg_bar)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_stylebox("slider", "HSlider", box(Color(0.06, 0.07, 0.09), Color(0.3, 0.28, 0.22), 3, 2))
	t.set_stylebox("grabber_area", "HSlider", box(GOLD.darkened(0.3), GOLD.darkened(0.3), 3, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, GOLD, 3, 2))
	return t


static func _line() -> StyleBoxLine:
	var l = StyleBoxLine.new()
	l.color = Color(BORDER, 0.45)
	l.thickness = 1
	return l


static func label(text: String, size: int = 14, colour: Color = TEXT, wrap_width: float = 0.0) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if wrap_width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = wrap_width
	return l


static func tip_label(text: String, tip: String, size: int = 14, colour: Color = TEXT) -> Label:
	var l = label(text, size, colour)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


static func button(text: String, callback: Callable, tooltip: String = "") -> Button:
	var b = Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b


static func action(text: String, why: String, callback: Callable, tooltip: String = "") -> Button:
	## A button that is disabled with its reason as the tooltip when `why` isn't empty.
	var b = button(text, callback, why if why != "" else tooltip)
	b.disabled = why != ""
	return b


static func swatch(colour: Color, size: Vector2 = Vector2(16, 16)) -> ColorRect:
	var r = ColorRect.new()
	r.color = colour
	r.custom_minimum_size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func bar(value: float, max_value: float, width: float = 120.0, colour: Color = GOLD, height: float = 10.0) -> ProgressBar:
	var p = ProgressBar.new()
	p.min_value = 0.0
	p.max_value = maxf(max_value, 0.001)
	p.value = clampf(value, 0.0, p.max_value)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(width, height)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("fill", box(colour.darkened(0.15), colour.darkened(0.15), 3, 0))
	return p


static func heading(text: String, size: int = 16) -> Label:
	return label(text, size, GOLD)


static func row(children: Array, sep: int = 8) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


static func kv(key: String, value: String, tip: String = "", value_colour: Color = TEXT) -> HBoxContainer:
	var k = label(key, 13, TEXT_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v = label(value, 13, value_colour)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var h = row([k, v])
	if tip != "":
		h.tooltip_text = tip
		h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h


static func spacer() -> Control:
	var c = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func card(border: Color = BORDER, pad: int = 8) -> PanelContainer:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(BG_CARD, border, 5, pad))
	return p


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func signed(v: float, decimals: int = 1) -> String:
	var fmt = "%+." + str(decimals) + "f"
	return fmt % v


static func money(v: float) -> String:
	if absf(v) >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return "%d" % int(round(v))


static func mod_lines(mods: Dictionary, power_names: Array = []) -> Array:
	## [[text, good?]] for a modifier dictionary.
	var Mod = load("res://scripts/sim/modifiers.gd")
	var out: Array = []
	for k in mods:
		out.append([Mod.describe_one(k, float(mods[k]), power_names), Mod.is_good(k, float(mods[k]))])
	return out


static func mod_box(mods: Dictionary, power_names: Array = [], width: float = 0.0) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	for l in mod_lines(mods, power_names):
		v.add_child(label("  " + l[0], 12, GOOD if l[1] else BAD, width))
	return v
