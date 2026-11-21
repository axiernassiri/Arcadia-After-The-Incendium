# Arcadia event codex

Every Menslosia and Skyfall event: when it can fire, what it needs, and what each choice does. Generated from `data/events.json` by `tools/event_codex.py`.

## Menslosia (39 events)

### A Letter from Napoleon (once)
`men_napoleon_letter` · years 4289–4310 · Mean time to happen: 30 months
- Needs: allied with Skyfall
- **Reply warmly.** +30 opinion with Skyfall
- **Ask him about the tank.** +40 Unity, -10 opinion with Skyfall

### A Signal from the Stars (once)
`men_space_signal` · years 4289– · Mean time to happen: 48 months
- Needs: owns Space Observatory; ADM tech 5
- **Study it.** +100 Lotus, sets flag “star signal”
- **Tell no one.** +1 stability

### Drills at Unity
`men_unity_drills` · years 4289– · Mean time to happen: 40 months; ×0.6 if at war
- Needs: owns Unity
- **Good. Keep them sharp.** +8 army tradition
- **Too costly in peacetime.** +40 sanctum, -3 army tradition

### Execution in the Sky
`photographer_executed` · years via a chain · Fired by another event
- **Declare the Great War for Arcadia.** sets flag “great war”, clears flag “allied SKY”, declares war on Skyfall
- **Swallow our pride. For now.** -2 stability, +50 Lotus

### Fire at Sty Royal (once)
`men_sty_royal_fire` · years 4289– · Mean time to happen: 120 months
- Needs: owns Sty Royal
- **Rebuild it grander than before.** -120 sanctum, +10 legitimacy
- **Leave the ruin as a memorial to the Incendium.** +1 stability

### Grain Shortage
`men_grain_shortage` · years 4289– · Mean time to happen: 72 months; ×0.5 if at war
- Needs: not: Grain League conquered or a subject
- **Buy grain from the Grain League.** -80 sanctum, +15 opinion with Grain League
- **Ration it.** -1 stability, -500 manpower

### Green Engineers (once)
`men_green_engineers` · years 4289– · 0.6% chance a month
- Needs: ADM tech 2
- **Build more.** “Imperial Windmills”: production mod +8% for 15 years, -50 sanctum

### Out of the Haze (once)
`men_white_haze_return` · years 4289– · Mean time to happen: 36 months
- Needs: has explored White Haze
- **Pension them quietly.** -30 sanctum, +60 Accord
- **Question them.** leads to “What the Haze Hides” after 20 days

### Parade in Unity
`men_unity_parade` · years 4289– · 0.8% chance a month
- Needs: 15 regiments
- **Glorious!** +5 legitimacy, +5 army tradition

### Strike on Ore Isle
`men_ore_isle_strike` · years 4289– · Mean time to happen: 60 months
- Needs: owns Ore Isle; 1 mines
- **Pay them.** -50 sanctum, +1 stability
- **Send the Unity Guard.** -1 stability, +3 army tradition

### The Black Moon Rises over Our Troops
`doomsday_men` · years 4289– · When the Black Moon rises (29 February of leap years)
- **Join the Barrier Pact: fight beside Skyfall.** -40 Unity, +25 opinion with Skyfall, sets flag “barrier pact”, +1 stability
- **Exploit the chaos: study the anomalies in Midrea's labs.** +60 Accord, -40 opinion with Skyfall, -1 stability, sets flag “studied anomalies”
- **Pull our soldiers back and wait for the dawn.** -3000 manpower

### The Canada Ruins (once)
`men_canada_ruins` · years 4289–4300 · Mean time to happen: 18 months
- **Open it in the Pig Lord's presence.** leads to “The Vault of the Old World” after 30 days
- **Seal it again. Some things should stay buried.** +1 stability

