# WRITE-OFF

A side-on 2D descent game for CC:Tweaked. You are a contract scavenger sent three
thousand metres down to recover a lost consignment. Returning home is not possible empty-handed - and failing to retrieve said consignment risks your family's lives.
Eleven stratums await you, and the shafts only
go down.

Head, two arms, two legs, a torso and pelvis, each one coloured by its own condition.

### INSTALL

The folder structure has to be preserved. The loader reads `ROOT/lib/<name>.lua`.

```
writeoff.lua
lib/util.lua      general helpers and the seeded RNG
lib/ui.lua        drawing, menus, touch buttons, layout modes
lib/data.lua      all content and all tuning numbers
lib/tiles.lua     what each tile does, including how it hurts you to land on
lib/body.lua      the medical simulation
lib/fall.lua      the fall injury model
lib/inv.lua       carrying, wearing, wielding, crafting
lib/mapgen.lua    2D map generation
lib/phys.lua      walking, climbing, gravity, creature movement
lib/render.lua    the map viewport
lib/combat.lua    encounters
lib/run.lua       the run: position, clock, stratum transitions
lib/screens.lua   every screen
lib/save.lua      saving, loading, past runs
```

Run with `writeoff`.

If a monitor is attached, the game asks once on the terminal, which screen you want.
`writeoff term` and `writeoff monitor` skip the question. The terminal is never taken
over without being asked, and touch buttons only appear on a monitor, because that is
the only place there is no keyboard. Obviously.

## The readout

Everything below the map is one row. It shows blood and pain always, and adds a
number only when that number has gone wrong: bleeding rate, oxygen under 92, a heart
rate outside 50 to 140, a core temperature outside 35.5 to 38.2, consciousness under 60.

The right hand side carries whichever of these matters most:

1. a drop beside you and what is at the bottom
2. something under your feet worth pressing F on
3. whatever is wrong with you that is not already a number

The drop warning outranks the numbers, because it is the thing about to happen. Ambient
status words yield to them, because they are not.

There is no permanent list of controls on the play screen. They are in the briefing and
in the `?` menu.

## Screens

Minimum 51x19, which is exactly a stock advanced computer.

If an advanced monitor is attached, the game finds it, picks the largest text size
that still fits the layout, and draws there instead. At 68x24 or larger it switches
to the full layout: bigger map, a side panel with the body diagram and vitals, and a
row of touch buttons along the bottom so it can be played by hand at the monitor.

A 7x4 advanced monitor lands in the full layout comfortably.

## Controls

Arrow keys or WASD walk and climb. `SPACE` jumps. `F` or `ENTER` uses whatever you
are standing on.

`X` mines. `M` medical, `V` condition, `I` pack, `K` map, `R` rest, `C` craft,
`J` paper, `Z` wait, `?` menu.

Stand on a trader, a thermostat, a shower or a container and press `F` to use it.

On a monitor, use the buttons.

The body is one tile wide and two tall. Arms and legs stick out into the tiles beside
you and are simply not drawn when there is rock there, so pressing up against a wall
looks like pressing up against a wall.

**Jumping** is an arc, drawn cell by cell, so you rise, travel and come down over about
a second. Tap jump on its own and you go straight up and land where you started. Hold a
direction and you travel that way, and you can change your mind halfway. At full
mobility that is two tiles up and three across; a damaged leg shortens both.

The same steering works during any fall. Push into open air and you drift. Push into
rock and you grab it.

Landing back at the height you left from costs nothing, because the rise is subtracted
from the fall. Landing lower costs the difference. Jump off a ledge on purpose and it is
just a fall with a running start.

Timing lives in `P.AIR_FRAME`, `P.APEX_HANG` and `P.FALL_FRAME` at the top of `phys.lua`.
Jump distance is the `dist` and `rise` lines in `P.jump`.

**Sliding.** While you are falling, push into a wall and hold it. If your arms still
grip, you catch the rock and slide instead of dropping. Sliding wipes out the speed you
had built up, so it turns a fatal shaft into a survivable one. It costs skin off the
arm you are leaning on, roughly one point per two metres, and it needs a grip above
25 percent. Gloves cut the damage substantially.

