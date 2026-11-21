extends PanelContainer
## Base for the game's windows: a title row with a close button and a scrolling body.
## Subclasses override build() to fill `body`. Call mark_dirty() when the game changes; the panel
## rebuilds at most a few times a second, and never in the middle of a click (rebuilding a button
## while it is being pressed used to let the click fall through to the map).

signal closed

const UI = preload("res://scripts/ui/ui_util.gd")
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
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	_header = HBoxContainer.new()
	_title_label = UI.label(title, 20, UI.GOLD)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_title_label)
	_header.add_child(UI.button("x", close, "Close (Esc)"))
	outer.add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(panel_width - 20.0, 0)
	outer.add_child(_scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)
	visible = false
	visibility_changed.connect(func(): if visible: mark_dirty())
	setup()


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


func _fit() -> void:
	await get_tree().process_frame
	if not is_instance_valid(body):
		return
	var want = body.get_combined_minimum_size().y + 4.0
	_scroll.custom_minimum_size.y = minf(want, max_height)
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
		body.add_child(HSeparator.new())
	body.add_child(UI.heading(t, 15))
