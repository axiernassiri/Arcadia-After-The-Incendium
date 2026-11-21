# Arcadia: grand strategy prototype

A Godot 4 grand strategy game in the spirit of Europa Universalis IV, built on the Arcadian lore.
You play a nation of the First World from 1 January 4289, right after the Incendium.

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build; no .NET needed).
2. Open Godot, choose **Import**, and pick `project.godot` in this folder.
3. Press **F5** (Run Project).

The first time you open the project, Godot imports the map images; that takes a few seconds.

To run the automated test on Windows, put the console build of Godot in your Downloads or Desktop folder and double-click `run_tests.bat`.

## What's in it

**Screens.** A main menu (new game, continue, load, quit), the Incendium opening cutscene, and a nation picker drawn over the live map: click a nation in the list or on the map to see its ruler, government, peoples, army, national ideas and difficulty. In game, Esc opens the menu to save, load, return to the main menu or quit.

**The map** is traced from the Holy Empire of Menslosia lore map: Mentos (the capital) in the north, Sylvania and the Bay of Pigs in the west, Midrea and the Space Observatory in the middle, the Eurome farms in the south, the Western Archipelago mines, the Southwest Island, the Southern Isles, and a lone islet on the equator. 119 mainland provinces plus 16 Skyfall islands, joined only by the Holy Waterfall of Eden. Midrea's White Haze starts hidden.

**Nations.** Menslosia (easy), Skyfall (normal), and four native boar tribes on land Menslosia hasn't conquered: the Snowtusk Clans (northeast Mentos), the Saltjaw Islanders (Western Archipelago), the Driftboar Tribe (Southwest Island) and the Coralsnout Tribe (Southern Isles). All six are playable.

