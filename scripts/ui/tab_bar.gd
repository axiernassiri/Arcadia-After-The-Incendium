extends PanelContainer
## The column of buttons down the left edge that opens the nation's panels (like EU4's top-left menu).

signal open_panel(name: String)

const UI = preload("res://scripts/ui/ui_util.gd")
const ICONS := {"court": "crown", "government": "column", "economy": "coins", "production": "hammer", "trade": "trade",
	"tech": "gear", "ideas": "book", "military": "swords", "diplomacy": "envelope", "peoples": "manpower",
	"missions": "flag", "ledger": "scroll", "ages": "hourglass", "help": "help"}
const TABS := [
	["court", "Court", "Ruler, heir, stability and modifiers (C)"],
	["government", "Government", "Government reforms (G)"],
	["economy", "Economy", "Income, expenses, loans and buildings (E)"],
	["production", "Production", "Build, recruit and lay down ships in every province (B)"],
	["trade", "Trade", "Trade nodes, merchants and prices (T)"],
	["tech", "Technology", "Administrative, diplomatic and military tech (R)"],
	["ideas", "Ideas", "National ideas and idea groups (I)"],
	["military", "Military", "Armies, fleets and generals (L)"],
	["diplomacy", "Diplomacy", "Nations, wars and peace deals (O)"],
	["peoples", "Peoples", "Cultures, religions and ethnicities (P)"],
	["missions", "Missions", "Mission tree (M)"],
	["ledger", "Ledger", "Every nation compared, and their history (J)"],
	["ages", "Ages", "The age, its objectives and abilities (K)"],
	["help", "Help", "How to play (F1)"],
]

var _buttons = {}


func _ready() -> void:
	theme_type_variation = "BarPanel"
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	for t in TABS:
		if t[0] == "help":
			var sep = HSeparator.new()
			sep.add_theme_constant_override("separation", 6)
			v.add_child(sep)
		var b = UI.icon_button(ICONS.get(t[0], "help"), t[1], func(): open_panel.emit(t[0]), t[2], 18)
		b.theme_type_variation = "FlatButton"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(132, 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("h_separation", 9)
		_buttons[t[0]] = b
		v.add_child(b)


func set_active(name: String) -> void:
	for k in _buttons:
		_buttons[k].set_pressed_no_signal(k == name)


func set_badge(name: String, text: String) -> void:
	if not _buttons.has(name):
		return
	for t in TABS:
		if t[0] == name:
			_buttons[name].text = t[1] + ("  " + text if text != "" else "")
			_buttons[name].add_theme_color_override("font_color", UI.GOOD if text != "" else UI.TEXT)