Measured, on a 124 m shaft: falling it leaves both legs at zero muscle. Sliding it
leaves the legs untouched and the arms at 45 percent skin. Your hands for your legs.

## Falling

The line under the map tells you how far the drop beside you is and what is at the
bottom, before you step off. A drop gauge in your pack turns the estimate into an
exact figure.

Damage is distance times surface. On bare stone with no gear:

| drop | what happens |
| --- | --- |
| under 3 m | nothing |
| 10 m | bruising |
| 30 m | torn muscle, often a joint out |
| 50 m | a dislocation or a fracture, bleeding on rough ground |
| 100 m | both legs, usually an arm as well |
| 300 m | multiple fractures and internal bleeding |
| 400 m + | usually fatal |

Surfaces change it a lot. A moss bed takes about three quarters out of a fall and
deep water takes more. Broken rock takes nothing out and turns the impact into
punctures, so the same drop leaves you bleeding four times as fast.

Walking into a rock does nothing. Only descent counts.

Every level has a rope route from top to bottom that costs you nothing but time.
Drops are always optional and always faster.

A `v` in the tile beside your feet marks a drop. A wall beside the drop is noted in the
readout, because that is a shaft you can slide rather than fall.

## Traps

**Impaler.** A spike. You cannot see it at all until you are within two tiles, and then
only as a red light that blinks, so it is easy to miss and easy to regret. Walking onto
it is a cut. Landing on it from a height is a puncture roughly twenty times worse, and
above about eight metres it starts taking eyes and jaws. Over 120 long falls onto spikes:
31 lost an eye, 30 lost a jaw. A lost eye permanently cuts your perception. A dislocated
jaw means nothing solid goes in it until it is set.

**Launch plate.** Throws you three to five tiles up and two to four sideways, never
straight up. If the ceiling is low you hit it, which costs head muscle and sometimes
brain. The real damage is wherever you come down.

**Leg trap.** Closes on a leg and holds you for eight seconds. It bleeds you the whole
time it is on. Three ways out:

| | speed | cost |
| --- | --- | --- |
| wait | eight seconds | steady bleeding |
| pull (move) | two pulls | roughly doubles the bleeding |
| pry (`F`) | one or two tries | almost nothing extra |

Prying needs a grip above 25 percent. If your arms are wrecked you can only pull.

Traps get more common the deeper you go, and they never spawn inside a pod.

## Mining

`X` breaks the rock in front of you. `UP` with nothing to climb digs the ceiling. `DOWN`
with nothing to climb digs the floor. One tile at a time, a few swings each.

Stone takes about a hundred points of work. A rock hammer does forty six a swing, a pry
bar twenty six, a pipe fourteen, bare hands nine. Every swing costs energy, and energy
only comes back by resting, so a long tunnel means stopping halfway. Swinging with
nothing in your hands skins them.

The readout under the map tells you what you are about to hit and how many swings it
will take with what you are holding.

Fall into a sealed hole and you are not stuck. Dig upward, then jump out. Bare handed
that is about twelve swings and most of an energy bar. With a hammer it is two.

Mining is loud. Anything within about sixteen tiles wakes up.

## Pods

Rare sealed shells bolted onto a gallery floor, about one level in three. Doors both
sides at body height, so a pod never blocks the way through. Two kinds.

Pods are lit wall to wall, so you can put the torch out and save the cell while you are
inside. Every one has a charge post for your lights.

Three tiles of headroom inside, so a person stands up in one. Doorways at body height
with hull above them.

**Supply pods** hold three or four containers nobody came back for.

**Trader pods** have somebody living in them, drawn as a figure the same as you are,
in their own colour. You can tell who is in a pod from the doorway.

Both have a thermostat and a decontamination shower.

The **thermostat** sets the air inside the pod anywhere from 2 to 35 degrees, and it is
the fastest way to get your core temperature back after The Rime, or down after The
Boiling Floor.