### The Empire Whole Again (once)
`men_empire_restored_parade` · years 4289– · Mean time to happen: 6 months
- Needs: owns all of Sylvania; owns all of Eurome
- **Glory to the Pig Lord!** +2 stability, +20 legitimacy, +10 army tradition

### The First Harvest After the Ash (once)
`men_ash_harvest` · years 4289–4292 · Mean time to happen: 6 months
- **Give thanks at the Lotus temples.** +1 stability, +5 legitimacy
- **Sell the surplus to the mainland.** +90 sanctum

### The Heir's Ambition
`men_heir_rebellion` · years 4289– · Mean time to happen: 240 months; ×0.3 if not: legitimacy 80
- Needs: legitimacy 0
- **Disband the guard.** +5 legitimacy, -500 manpower
- **Give him a command in the Unity Guard.** +5 army tradition, -5 legitimacy

### The Imperial Cartographers (once)
`men_cartographers` · years 4289–4340 · Mean time to happen: 48 months
- **Fund them.** -60 sanctum, +60 Accord
- **Old maps will do.** 

### The Old Bureaucracy
`men_old_bureaucracy` · years 4289– · 0.6% chance a month
- Needs: 20 provinces
- **Clean house.** -60 Lotus, “Clean Bureaucracy”: tax mod +10% for 10 years
- **It works, more or less.** +5 autonomy everywhere

### The Photographer's Pictures (once)
`men_photographer_trial` · years 4289– · Mean time to happen: 24 months
- Needs: flag “photographer pardoned”
- **Burn the papers.** +20 opinion with Skyfall, -5 legitimacy
- **Let the people see the sky islands.** +50 Accord, -30 opinion with Skyfall

### The Pigman Engineers' Guild (once)
`men_pigman_guild` · years 4289– · Mean time to happen: 36 months
- Needs: ADM tech 2
- **Grant the charter.** “Engineers' Guild”: build cost mod -10%, -5 legitimacy
- **They serve the Pig Lord, not a guild.** +5 legitimacy, -25 Lotus

### The Schism Healed
`men_lotus_schism_end` · years via a chain · Fired by another event
- **Let the bells ring.** +2 stability, +10 legitimacy

### The Skyfall Embassy (once)
`men_skyfall_embassy` · years 4289– · 0.6% chance a month
- Needs: allied with Skyfall
- **Host a feast for the angels.** -40 sanctum, +40 opinion with Skyfall
- **Ask for their scholars.** +40 Lotus

### The Truffle Baron's Loan
`men_truffle_baron` · years 4289– · Mean time to happen: 48 months; ×0.5 if 400 sanctum
- Needs: owns Truffle Downs
- **Take his sanctum and give him the seat.** +200 sanctum, -10 legitimacy
- **The court is not for sale.** +5 legitimacy

### The Vault of the Old World
`men_canada_vault` · years via a chain · Fired by another event
- **The seeds go to the farms.** “Seeds of the Old World”: production mod +5%, manpower mod +5%
- **The books go to Midrea.** +80 Lotus, +40 Accord

### What the Haze Hides
`men_haze_secret` · years via a chain · Fired by another event
- **Mark it on our maps.** reveals The Center, +30 Accord

### A Feast at Eden's Crown (once)
`skyfall_feast` · years 4290– · 3.0% chance a month
- Needs: allied with Skyfall; from 4290
- **Accept with thanks.** +20 opinion with Skyfall, -30 sanctum
- **Send a gift instead.** +10 opinion with Skyfall, -50 sanctum

### Envoys from the Breakaway States (once)
`men_breakaway_envoys` · years 4290–4330 · Mean time to happen: 36 months
- Needs: not: Sylvania conquered or a subject
- **Never. They are Menslosian.** +5 legitimacy, -20 opinion with Sylvania, -20 opinion with Bay of Pigs, -20 opinion with Grain League
- **Recognise them, for now.** +1 stability, +40 opinion with Sylvania, +40 opinion with Bay of Pigs, +40 opinion with Grain League, -10 legitimacy

