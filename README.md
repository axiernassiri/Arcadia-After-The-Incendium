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

**The map** is traced from the Holy Empire of Menslosia lore map: Mentos (the capital) in the north, Sylvania and the Bay of Pigs in the west, Midrea and the Space Observatory in the middle, the Eurome farms in the south, the Western Archipelago mines, the Southwest Island, the Southern Isles, and a lone islet on the equator. 119 mainland provinces plus 21 Skyfall islands (five of them the Black Moon Isles), joined only by the Holy Waterfall of Eden, which now reaches the ground at Equator Isle. Midrea's White Haze starts hidden.

**Nations.** 13, all playable, all starting at 0 stability. The Holy Empire of Menslosia is still the strongest (215 development) but no longer swallows the continent: after the Incendium, Sylvania, the Merchant Republic of the Bay, the Euromean Grain League, the Duchy of Ryefield and the Midrean Technocracy broke away. Skyfall (115) rules the sky, develops 25% cheaper with +10% tax and production while it holds no land on the Arcadian continent, and sits on the richest trade node (goods worth 75% more there), opposed by the Order of the Black Moon, cultists on their own island chain who worship the Doomsday Portal (few troops, little money, high morale). The boars are now different kinds of nation: the Snowtusk and Cinderhoof hordes, the Driftboar Kingdom, the Saltjaw League (a republic) and the Coralsnout Tribe.

