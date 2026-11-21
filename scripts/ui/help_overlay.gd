extends PanelContainer
## F1: a one-page guide to the controls and the main systems.

const UI = preload("res://scripts/ui/ui_util.gd")
const SECTIONS := [
	["Controls", "Left-click a province to select it. Right-click with an army selected to move it; right-click a foreign province to open its diplomacy.\nWheel or +/- to zoom, drag with the middle mouse button or WASD to pan. Tab switches between the mainland and Skyfall. Space pauses, 1-5 set the speed, Home shows the whole map, Esc closes windows."],
	["Panels", "C Court (ruler, legitimacy, advisors)   G Government   E Economy   B Production   T Trade\nR Technology   I Ideas   L Military   O Diplomacy   P Peoples   M Missions   F1 this help"],
	["Alerts", "The icons under the top bar tell you what you can do now (green: tech, ideas, reforms, missions, advisors, enforce peace) and what is going wrong (red: deficit, loans, low legitimacy, rebels, force limit). Hover for details, click to jump there."],
	["Sanctum", "Your money. Tax, production and trade bring it in; armies, fleets, forts, advisors, loans and administration cost it every month. Mines on sanctum ore sites dig it straight from the ground. Everything is expensive: spend carefully."],
	["Technology", "Each level has a year. Researching before that year costs 10% more per year early and gives a 10-year 'ahead of time' penalty. The game runs about 500 years, from 4289 to 4789."],
	["Autonomy", "In the early Arcadian era provinces slowly drift away from the capital. Autonomy lowers their tax, production, manpower and trade, but also unrest. Lower it from the province window."],
	["War", "Declare war from a nation's diplomacy window. Your allies do NOT join on their own: call them from the Diplomacy panel. They decide by opinion, the enemy and their own situation, and want sanctum in return. Occupy every province of the enemy and you can enforce peace."],
	["The Black Moon", "Every 29 February the Doomsday Barrier falls. Anomalies tear at Skyfall, then time reverses. Sometimes entities come through the portal and stay. The Order of the Black Moon worships them."],
]

signal closed


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(UI.BG_DARK, UI.GOLD, 8, 16))
	custom_minimum_size = Vector2(720, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UI.row([UI.label("How to play Arcadia", 22, UI.GOLD), UI.spacer(), UI.button("Close (F1)", func(): visible = false; closed.emit())]))
	for s in SECTIONS:
		v.add_child(UI.heading(s[0], 15))
		v.add_child(UI.label(s[1], 13, UI.TEXT, 690))
	visible = false