### The Pig Lord Speaks (once)
`men_pig_lord_speech` · years 4290– · 1.0% chance a month
- Needs: from 4290; no flag “pig lord speech”
- **Reclaim what is ours!** sets flag “pig lord speech”, “Reclamation Fervour”: land morale +10%, core cost mod -15% for 10 years
- **Peace first. Then we rebuild.** sets flag “pig lord speech”, +1 stability, +50 Lotus

### Truffle Rush
`truffle_rush` · years 4290– · 1.0% chance a month
- Needs: from 4290
- **Let them dig!** truffles prices ×1.4, +40 sanctum
- **Back to work, everyone.** +25 Lotus

### The Photographer (once)
`photographer_incident` · years 4291– · 15.0% chance a month
- Needs: from 4291; has explored 3 sky provinces; no flag “great war”
- **Demand his return. He is a pig of Menslosia!** -30 opinion with Skyfall, leads to “Execution in the Sky” after 20 days
- **Apologise and pay for his release.** -80 sanctum, +10 opinion with Skyfall, sets flag “photographer freed”, sets flag “photographer pardoned”

### The Sylvanian Question (once)
`men_sylvanian_question` · years 4291– · 1.0% chance a month
- Needs: from 4291; no flag “sylvania question”; not: Sylvania is gone
- **Prepare for war.** sets flag “sylvania question”, claims on Sylvania, -50 Unity
- **Win them back with gifts.** sets flag “sylvania question”, +50 opinion with Sylvania, -80 sanctum

### Pilgrims to Lotus Vale
`men_lotus_pilgrims` · years 4292– · 0.8% chance a month
- Needs: from 4292
- **Tax the pilgrim roads.** +70 sanctum, -1 stability
- **Feed them for free.** -30 sanctum, +10 legitimacy, +1 stability

### The Caldera Rumbles
`men_yellowstone_rumble` · years 4295– · Mean time to happen: 60 months
- Needs: from 4295
- **Evacuate the borderlands.** -60 sanctum, +1 stability
- **Pray to the Lotus. It is only the earth settling.** “Fear of the Caldera”: unrest +1 for 2 years

### The Heir's Education
`men_heir_education` · years 4295– · 0.5% chance a month
- Needs: from 4295
- **The finest scholars.** -50 sanctum, +50 Lotus
- **The army will teach him.** +10 army tradition

### The Great Windfarm (once)
`men_green_power_plant` · years 4300– · Mean time to happen: 60 months; ×0.5 if 3 ideas
- Needs: ADM tech 3
- **Build it.** -150 sanctum, “The Great Windfarm”: production mod +10%, build cost mod -5%
- **Not yet.** 

### The Lotus Schism (once)
`men_lotus_schism` · years 4300–4400 · Mean time to happen: 200 months; ×0.5 if stability -3 and legitimacy 0
- **Back the old priest of Lotus Vale.** -1 stability, +60 Lotus, leads to “The Schism Healed” after 365 days
- **Back the young reformer from Mentos.** +60 Accord, -10 legitimacy, leads to “The Schism Healed” after 365 days

### The Truffle Wars
`men_truffle_war` · years 4300– · 0.4% chance a month
- Needs: from 4300
- **Send the army.** -30 Unity, +1 stability
- **Let them fight it out.** +5 autonomy everywhere, +40 sanctum

### The Pig Lord's Jubilee (once)
`men_pig_lord_jubilee` · years 4314–4316 · Mean time to happen: 6 months
- **Spare no expense.** -200 sanctum, +2 stability, +15 legitimacy
- **A modest feast.** +1 stability

### The Governors' Revolt (once)
`men_centralisation_riots` · years 4339–4380 · Mean time to happen: 12 months
- Needs: flag “centralised”
- **Crush them.** -1 stability, +5 army tradition, -5 autonomy everywhere
- **Buy them off.** -150 sanctum, +1 stability

