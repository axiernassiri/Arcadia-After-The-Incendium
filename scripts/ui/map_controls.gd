extends PanelContainer
## Bottom-left: map modes and the mainland / Skyfall layer switch.

signal mode_selected(mode: String)
signal layer_selected(layer: String)

const UI = preload("res://scripts/ui/ui_util.gd")
const MODE_LABELS := {"political": "Political", "diplomacy": "Diplomatic", "development": "Development",
	"goods": "Goods", "trade": "Trade", "region": "Regions", "culture": "Culture", "religion": "Religion",
	"ethnicity": "Ethnicity", "unrest": "Unrest", "terrain": "Terrain"}

var _mode_buttons = {}
var _layer_buttons = {}


func _ready() -> void:
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var layers = HBoxContainer.new()
	for l in [["ground", "Mainland"], ["sky", "Skyfall"]]:
		var b = UI.button(l[1], func(): layer_selected.emit(l[0]), "Switch map layer (Tab)")
		b.toggle_mode = true
		b.custom_minimum_size.x = 120
		_layer_buttons[l[0]] = b
		layers.add_child(b)
	v.add_child(layers)
	var grid = GridContainer.new()
	grid.columns = 4
	for m in MODE_LABELS:
		var b = UI.button(MODE_LABELS[m], func(): mode_selected.emit(m), "Map mode")
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 12)
		_mode_buttons[m] = b
		grid.add_child(b)
	v.add_child(grid)
	set_state("political", "ground")


func set_state(mode: String, layer: String) -> void:
	for m in _mode_buttons:
		_mode_buttons[m].set_pressed_no_signal(m == mode)
	for l in _layer_buttons:
		_layer_buttons[l].set_pressed_no_signal(l == layer)
