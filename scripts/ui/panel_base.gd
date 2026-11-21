extends PanelContainer
## Base for the game's windows: a title row with a close button and a scrolling body.
## Subclasses override build() to fill `body`. Call mark_dirty() when the game changes; the panel
## rebuilds at most a few times a second, and never in the middle of a click (rebuilding a button
## while it is being pressed used to let the click fall through to the map).

signal closed

const UI = preload("res://scripts/ui/ui_util.gd")
const Tokens = preload("res://ui/style/tokens.gd")
const MIN_INTERVAL := 0.25

var title = "Panel"
var panel_width = 400.0
var max_height = 600.0
var body: VBoxContainer
var _title_label: Label
var _scroll: ScrollContainer
var _dirty = true
var _since = 0.0
var _header: HBoxContainer


func _ready() -> void:
	custom_minimum_size.x = panel_width
	mouse_filter = Control.MOUSE_FILTER_STOP
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", Tokens.SP_1)
	add_child(outer)
	_header = HBoxContainer.new()
	_title_label = UI.heading(title, Tokens.SIZE_TITLE)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_title_label)
	var x = UI.icon_button("close", "", close, "Close (Esc)", 14)
	x.theme_type_variation = "FlatButton"
	x.custom_minimum_size = Vector2(28, 28)
	x.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_child(x)
	outer.add_child(_header)
	outer.add_child(UI.divider())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(panel_width - 20.0, 0)
	outer.add_child(_scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)
	visible = false
	visibility_changed.connect(_on_visibility)
	setup()


var _tween: Tween


func _on_visibility() -> void:
	if not visible:
		return
	mark_dirty()
	# a short fade and settle, so windows don't pop in
	if _tween:
		_tween.kill()
	pivot_offset = Vector2(0, 0)
	modulate.a = 0.0
	scale = Vector2(0.985, 0.985)
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, Tokens.DUR_NORMAL)
	_tween.tween_property(self, "scale", Vector2.ONE, Tokens.DUR_NORMAL)


func setup() -> void:
	## Override: connect game signals here.
	pass


func set_title(t: String) -> void:
	title = t
	if _title_label:
		_title_label.text = t


func mark_dirty() -> void:
	_dirty = true


func refresh_now() -> void:
	_dirty = false
	_since = 0.0
	UI.clear(body)
	build()
	_fit()


func _process(delta: float) -> void:
	_since += delta
	if visible and _dirty and _since >= MIN_INTERVAL and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		refresh_now()
	elif visible and not is_equal_approx(max_height, _fitted_max):
		_fit()   # the window was resized (main.gd sets max_height every frame)


var _fitted_max = -1.0


func _fit() -> void:
	_fitted_max = max_height
	await get_tree().process_frame
	if not is_instance_valid(body):
		return
	# max_height caps the whole window, so take off the title row, divider and frame padding,
	# otherwise a long panel runs past the bottom of the screen and its last rows can't be reached.
	var chrome = get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var want = body.get_combined_minimum_size().y + 4.0
	_scroll.custom_minimum_size.y = maxf(80.0, minf(want, max_height - chrome))
	reset_size()


func build() -> void:
	## Override: fill `body`.
	pass


func close() -> void:
	visible = false
	closed.emit()


func add(c: Control) -> Control:
	body.add_child(c)
	return c


func text(t: String, size: int = 13, colour: Color = UI.TEXT) -> Label:
	var l = UI.label(t, size, colour, panel_width - 40.0)
	body.add_child(l)
	return l


func section(t: String) -> void:
	if body.get_child_count() > 0:
		var gap = Control.new()
		gap.custom_minimum_size.y = Tokens.SP_1
		body.add_child(gap)
	body.add_child(UI.heading(t, 15))
	var line = ColorRect.new()
	line.color = Color(UI.BORDER, 0.35)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(line)