### The Menslosian Renaissance (once)
`men_menslosian_renaissance` · years 4350– · Mean time to happen: 120 months
- Needs: stability +2; ADM tech 5
- **Patronise the arts.** -100 sanctum, “The Menslosian Renaissance”: monthly dip +1, tech cost mod -5% for 20 years
- **Patronise the sciences.** -100 sanctum, “The Menslosian Renaissance”: monthly adm +1, tech cost mod -5% for 20 years

## Skyfall (36 events)

### A Bridge of Water (once)
`sky_waterfall_bridge` · years 4289– · Mean time to happen: 60 months
- Needs: DIP tech 4; owns Equator Isle
- **Build the lift.** -200 sanctum, “The Waterfall Lift”: trade efficiency +10%, trade power mod +10%
- **The Waterfall is holy. No machines.** +5 legitimacy

### An Island Drifts
`sky_island_drifts` · years 4289– · Mean time to happen: 200 months; ×0.5 if not: stability +1
- **Anchor it with Core cables.** -80 sanctum
- **Let it find its own place.** -1 development in Halo Isle

### Black Moon Preachers
`sky_cult_preachers` · years 4289– · 1.2% chance a month
- Needs: not: Black Moon is gone
- **Arrest them.** -5 legitimacy, +1 stability
- **Let them talk. No one listens.** “Cult Whispers”: unrest +1 for 3 years

### Core Overload
`sky_core_overload` · years 4289– · Mean time to happen: 180 months
- Needs: Eden's Crown at 25 development
- **Vent the excess into the Waterfall.** “Core Vented”: production mod +10% for 5 years
- **Let it burn.** +100 Core, “Core Overload”: unrest +1 for 2 years

### Pilgrims at the Holy Waterfall
`sky_waterfall_pilgrims` · years 4289– · 1.0% chance a month
- Needs: owns Equator Isle
- **Let them come.** +60 sanctum, +15 opinion with Menslosia
- **The waters are sacred. Close the shore.** +10 legitimacy

### The Angel Exodus
`sky_angel_exodus` · years 4289– · Mean time to happen: 120 months
- Needs: not: stability +0
- **Promise reforms.** -20 reform progress, +1 stability
- **Let them go.** -1000 manpower, +10 opinion with Black Moon

### The Black Moon Rises
`doomsday_sky` · years 4289– · When the Black Moon rises (29 February of leap years)
- **Hold the Barrier alone, by the Will of Eden.** -50 Wings, +1 stability, +40 Core
- **Call on Menslosia for the Barrier Pact.** +15 opinion with Menslosia, -30 Eden, sets flag “barrier pact”
- **Cast holy spells on everything that moves.** -20 Wings, -1500 manpower, sets flag “holy spells unleashed”, +10 army tradition

### The Book of Flight
`sky_book_found` · years via a chain · Fired by another event
- **Teach it to every soldier.** “The Book of Flight”: land morale +10%, leader maneuver +1, sets flag “book of flight”
- **Lock it in Eden's library.** +100 Core, sets flag “book of flight”

### The Census of Eden (once)
`sky_eden_census` · years 4289–4310 · Mean time to happen: 48 months
- **Count everyone.** +40 Core, +500 manpower
- **The angels refuse to be counted.** -5 legitimacy, +1 stability

### The Cloud Cotton Boom
`sky_cloud_cotton_boom` · years 4289– · Mean time to happen: 60 months
- Needs: owns Windward Isle
- **Raise the export tariff.** +150 sanctum
- **Flood the market.** cloud cotton prices ×1.4, “Cloud Cotton Boom”: trade efficiency +10% for 5 years

### The Core Flickers
`sky_core_flicker` · years 4289– · Mean time to happen: 90 months; ×0.5 if not: Eden's Crown at 20 development
- **Pour sanctum into the Core.** -100 sanctum, +1 stability
- **Pray it holds.** -1 stability, “Doubts about the Core”: unrest +1 for 2 years

