extends PanelContainer
## The column of buttons down the left edge that opens the nation's panels (like EU4's top-left menu).

signal open_panel(name: String)

const UI = preload("res://scripts/ui/ui_util.gd")
const TABS := [
	["court", "Court", "Ruler, heir, stability and modifiers (C)"],
	["government", "Government", "Government reforms (G)"],
	["economy", "Economy", "Income, expenses, loans and buildings (E)"],
	["trade", "Trade", "Trade nodes, merchants and prices (T)"],
	["tech", "Technology", "Administrative, diplomatic and military tech (R)"],
	["ideas", "Ideas", "National ideas and idea groups (I)"],
	["military", "Military", "Armies, fleets and generals (L)"],
	["diplomacy", "Diplomacy", "Nations, wars and peace deals (O)"],
	["peoples", "Peoples", "Cultures, religions and ethnicities (P)"],
	["missions", "Missions", "Mission tree (M)"],
]

var _buttons = {}


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(UI.BG_DARK, UI.BORDER, 6, 6))
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	for t in TABS:
		var b = UI.button(t[1], func(): open_panel.emit(t[0]), t[2])
		b.custom_minimum_size = Vector2(104, 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_buttons[t[0]] = b
		v.add_child(b)


func set_active(name: String) -> void:
	for k in _buttons:
		_buttons[k].add_theme_color_override("font_color", UI.GOLD if k == name else UI.TEXT)


func set_badge(name: String, text: String) -> void:
	if not _buttons.has(name):
		return
	for t in TABS:
		if t[0] == name:
			_buttons[name].text = t[1] + ("  " + text if text != "" else "")
			_buttons[name].add_theme_color_override("font_color", UI.GOOD if text != "" else UI.TEXT)
