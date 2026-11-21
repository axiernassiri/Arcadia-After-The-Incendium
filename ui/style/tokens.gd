extends RefCounted
## Arcadia's design tokens: the single source for colour, type, spacing and motion.
##
## Art direction, "After the Incendium": a war-room table after the fire. Charred slate and ink
## panels, burnished brass trim, parchment-coloured text, ember gold for what matters. Titles and
## nation names are carved Roman capitals (Cinzel); everything you read or count is a warm humanist
## sans (Alegreya Sans) with lining, tabular figures so columns of numbers line up.
## The generated textures in assets/ui (tools/make_ui_art.py) use the same colours.
##
## Usage: const Tokens = preload("res://ui/style/tokens.gd")

# --- palette ---------------------------------------------------------------------------------
const INK := Color("#0a0b0e")            # darkest: outlines, shadows, text outlines
const BG := Color(0.082, 0.094, 0.118, 0.96)    # window background
const BG_DARK := Color(0.055, 0.06, 0.075, 0.97)  # bars, tooltips
const BG_CARD := Color("#22262e")        # raised surface inside a window
const BORDER := Color("#9c844f")         # brass trim
const BORDER_DIM := Color("#6e5c3a")
const TEXT := Color("#ece3cf")           # parchment
const TEXT_DIM := Color("#a69e8c")
const TEXT_FAINT := Color("#6f6a5f")
const GOLD := Color("#f0c66e")           # accent: titles, selection, the important number
const GOLD_HI := Color("#ffe3a3")
const GOOD := Color("#8fd47e")
const BAD := Color("#ee7a6c")
const WARN := Color("#f0a85a")
const INFO := Color("#8dbcef")
const DOOM := Color("#c48bff")           # the Black Moon, entities

# --- type ------------------------------------------------------------------------------------
const SIZE_SMALL := 12
const SIZE_BODY := 14
const SIZE_LARGE := 16
const SIZE_TITLE := 20
const SIZE_DISPLAY := 30

# --- spacing, shape --------------------------------------------------------------------------
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24
const SP_6 := 32
const RADIUS := 4
const BORDER_W := 1

# --- motion ----------------------------------------------------------------------------------
const DUR_FAST := 0.08
const DUR_NORMAL := 0.15
const DUR_SLOW := 0.3

# --- fonts -----------------------------------------------------------------------------------
static var _fonts := {}


static func _tag(name: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(name)


static func font(kind: String = "body") -> Font:
	## "body", "medium", "bold", "title" (Cinzel bold), "title_regular", "map_nation" (Cinzel, spaced),
	## "map_label" (bold sans for province names and counters).
	if _fonts.has(kind):
		return _fonts[kind]
	var f = FontVariation.new()
	var figures = {_tag("lnum"): 1, _tag("tnum"): 1}
	match kind:
		"body":
			f.base_font = load("res://assets/fonts/AlegreyaSans-Regular.ttf")
			f.opentype_features = figures
		"medium":
			f.base_font = load("res://assets/fonts/AlegreyaSans-Medium.ttf")
			f.opentype_features = figures
		"bold", "map_label":
			f.base_font = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
			f.opentype_features = figures
		"title":
			f.base_font = load("res://assets/fonts/Cinzel-Variable.ttf")
			f.variation_opentype = {_tag("wght"): 700}
		"title_regular":
			f.base_font = load("res://assets/fonts/Cinzel-Variable.ttf")
			f.variation_opentype = {_tag("wght"): 500}
		"map_nation":
			f.base_font = load("res://assets/fonts/Cinzel-Variable.ttf")
			f.variation_opentype = {_tag("wght"): 700}
			f.spacing_glyph = 3
		_:
			return font("body")
	_fonts[kind] = f
	return f