### The Emperor's Birthday (once)
`sky_napoleon_birthday` · years 4289–4300 · Mean time to happen: 12 months
- **A grand ball at Eden's Crown.** -60 sanctum, +10 legitimacy
- **A military parade.** +10 army tradition

### The Feather Market
`sky_feathers_fashion` · years 4289– · Mean time to happen: 90 months
- **Forbid it.** +5 legitimacy, -30 sanctum
- **Tax it.** +80 sanctum, -5 legitimacy

### The Moonblade
`sky_cult_assassin` · years 4289– · Mean time to happen: 96 months; ×0.5 if at war
- Needs: not: Black Moon is gone
- **Execute him publicly.** +5 legitimacy, -50 opinion with Black Moon
- **Turn him: he will spy for us.** +60 Eden, claims on Black Moon

### The Staircase Climbers (once)
`sky_staircase_climb` · years 4289– · Mean time to happen: 48 months
- Needs: owns Staircase Spire
- **Send scholars with them.** +40 Eden, leads to “The Book of Flight” after 90 days
- **Close the stair.** +1 stability

### The Thing in the Cage (once)
`sky_entity_survivor` · years 4289– · Mean time to happen: 24 months
- Needs: flag “entities came”; not: entities hold the portal
- **Study it.** +80 Core, “Study of the Entities”: doomsday resistance +30%
- **Throw it back through the portal.** +1 stability

### We Can Breathe Below
`sky_mask_success` · years via a chain · Fired by another event
- **A new age for Eden.** sets flag “breathing masks”, +50 Eden

### Whispers at the Portal
`sky_portal_whispers` · years 4289– · Mean time to happen: 36 months; ×0.5 if not: Black Moon is gone
- Needs: owns Portal Isle
- **Rotate the guard more often.** -500 manpower, “Fresh Guards”: doomsday resistance +20% for 5 years
- **Ignore it. Voices can't hurt anyone.** “Voices at the Portal”: unrest +1 for 3 years

### Mask Trials at Equator Isle (once)
`sky_mask_trials` · years 4290–4330 · Mean time to happen: 24 months; ×0.5 if owns Equator Isle
- Needs: no flag “breathing masks”
- **Fund the trials.** -80 sanctum, leads to “We Can Breathe Below” after 120 days
- **Too dangerous.** 

### Masks for the Mainland (once)
`eden_masks` · years 4290– · 8.0% chance a month
- Needs: from 4290; no flag “breathing masks”
- **Fund the masks.** -60 sanctum, sets flag “breathing masks”
- **Skyfall belongs in the sky.** +1 stability

### Omens of the Black Moon
`sky_black_moon_omen` · years 4290– · Mean time to happen: 18 months; ×0.5 if flag “entities came”
- **Double the Barrier Guard.** -1000 manpower, “Doubled Barrier Guard”: doomsday resistance +30% for 4 years
- **Astronomers always say that.** 

### Scraps and Blueprints (once)
`napoleons_blueprints` · years 4290– · 5.0% chance a month
- Needs: from 4290
- **Begin the war machine project.** sets flag “tank project”, -30 Wings, “War Machine Project”: artillery power +10%
- **Too much power for anyone. Lock them away.** +1 stability

### The Barrier Guard
`sky_barrier_guard` · years 4290– · 0.8% chance a month
- Needs: from 4290
- **Send them our best.** -1000 manpower, “Strengthened Barrier Guard”: doomsday resistance +30% for 10 years
- **We need them at home.** -1 stability

### The Core Surges
`core_surge` · years 4290– · 1.0% chance a month
- Needs: from 4290
- **Put the power to work.** “Core Surge”: production mod +15% for 1 years, core energy prices ×0.8
- **Store it for the Black Moon.** “Core Reserve”: doomsday resistance +25% for 5 years

