extends PanelContainer
## Bottom-left: map modes and the mainland / Skyfall layer switch.

signal mode_selected(mode: String)
signal layer_selected(layer: String)

const UI = preload("res://scripts/ui/ui_util.gd")
const MODE_LABELS := {"political": "Political", "diplomacy": "Diplomatic", "development": "Development",
	"goods": "Goods", "trade": "Trade", "region": "Regions", "culture": "Culture", "religion": "Religion",
	"ethnicity": "Ethnicity", "unrest": "Unrest", "terrain": "Terrain", "autonomy": "Autonomy"}

const MODE_ICONS := {"political": "flag", "diplomacy": "envelope", "development": "house", "goods": "coins",
	"trade": "trade", "region": "map", "culture": "scroll", "religion": "sun", "ethnicity": "person", "unrest": "flame",
	"terrain": "mountain", "autonomy": "seal"}

var _mode_buttons = {}
var _mode_label: Label
var _layer_buttons = {}


func _ready() -> void:
	theme_type_variation = "BarPanel"
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var layers = HBoxContainer.new()
	layers.add_theme_constant_override("separation", 4)
	for l in [["ground", "Mainland", "map"], ["sky", "Skyfall", "wing"]]:
		var b = UI.icon_button(l[2], l[1], func(): layer_selected.emit(l[0]), "Switch map layer (Tab)", 16)
		b.toggle_mode = true
		b.custom_minimum_size.x = 118
		_layer_buttons[l[0]] = b
		layers.add_child(b)
	v.add_child(layers)
	_mode_label = UI.heading("", 13)
	v.add_child(_mode_label)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	for m in MODE_LABELS:
		var b = UI.icon_button(MODE_ICONS[m], "", func(): mode_selected.emit(m), "%s map mode" % MODE_LABELS[m], 18)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(36, 32)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_mode_buttons[m] = b
		grid.add_child(b)
	v.add_child(grid)
	set_state("political", "ground")


func set_state(mode: String, layer: String) -> void:
	for m in _mode_buttons:
		_mode_buttons[m].set_pressed_no_signal(m == mode)
	if _mode_label:
		_mode_label.text = "%s map" % MODE_LABELS.get(mode, mode)
	for l in _layer_buttons:
		_layer_buttons[l].set_pressed_no_signal(l == layer)
