extends RefCounted
## Player preferences, kept in user://settings.cfg (not in save games).
## Usage: const Settings = preload("res://scripts/settings.gd"); Settings.get_value("autosave")

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"pause_on_news": true,      # pause and show a popup for wars, peace and bankruptcy
	"autosave": "yearly",       # off | monthly | yearly
	"fullscreen": false,
	"ui_scale": 1.0,            # 0.8 .. 1.5, scales every window and the HUD
	"edge_scroll": false,       # pan when the mouse touches the screen edge
	"master_volume": 0.8,       # 0..1, applied by the Sound autoload
	"music_volume": 0.5,
	"sfx_volume": 0.8,
	"player_name": "",          # your name in multiplayer games (empty: the computer's user name)
}
const AUTOSAVE_SLOTS := 3

static var _cfg: ConfigFile = null


static func _load() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	_cfg.load(PATH)   # a missing file just leaves the defaults


static func get_value(key: String) -> Variant:
	_load()
	return _cfg.get_value("game", key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_load()
	_cfg.set_value("game", key, value)
	_cfg.save(PATH)


static func apply(tree: SceneTree) -> void:
	## Apply the display settings (call at start-up and after a change).
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and not (mode == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(mode)
	tree.root.content_scale_factor = clampf(float(get_value("ui_scale")), 0.8, 1.5)