**Systems** (EU4 equivalents in brackets):
- **Economy in sanctum**: tax, production and trade income; army, navy, fort, administration, colony, missionary and loan-interest expenses; maintenance sliders; loans and bankruptcy. The Economy panel shows it all, with the treasury over time.
- **Goods and prices**: 31 trade goods. Prices drift every month and fall when the world makes more of a good. Events can shock them.
- **Trade** (trade nodes): seven nodes, seated on the stars of the lore map, flowing toward the Arcadian Sea. Merchants collect or steer; light ships add trade power.
- **Development** costs more in rough terrain (mountains, tundra, volcanic, anomalous) and less on farmland.
- **Buildings** (construction): marketplace, temple, courthouse, workshop, granary, university, dock, trade depot, shipyard, harbour, barracks, fort. They cost sanctum, take months, and need tech and free building slots.
- **Technology**: administrative, diplomatic and military tracks of 15 levels, with an early-research penalty.
- **Ideas**: national ideas for Menslosia, Skyfall and the tribes, plus 13 idea groups in idea slots.
- **Government reforms**: tiers of reforms per government type (Holy Pig Monarchy, Edenic Monarchy, Boar Tribe), paid with reform progress.
- **Modifiers**: every bonus is a named modifier, summed from government, reforms, tech, ideas, religion, buildings, stability and timed event modifiers. The Court panel lists them all.
- **Rulers and heirs**: rulers age and die, heirs are born and inherit, regency councils step in. Napoleon is ageless.
- **Cultures, religions and ethnicities**: 10 cultures in 3 culture groups, 3 faiths, 5 peoples (Pig, Pigman, Boar, Human, Angel). Unaccepted cultures, other faiths and foreign peoples cause unrest. You can accept cultures, convert culture and send missionaries.
- **Cores and overextension**: conquered land must be cored with admin power.
- **Unrest and rebellions**: separatists, zealots and peasants rise when rebel progress fills. If they hold their home province for half a year they win their demands (separatists can free a conquered tribe).
- **Military**: infantry, cavalry and artillery; heavy ships, light ships and transports (Skyfall's are airships that stay in the sky). Recruiting takes time, and there are force limits, manpower, morale, discipline and attrition. Armies cross sea lanes when your fleets can carry them. Skyfallins without masks suffer below the clouds.
- **Generals and battles**: generals with fire, shock, manoeuvre and siege pips. Battles run day by day in fire and shock phases with dice, terrain and morale; the loser retreats or is wiped out. Sieges need more men and artillery against bigger forts; fleets blockade coasts.
- **War and diplomacy**: casus belli (Tribal Conquest, claims, rivals, the Great War), war declarations with calls to arms, war score from battles and occupations, and peace deals (provinces, sanctum, vassalage, annexation, white peace, concessions). Also opinions with reasons, alliances, royal marriages, military access, rivals, fabricated claims, vassals and integration, and truces.
- **The Black Moon**: on 29 February of every leap year the Doomsday Barrier falls. It only touches nations with land or armies in Skyfall: Menslosia is untouched unless it has landed there. The next day time reverses and the damage is undone.
- **Missions**: a mission tree of 25 missions for Menslosia, 14 for Skyfall and 8 shared by the tribes, drawn as a grid with arrows.
- **Events**: 20 written events plus built-in ones for peace offers and calls to arms, including the Photographer incident that starts the Great War, rulers and heirs, rebellions, harvests and the Core surging.
- **AI**: develops, researches, takes ideas and reforms, builds, recruits, cores, colonises, converts, makes alliances, declares wars on tribes, marches and besieges, and makes peace.
- **Map modes**: Political, Diplomatic, Development, Goods, Trade, Regions, Culture, Religion, Ethnicity, Unrest and Terrain. Occupied land and colonies are striped.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a province, or an army or fleet marker |
| Right click | With your army or fleet selected: move it there. Otherwise: open that nation's diplomacy |
| Drag (any mouse button), WASD or arrow keys | Pan |
| Mouse wheel | Zoom |
| Space | Pause or resume |
| 1 to 5 | Game speed |
| Tab | Switch between the mainland and Skyfall |
| C, G, E, T, R, I, L, O, P, M | Court, Government, Economy, Trade, Technology, Ideas, Military, Diplomacy (O), Peoples, Missions |
| Esc | Close panels, then open the menu |
| Home | Fit the map to the screen |

Clicks and scrolling on a panel never reach the map, and panels no longer close when you press their buttons.

## Project layout

```
data/                 Game content as JSON: edit these to change the game, no code needed
  nations.json        Nations: colours, rulers, heirs, government, culture, starting army and fleet
  provinces.json      Every province: name, region, owner, terrain, goods, development, culture, faith, people, trade node
  goods.json          Trade goods: base price, volatility, map colour
  terrain.json        Terrain: development cost, movement, defence, supply, building slots
  buildings.json      Buildings
  technology.json     The three tech tracks
  ideas.json          Idea groups and national ideas
  governments.json    Government types and reform tiers
  units.json          Regiments and ships
  peoples.json        Cultures, culture groups, ethnicities, religions, rebel types
  trade.json          Trade nodes and how trade flows
  events.json         Events, with triggers, options and effects
  missions.json       Mission trees (column and row place each mission)
  cutscene.json       The Incendium opening
map/source/           The lore map and the masks traced from it (land_mask.png, region_mask.png)
map/                  Generated province maps (don't edit by hand except *_provinces.png)
scripts/
  game_state.gd       Autoload "Game": calendar, data, events, missions, effects, Doomsday, saving
  sim/                One file per system: modifiers, economy, trade, progression (tech, ideas,
                      reforms), court (rulers), population (cultures, unrest, rebels), military,
                      diplomacy, ai
  map_view.gd         Map drawing, map modes, picking, army and fleet markers
  map_camera.gd       Pan and zoom
  main.gd             Screens, panels and input; also automation flags for tests and screenshots
  ui/                 One script per panel (panel_base.gd is the shared window)
shaders/map.gdshader  Province colouring, borders, occupation stripes, selection, the Doomsday tint
tests/sim_test.gd     Headless test of every system (53 checks)
tools/                trace_lore_map.py (lore map to masks), generate_map.py (masks to provinces)
run_tests.bat/.ps1    Windows: run the test by double-clicking
```

The simulation has no UI code. The UI listens to its signals and calls its action functions, so the whole game runs headless too.

## Redrawing the map

1. Replace `map/source/lore_map.png` with a new drawing, or paint `map/source/land_mask.png` (white land on black) and `map/source/region_mask.png` (one colour per region; the colours are listed in `tools/trace_lore_map.py`) yourself.
2. If you replaced the drawing, run `python3 tools/trace_lore_map.py`. It needs Python 3 with numpy, scipy, scikit-image and Pillow. It finds the land and region outlines. The region boundary lines at the top of the script are traced by hand for the current map, so adjust them for a new one.
3. Run `python3 tools/generate_map.py --force-provinces`. Lore names (Mentos, Bay of Pigs, Space Observatory, White Haze...) are placed by the anchors at the top of the script; other province names come from name pools per region. Without `--force-provinces`, your hand edits to `data/provinces.json` are kept, but then the province count and order must not change.

## Extending with data

**Modifier keys** (used by reforms, ideas, tech, buildings, religions and event modifiers): `tax_mod`, `production_mod`, `trade_power_mod`, `trade_efficiency`, `manpower_mod`, `land_maintenance_mod`, `naval_maintenance_mod`, `land_morale`, `naval_morale`, `discipline`, `infantry_power`, `cavalry_power`, `artillery_power`, `fort_defense`, `siege_ability`, `dev_cost_mod`, `tech_cost_mod`, `idea_cost_mod`, `core_cost_mod`, `stability_cost_mod`, `build_cost_mod`, `build_time_mod`, `unrest`, `tolerance_own`, `tolerance_heathen`, `colonists`, `colonist_growth`, `merchants`, `diplomats`, `missionaries`, `missionary_strength`, `diplomatic_reputation`, `improve_relations_mod`, `interest_mod`, `monthly_adm`, `monthly_dip`, `monthly_mil`, `leader_fire`, `leader_shock`, `leader_maneuver`, `leader_siege`, `reinforce_speed`, `land_force_limit`, `naval_force_limit`, `accepted_cultures`, `doomsday_resistance`, `explore_cost_mod`. Province-only keys: `local_tax_mod`, `local_production_mod`, `local_trade_power`, `local_unrest`, `local_manpower_mod`, `local_supply`, `local_core_cost`, `local_dev_cost`.

**Event triggers**: `{"date": "4300-05-01"}`, `{"monthly_chance": 0.05, "conditions": [...]}`, `{"special": "doomsday"}` or `{"special": "fired_by_effect"}`. `for` is a tag, `all`, `tribes` or `player`.

**Conditions**: `year_at_least`, `flag`, `not_flag` (add `"scope": "global"`), `explored`, `explored_count`, `owns`, `owns_region`, `province_dev_at_least`, `region_dev_at_least`, `provinces_owned_at_least`, `layer_provinces_owned_at_least`, `power_at_least`, `tech_at_least`, `ideas_at_least`, `reforms_at_least`, `has_reform`, `buildings_at_least`, `regiments_at_least`, `ships_at_least`, `treasury_at_least`, `no_loans`, `stability_at_least`, `total_dev_at_least`, `trade_income_at_least`, `trade_share_at_least`, `battles_won_at_least`, `at_war`, `not_at_war`, `nation_dead`, `subjects_at_least`, `allied_with`, `opinion_at_least`, `in_skyfall`, `is_tag`, `culture_provinces_at_least`, `religion_provinces_at_least`.

**Effects**: `add_power`, `add_treasury`, `add_stability`, `add_manpower`, `add_opinion`, `set_flag`, `clear_flag`, `add_dev`, `reveal`, `fire_event`, `message`, `add_modifier` (with `modifiers` and `months`, -1 = permanent), `add_war_exhaustion`, `add_army_tradition`, `add_reform_progress`, `declare_war`, `add_claim`, `add_core`, `spawn_leader`, `price_shock`.

**Add a nation**: add it to `data/nations.json` and give it provinces in `provinces.json`. Its government, ideas, culture and religion must exist in the other data files.

## Tests

```
godot --headless --path . --import
godot --headless --path . -s tests/sim_test.gd
```

The test checks the map and regions, the tribes, the budget, loans, terrain-based development costs, buildings, tech, ideas, reforms, trade, prices, the Black Moon rule, rulers, rebels, colonies and saving and loading. It also runs a war with peace, and 12 years of AI play.

Screenshots and a UI stress test can run without a display on Linux (with Xvfb):

```
xvfb-run godot --path . --rendering-driver opengl3 -- --nation=MEN --panel=economy --screenshot=economy.png
xvfb-run godot --path . --rendering-driver opengl3 -- --nation=MEN --soak=40
```

The other automation flags are listed at the top of `scripts/main.gd`.

## Lore notes and placeholders

- Region names, Mentos as the capital, the Bay of Pigs, the Space Observatory, the farms and the mines come from the lore map. The trade node seats are its yellow stars; my guess is that the stars mark ports.
- Most province names (Pigwood, Grainhold, Ore Isle...) are placeholders, as are the tribe names, the Lotus Faith, the Mud Spirits and the ruler names other than the Pig Lord and Napoleon.
- Not yet built: several universes on one map (the lore's other worlds, as separate continents). The data has room for more nations and regions when that comes.
