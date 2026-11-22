extends PanelContainer
## F1: a one-page guide to the controls and the main systems.

const UI = preload("res://scripts/ui/ui_util.gd")
const SECTIONS := [
	["Controls", "Left-click a province to select it. Right-click with an army selected to move it; right-click a foreign province to open its diplomacy.\nWheel or +/- to zoom, drag with the middle mouse button or WASD to pan. Tab switches between the mainland and Skyfall. Space pauses, 1-5 set the speed, Home shows the whole map, Esc closes windows.\nShift-click armies to select several, or shift-drag a box around them; right-click then sends them all. With an army selected, hover a province to see the route, the days it takes and any attrition. The Outliner (top right) lists your wars, armies, fleets, sieges, construction and recruitment: click a row to jump there.\nCtrl+F finds a province or nation. Shift+1 to Shift+= pick a map mode. The world map loops east-west: keep panning and you come round again."],
	["Sky, sea and masks", "Skyfall and VAGA live above the clouds, Oceania under the sea. Everyone else needs oxygen masks (Military technology 3) to climb the Holy Waterfall or dive into the deep, and the sky and sea peoples need them to come onto dry land."],
	["Estates and prestige", "The Faithful, the Guilds and the War Clans (Government window) help you while loyal and hurt you when not. Granting a privilege wins their loyalty but gives them influence; an empowered estate left angry throws the realm into disorder. Prestige from victories adds morale; the five strongest nations are Great Powers."],
	["Panels", "C Court (ruler, legitimacy, advisors)   G Government   E Economy   B Production   T Trade\nR Technology   I Ideas   L Military   O Diplomacy   P Peoples   M Missions   J Ledger   K Ages   F1 this help"],
	["Alerts", "The icons under the top bar tell you what you can do now (green: tech, ideas, reforms, missions, advisors, enforce peace) and what is going wrong (red: deficit, loans, low legitimacy, rebels, force limit). Hover for details, click to jump there."],
	["Sanctum", "Your money. Tax, production and trade bring it in; armies, fleets, forts, advisors, loans and administration cost it every month. Mines on sanctum ore sites dig it straight from the ground. Everything is expensive: spend carefully."],
	["Technology", "Each level has a year. Researching before that year costs 10% more per year early and gives a 10-year 'ahead of time' penalty. The game runs about 500 years, from 4289 to 4789."],
	["Autonomy", "In the early Arcadian era provinces slowly drift away from the capital. Autonomy lowers their tax, production, manpower and trade, but also unrest. Lower it from the province window."],
	["Aggressive expansion", "Taking land in a peace deal makes other nations wary of you, most of all your neighbours and those who share the victim's faith or culture. Retaking your own cores causes only half as much. At 50 they join a coalition against you, and a coalition of three or more declares war after a year; if it wins, it disbands and forgives you. It fades by half a point a month: the Diplomacy panel shows who is wary."],
	["Wars and battles", "Open a war's overview from the Outliner or the Diplomacy panel: the war score and where it comes from, both sides, occupations and every battle. After each battle you fight, a report shows the generals, terrain and losses."],
	["Messages", "The log at the bottom shows news about you, your allies, enemies and neighbours; the World tab shows the rest. Wars on you, peace deals and bankruptcy pause the game with a popup (turn this off in Settings, from the Esc menu). The game autosaves every year by default."],
	["War", "Declare war from a nation's diplomacy window. Your allies do NOT join on their own: call them from the Diplomacy panel. They decide by opinion, the enemy and their own situation, and want sanctum in return. Occupy every province of the enemy and you can enforce peace."],
	["The Black Moon", "Every 29 February the Doomsday Barrier falls. Anomalies tear at Skyfall, then time reverses. Sometimes entities come through the portal and stay. VAGA worships them."],
]

signal closed


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.tex_box("panel.png", 12, 24, 20, true))
	custom_minimum_size = Vector2(720, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	outer.add_child(UI.row([UI.heading("How to play Arcadia", 22), UI.spacer(), UI.button("Close (F1)", func(): visible = false; closed.emit())]))
	# the guide scrolls when it is taller than the window (main.gd calls fit_height)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_scroll.add_child(v)
	for s in SECTIONS:
		v.add_child(UI.heading(s[0], 15))
		v.add_child(UI.label(s[1], 13, UI.TEXT, 680))
	visible = false


var _scroll: ScrollContainer


func fit_height(viewport_h: float) -> void:
	var h := maxf(200.0, viewport_h - 160.0)
	if absf(_scroll.custom_minimum_size.y - h) > 1.0:
		_scroll.custom_minimum_size = Vector2(700, h)
		reset_size()