**Systems** (EU4 equivalents in brackets):
- **Economy in sanctum**: tax, production, trade and mine income; army, navy, fort, administration, advisor, colony, missionary and loan-interest expenses; maintenance sliders; loans and bankruptcy. Money is tight and everything costs about twice what it used to. Forts are scattered through every nation (the capital's is free, the rest cost upkeep).
- **Mines**: 19 provinces sit on sanctum ore (ore, copper, gems, crystals, salt, sulfur, marble). Build a mine there to dig sanctum out of the ground.
- **Autonomy**: provinces slowly drift away from the capital (0.12 a month, up to 60%) until the realm takes the **Centralise the Realm** decision, available from 4339 (50 years in). Autonomy cuts tax, production, manpower and trade but calms unrest. Lowering or raising it is free, but each province can only be changed once every five years.
- **Decisions**: shown in the Government window, from `data/decisions.json`. The AI takes them too.
- **Coring**: pay admin power and the province becomes a core after 24 months. The Production window's Cores tab lists every uncored province, and an alert tells you when you can core one.
- **Advisors and legitimacy**: hire one advisor for each kind of power from a rotating pool of 13 types; they add power and a bonus but cost a salary. Rulers have legitimacy (republican tradition, devotion or clan cohesion for other governments); low values cost power and stir unrest. Republics hold elections.
- **Production panel (B)**: every province in one list to build, recruit (including special regiments: Unity Guard, Angel Host, Moon Zealots, Boar Raiders, Automaton Battery) and lay down ships.
- **Alerts**: icons under the top bar for things you can do (tech, ideas, reforms, missions, advisors, enforce peace, uncalled allies) and things going wrong (deficit, loans, legitimacy, stability, force limit, manpower, rebels, entities at the portal).
- **Goods and prices**: 31 trade goods. Prices drift every month and fall when the world makes more of a good. Events can shock them.
- **Trade** (trade nodes): seven nodes, seated on the stars of the lore map, flowing toward the Arcadian Sea. Merchants collect or steer; light ships add trade power.
- **Development** costs more in rough terrain (mountains, tundra, volcanic, anomalous) and less on farmland.
- **Buildings** (construction): marketplace, temple, courthouse, workshop, granary, university, dock, trade depot, shipyard, harbour, barracks, fort. They cost sanctum, take months, and need tech and free building slots.
- **Technology**: administrative, diplomatic and military tracks of 25 levels spread 20 years apart over a ~500-year game (4289 to 4789). Base cost 600; each year ahead of time adds 10% and gives a 10-year 'ahead of time' penalty.
- **Ideas**: national ideas for Menslosia, Skyfall, the Black Moon, the pig states, hordes and tribes, plus 15 idea groups drawn from the lore (Green Power, Sty Administration, Lotus Devotion, Haze Expeditions, Waterfall Commerce, Incendium Lessons, Anomaly Studies, Unity Doctrine, Barrier Lore, Wings of Eden...). The first slot comes with the first tech level.
- **Government reforms**: slow to earn (reform progress is half what it was, and tiers cost 75 each); tiers of reforms per government (Holy Pig Monarchy, Edenic Monarchy, pig and boar kingdoms, merchant and farmers' republics, the Technocracy, boar hordes and tribes, the Black Moon cult), paid with reform progress.
- **Modifiers**: every bonus is a named modifier, summed from government, reforms, tech, ideas, religion, buildings, stability and timed event modifiers. The Court panel lists them all.
- **Rulers and heirs**: rulers age and die, heirs are born and inherit, regency councils step in. Napoleon is ageless.
- **Cultures, religions and ethnicities**: 10 cultures in 3 culture groups, 3 faiths, 5 peoples (Pig, Pigman, Boar, Human, Angel). Unaccepted cultures, other faiths and foreign peoples cause unrest. You can accept cultures, convert culture and send missionaries.
- **Cores and overextension**: conquered land must be cored with admin power.
- **Unrest and rebellions**: fewer uprisings than before, but bigger rebel armies. Separatists, zealots and peasants rise when rebel progress fills. If they hold their home province for half a year they win their demands (separatists can free a conquered tribe).
- **Military**: infantry, cavalry and artillery; heavy ships, light ships and transports (Skyfall's are airships that stay in the sky). Recruiting takes time, and there are hard force limits (+50% in wartime), manpower, morale, discipline and attrition. Armies cross sea lanes when your fleets can carry them. Skyfallins without masks suffer below the clouds.
- **Generals and battles**: generals with fire, shock, manoeuvre and siege pips. Battles run day by day in fire and shock phases with dice, terrain and morale; the loser retreats or is wiped out. Sieges take about 100 days per fort level (an unfortified province about a month); artillery (up to five per fort level), siege pips and blockades speed them up. Fleets blockade coasts.
- **Stack wipes, as in EU4**: an army that routs before two fire and two shock phases are over (12 days) while outnumbered 2:1 is destroyed; half its men return to the manpower pool. An army ten times bigger overruns a small one without a battle.
- **Zone of control, as in EU4**: a fort controls its own province and the land next to it. An army inside an enemy fort's zone may only go back where it came from, march on the fort, or move near its return province (the last province outside any zone it left). Occupied land without a fort, next to a fort its owner still holds, goes back to the owner a month after your armies leave, unless you're besieging that fort.
- **War and diplomacy**: casus belli (Tribal Conquest, claims, rivals, the Great War), war declarations, calls to arms (allies only join when you call them; they weigh opinion, the enemy and their own situation and ask for sanctum), war score from battles and occupations, and peace deals (provinces, a share of a year's income, vassalage, annexation, white peace, concessions). The AI is harder to talk into peace, and once you occupy every province of the enemy you can enforce peace. Also opinions with reasons, alliances, royal marriages, military access, rivals, fabricated claims, vassals and integration, and truces.
- **The Black Moon**: on 29 February of every leap year the Doomsday Barrier falls. It only touches nations with land or armies in Skyfall: Menslosia is untouched unless it has landed there. The next day time reverses and the damage is undone. Sometimes entities from beyond come through the portal and stay: an army that raids Skyfall and can seize the portal itself.
- **Missions**: trees for Menslosia (now about reclaiming Sylvania, Midrea and Eurome), Skyfall, the Black Moon, the pig states and the boar nations, drawn as a grid with arrows.
- **Events**: 61 written events plus built-in ones for peace offers and calls to arms: the Photographer incident, the Pig Lord's speech, the Sylvanian Question, pilgrims at the Holy Waterfall, the Barrier Guard, Black Moon preachers, entity invasions, elections, clan feuds, mines, scandals and more.
- **AI**: develops, researches, takes ideas and reforms, builds, recruits, cores, colonises, converts, makes alliances, declares wars on tribes, marches and besieges, and makes peace.
- **Map modes**: Political, Diplomatic, Development, Goods, Trade, Regions, Culture, Religion, Ethnicity, Unrest and Terrain. Occupied land and colonies are striped.

## Look and feel

The UI follows one art direction, *After the Incendium*: charred slate panels with brass trim, parchment text and ember-gold accents.
- **Design tokens** in `ui/style/tokens.gd`: the palette, type scale, spacing and motion timings. Change a colour there, not in the panels.
- **Fonts** in `assets/fonts`: Cinzel for titles and nation names, Alegreya Sans for everything else, with lining tabular figures so numbers line up. Both are under the SIL Open Font License; the license texts sit next to the fonts.
- **Icons**: 48 icons in one style, drawn as SVG in `tools/make_icons.py`, which writes `ui/style/icons.gd`. The game rasterises them at twice the size it needs, so they stay sharp at any window size. Run `python3 tools/make_icons.py --preview sheet.png` after editing.
- **Graphics**: panel frames, button states, the top bar, the heading ornament, the map's paper grain, the vignette and the title emblem come from `tools/make_ui_art.py` (Python with Pillow and numpy) and land in `assets/ui`.
- **Map**: names, army and fleet counters, forts, sieges and battles are drawn on a screen-space layer at whole-pixel sizes, so they stay sharp at every zoom. The shader adds a paper grain, draws nation borders twice as thick as province borders, and makes open water shimmer slowly.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a province, or an army or fleet marker |
| Right click | With your army or fleet selected: move it there. Otherwise: open that nation's diplomacy |
| Drag (any mouse button), WASD or arrow keys | Pan |
| Mouse wheel | Zoom |
| Space | Pause or resume (the pips by the date show the speed) |
| 1 to 5 | Game speed |
| Tab | Switch between the mainland and Skyfall |
| C, G, E, B, T, R, I, L, O, P, M | Court, Government, Economy, Production, Trade, Technology, Ideas, Military, Diplomacy (O), Peoples, Missions |
| F1 | How to play |
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

**Modifier keys** (used by reforms, ideas, tech, buildings, religions and event modifiers): `tax_mod`, `production_mod`, `trade_power_mod`, `trade_efficiency`, `manpower_mod`, `land_maintenance_mod`, `naval_maintenance_mod`, `land_morale`, `naval_morale`, `discipline`, `infantry_power`, `cavalry_power`, `artillery_power`, `fort_defense`, `siege_ability`, `dev_cost_mod`, `tech_cost_mod`, `idea_cost_mod`, `core_cost_mod`, `stability_cost_mod`, `build_cost_mod`, `build_time_mod`, `unrest`, `tolerance_own`, `tolerance_heathen`, `colonists`, `colonist_growth`, `merchants`, `diplomats`, `missionaries`, `missionary_strength`, `diplomatic_reputation`, `improve_relations_mod`, `interest_mod`, `monthly_adm`, `monthly_dip`, `monthly_mil`, `leader_fire`, `leader_shock`, `leader_maneuver`, `leader_siege`, `reinforce_speed`, `land_force_limit`, `naval_force_limit`, `accepted_cultures`, `doomsday_resistance`, `explore_cost_mod`, `legitimacy_gain`, `autonomy_gain`. Province-only keys: `local_tax_mod`, `local_production_mod`, `local_trade_power`, `local_unrest`, `local_manpower_mod`, `local_supply`, `local_core_cost`, `local_dev_cost`, `local_autonomy_gain`, `local_mine_income`.

**Event triggers**: `{"date": "4300-05-01"}`, `{"monthly_chance": 0.05, "conditions": [...]}`, `{"special": "doomsday"}` or `{"special": "fired_by_effect"}`. `for` is a tag, `all`, `player`, `tribes` (tribes and hordes), `republics`, `monarchies`, `pig_states` or `others` (everyone but Menslosia and Skyfall). Any condition can take `"negate": true`.

**Conditions**: `year_at_least`, `flag`, `not_flag` (add `"scope": "global"`), `explored`, `explored_count`, `owns`, `owns_region`, `province_dev_at_least`, `region_dev_at_least`, `provinces_owned_at_least`, `layer_provinces_owned_at_least`, `power_at_least`, `tech_at_least`, `ideas_at_least`, `reforms_at_least`, `has_reform`, `buildings_at_least`, `regiments_at_least`, `ships_at_least`, `treasury_at_least`, `no_loans`, `stability_at_least`, `total_dev_at_least`, `trade_income_at_least`, `trade_share_at_least`, `battles_won_at_least`, `at_war`, `not_at_war`, `nation_dead`, `subjects_at_least`, `allied_with`, `opinion_at_least`, `in_skyfall`, `is_tag`, `culture_provinces_at_least`, `religion_provinces_at_least`, `legitimacy_at_least`, `has_advisors_at_least`, `mines_at_least`, `portal_held_by_entities`, `gov_type`.

**Effects**: `add_power`, `add_treasury`, `add_stability`, `add_manpower`, `add_opinion`, `set_flag`, `clear_flag`, `add_dev`, `reveal`, `fire_event`, `message`, `add_modifier` (with `modifiers` and `months`, -1 = permanent), `add_war_exhaustion`, `add_army_tradition`, `add_reform_progress`, `declare_war`, `add_claim` (a province, or `tag` for all of a nation's land), `add_core`, `spawn_leader`, `price_shock`, `add_legitimacy`, `add_autonomy`, `spawn_entities`.

**Add a nation**: add it to `data/nations.json` and give it provinces in `provinces.json`. Its government, ideas, culture and religion must exist in the other data files.

## Tests

```
godot --headless --path . --import
godot --headless --path . -s tests/sim_test.gd
```

The test checks the map and regions, the nation balance, the waterfall, mine sites, forts, governments, the budget, mines, advisors, legitimacy, autonomy, force limits, special regiments, entities, calls to arms, loans, terrain-based development costs, buildings, tech, ideas, reforms, trade, prices, the Black Moon rule, rulers, rebels, colonies and saving and loading. It also runs a war with peace, and 12 years of AI play.

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