### The Gardens of Eden (once)
`sky_eden_gardens` · years 4291– · 0.6% chance a month
- Needs: from 4291
- **Open them to all.** +1 stability, +5 legitimacy
- **Sell their fruit.** +80 sanctum

### The Emperor's Tank (once)
`sky_napoleons_tank` · years 4292–4330 · Mean time to happen: 36 months
- Needs: no flag “tank project”; owns Napoleon's Foundry
- **Build it.** -150 sanctum, sets flag “tank project”, “The Tank Project”: artillery power +10%
- **Steel is for swords.** +5 army tradition

### The Wing Trials
`sky_wing_trials` · years 4292– · 0.6% chance a month
- Needs: from 4292
- **Recruit the winners.** +10 army tradition, +500 manpower
- **Celebrate them.** +1 stability

### An Ambassador to Mentos (once)
`sky_mainland_ambassador` · years 4295–4350 · Mean time to happen: 36 months
- Needs: allied with Menslosia
- **Send our best.** +40 opinion with Menslosia, -30 Eden
- **Our place is in the sky.** -20 opinion with Menslosia, +1 stability

### The Council of Angels
`sky_angel_council` · years 4295– · 0.5% chance a month
- Needs: from 4295
- **Direct rule.** -10 autonomy everywhere, -5 legitimacy
- **Let the chiefs rule.** +10 autonomy everywhere, +1 stability

### The Waterfall Runs Thin
`sky_waterfall_drought` · years 4295– · Mean time to happen: 150 months
- **Divert the Core's power to the springs.** -100 sanctum, -50 Core
- **It will return.** -1 stability, “Thin Waterfall”: trade efficiency -10% for 2 years

### An Island Sinks (once)
`sky_falling_island` · years 4300– · 0.2% chance a month
- Needs: from 4300
- **Evacuate it.** -60 sanctum, -300 manpower
- **Hold it up with our magic.** -60 Core

### The Academy of Eden (once)
`sky_eden_school` · years 4300– · Mean time to happen: 72 months
- Needs: ADM tech 2
- **Found it.** -120 sanctum, “Academy of Eden”: tech cost mod -5%, idea cost mod -5%
- **Learning is for the Core priests.** +30 Core

### The Festival of Light (once)
`sky_eclipse_festival` · years 4300–4302 · Mean time to happen: 8 months
- **Light every island!** -60 sanctum, +1 stability, -30 opinion with Black Moon
- **A quiet vigil.** +5 legitimacy

### Napoleon's Memoirs (once)
`sky_napoleons_memoirs` · years 4320– · Mean time to happen: 120 months
- **Publish them.** +10 legitimacy, +50 Eden
- **Keep them secret.** +50 Core

### The Barrier Reinforced (once)
`sky_barrier_reinforced` · years 4330– · Mean time to happen: 60 months
- Needs: a fort in Portal Isle
- **Pour the Core's strength into it.** -200 sanctum, “Reinforced Barrier”: doomsday resistance +50%
- **The Barrier has held so far.** 

### Fire on the Horizon (once)
`sky_second_incendium` · years 4400– · Mean time to happen: 36 months
- Needs: flag “star signal”
- **Warn the mainland.** +30 opinion with Menslosia, -30 Eden
- **Prepare Skyfall alone.** +1000 manpower, +5 army tradition

## Chains

- The Photographer → Execution in the Sky (leads to)
- The Photographer → The Photographer's Pictures (unlocks (flag “photographer pardoned”))
- The Canada Ruins → The Vault of the Old World (leads to)
- The Lotus Schism → The Schism Healed (leads to)
- The Lotus Schism → The Schism Healed (leads to)
- A Signal from the Stars → Fire on the Horizon (unlocks (flag “star signal”))
- Out of the Haze → What the Haze Hides (leads to)
- The Staircase Climbers → The Book of Flight (leads to)
- Mask Trials at Equator Isle → We Can Breathe Below (leads to)