The **shower** takes four minutes, has two tanks, and is the only way to clear
contamination out of every limb at once without spending antibiotics. Minor
contamination is washed away completely. A wound that has already gone bad gets knocked
back but not finished. Everything is sealed against new infection for forty minutes.
It leaves you soaked, so turn the pod up before you go back out.

## Traders

Everything in the game has a value, and what you pay or get paid depends on how the
trader feels about you. Attitude runs 0 to 100.

At attitude 10 a field dressing costs 8 scrip and sells for 1. At attitude 95 it costs
6 and sells for 3.

**Scrip** is the currency. It turns up on bodies and in caches, and traders take
nothing else.

Four ways to move an attitude:

**Buying and selling** nudges it up a point at a time, just for dealing.

**Hugging** is cheap and depends on who you are hugging and what state you are in.
Warm traders take it, cold ones do not, and showing up covered in blood is worse than
showing up merely injured. Measured over 120 attempts: Hob accepts 84, Vasco accepts 36,
and Hob drops to 53 if you are actively bleeding on him. The second hug is much harder
than the first.

**Haggling** is a real check against how shrewd they are, using your steadiness, your
brain and your wits. It can go backwards, and after four attempts they stop listening.
Head injuries make you noticeably worse at it.

**Threatening** is the big swing. A success pins their attitude at 88 and they hand you
whatever price you want. A failure means they reach under the counter. Over 120 threats,
Hob folded 87 times; Vasco folded 8 and shot at you 112. An armed trader is a tier four
opponent with 70 hit points and a scatter pistol.

## Order of work

Bleeding, then breathing, then bone, then infection.

Press `DOWN` while standing in water to kneel and drink from it directly. No flask
needed. Pool water may make you sick; a spring within two tiles of you is clean, even
if you are stood in a dirty pool. `F` on water offers the same thing plus filling a
flask.

You leave blood on the floor while you are bleeding, and it stays. It is a useful way
of finding your way back through a level, and a fairly clear signal that you should have
stopped to dress something.

Blood is five litres. Saturation holds up until about 4.5 and collapses through 2.78.
A dressing stops a fraction of the flow and soaks through. A tourniquet stops all of
it and starts killing the limb after six minutes. Pain makes your hands shake, and
shaking hands fail at pulling shrapnel and setting joints.

## Tuning

Numbers live in `lib/data.lua`.

- `D.TUNE` at the top: clotting, infection rate, pain decay, bone healing time,
  hunger and thirst, blood thresholds, cardiac arrest grace period.
- `D.STRATA`: per-level temperature, loot tier, floor material bias, creatures,
  hazards.
- `D.ITEMS`, `D.RECIPES`, `D.CREATURES`, `D.CONTAINERS`, `D.LOOT`, `D.DOCS`.

The fall curve is `lib/fall.lua`, and it is short. The thresholds are the four
`chance()` calls in `F.land`. Surface behaviour is the `hard`, `sharp` and `cushion`
values in `lib/tiles.lua`.

Map shape is `M.generate` in `lib/mapgen.lua`: gallery spacing, how many open drops
get cut, and how often a long shaft appears. Every gallery keeps a protected walking
corridor between where you arrive and the rope you leave by, which is what guarantees
the safe route exists.

## Adding things

New tile: add it to `T.DEFS` in `tiles.lua` with its physical flags and its landing
values, then add a colour entry to `LIT` in `render.lua`. That is all it needs.

The player figure is the `FIGURE` table in `render.lua`: six entries, each an offset
from the feet, a limb name and a glyph. Change the glyphs there and the character
changes shape. Collision height is `P.BODY_H` in `phys.lua`.

Slide cost is the small `CU.body.hurt` call inside `P.settle`.

New level: append to `D.STRATA`. Anything past eleven loops the middle of the list.

New trader: append to `D.TRADERS` in `data.lua`. Each one needs `warm`, `shrewd` and
`nerve` between 0 and 1, a greeting, and a list of signature stock. Three to five random
items get added on top at the level's loot tier.

Pod frequency and size are `placePods` and `M.buildPod` in `mapgen.lua`. Price curves
are the one `rates` function at the top of the trading section in `screens.lua`.
