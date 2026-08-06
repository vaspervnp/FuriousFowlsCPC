# FOWL AND FURIOUS

### Amstrad CPC 464 / 6128 — 64K, disc

*A slingshot, a hill of timber, and a great many smug pigs.*

---

## Loading

Insert the disc and type:

    RUN"FOWLS

The REVIVE8BIT splash appears. Press **SPACE** to go on, or wait ten
seconds and it goes on by itself. The game then loads in two pieces and
starts.

The game writes to the disc — see **The high score** below — so do not
leave the write-protect tab open unless you want to keep your score to
yourself.

---

## Why the birds are furious

They had a tree. A very good tree — a broad oak on the ridge, six nests in
it, and a dawn chorus that had taken four seasons to get right.

The pigs had a field. Pigs cannot climb and pigs cannot fly, and what a
pig in a field mostly has is a view of the field. This was felt, at some
length, over the fence.

The birds are heavy sleepers. They have to be: you cannot rehearse a dawn
chorus at dawn without going to bed in the afternoon, and by nine in the
evening the whole ridge is out cold. So nobody woke up. Not when the
sawing started, not when the oak came down in the small hours, and not
when three hundred metres of the finest nesting timber on the ridge went
over the fence one plank at a time.

They woke up on the ground.

The pigs had been busy. Fifty structures, from a shed to a proper walled
citadel, every last one of them built out of somebody else's tree — and a
pig sitting in each one with the smug, settled look of an animal that has
finally got a view. One of them waved.

The birds held a meeting. The findings were: (a) that this was not on, and
(b) that a bird carrying a full winter's grudge cannot actually get much
above the fence under its own power, which was awkward, and was not
mentioned again. What they had was the last fork of the oak, still
standing where the trunk used to be, and the elastic out of the choir
conductor's braces.

You are not knocking those forts down. You are taking the tree back, one
plank at a time, and it is going to land on somebody.

---

*(The pigs tell it differently. They say the tree was dead, the birds were
loud, and nobody in the history of the field has ever asked a pig what it
would like. If you press UP at the menu you can hear their side of it, at
which point the slingshot is theirs and the birds are the ones sitting in
the buildings looking pleased.)*

---

## The idea

Nine pigs have built forts out of timber and are sitting inside them
looking pleased. You have a slingshot and a queue of birds. Knock the
forts down on top of the pigs.

You do not have to hit a pig. You have to make the fort hit the pig. A
shot that brings a roof down on three of them beats a shot that hits one
of them squarely, and the score is worked out on exactly that basis.

There are fifty forts. They start as a hut with one pig in it and end as a
stone-footed citadel with a rope walk across the top, a charge of dynamite
in the ground floor and a king on the roof.

---

## The menu

| Key | What it does |
|---|---|
| **SPACE** | Start playing |
| **UP** | Swap sides — throw pigs at birds instead |
| **DOWN** | Difficulty: EASY, MEDIUM, HARD |

**HI SCORE** at the top of the menu is read off the disc when the machine
is switched on, and written back when you return here.

**Swapping sides** changes nothing about the forts or the physics. The
thing in the pouch becomes a pig and the things in the fort become birds,
and the status strip changes its labels to match. It is the same game
seen from the other end of the argument.

---

## Playing

| Key | What it does |
|---|---|
| **SPACE** (hold) | Draw the sling back. Let go to launch. |
| **UP** / **DOWN** | Raise and lower the angle |
| **LEFT** / **RIGHT** | Look along the world without shooting |
| **ESC** twice | Back to the menu |
| **R** | Rebuild this fort |
| **N** | Skip to the next fort |

**R** and **N** are there for people building levels. They are honest
about it: **N** does not score anything and **R** does not cost you a go.

### Aiming

The dotted line out of the pouch is the direction the bird will leave in —
five dots, about twenty pixels of it. It is a direction, not a prediction:
gravity takes over the moment the bird is in the air.

The **pull** is the power. Hold SPACE and the bird is hauled further back
along the reverse of the launch direction; that is the whole gauge, and it
takes about two fifths of a second to wind up to full.

The camera follows the bird, and when the bird hits something it centres
on the impact so that you can see what you did.

---

## The status strip

    LV01  BD3  PG2  SC000450

| | |
|---|---|
| **LV** | which fort, 01 to 50 |
| **BD** | birds still in the queue (**PG** if you swapped sides) |
| **PG** | pigs still alive (**BD** if you swapped sides) |
| **SC** | score |

At the end of a fort the strip is replaced by a banner: **FORT DOWN!** or
**OUT OF BIRDS**, with the go you are on, and **SPACE** to carry on.

---

## Scoring

**The score is how hard the pigs were hit.** Every blow that lands on a
pig adds its own force to the score — a plank falling on one, a bird
catching one on the way past, a charge going off next to one. A shot that
catches three pigs beats a shot that flattens one.

**Plus 100 for every bird you did not need.** Clear a fort with two birds
still in the queue and that is 200 on top.

Nothing at all is scored for damage to the fort. The fort is the means,
not the end — paying for it would reward knocking a wall down and walking
away from the pig behind it.

The score carries across forts and resets when you go back to the menu.

---

## Difficulty, and running out

A fort allows you a fixed number of **goes**. Use all your birds without
clearing it and that is one go gone; you get the fort back, rebuilt.

| | Goes per fort |
|---|---|
| **EASY** | 5 |
| **MEDIUM** | 3 |
| **HARD** | 2 |

Run out of goes and it is **GAME OVER**. SPACE takes you back to the menu,
where your score is compared with the high score and written to the disc
if it beat it.

Clearing a fort gives you a fresh set of goes on the next one.

---

## The high score

It lives on the disc, in a sector reserved by a file called `SCORES.BIN`.
The game does not use AMSDOS to get at it — the firmware is paged out
while the game runs — it drives the disc controller itself, and it only
believes a save after reading the sector back and comparing it.

It is written **at the menu and nowhere else**. Spinning the drive up
stops the machine for about a second, which nobody notices at a menu and
everybody notices mid-shot. So: if you want your score kept, go back to
the menu (ESC twice, or lose) before you switch off.

Your difficulty setting is kept in the same sector.

---

## What a fort is made of

Sixteen pieces, all timber except where the table says otherwise. The
number is how much punishment the piece takes before it is dislodged.

| Piece | Takes | Notes |
|---|---|---|
| Plank, flat | 30 | floors and lintels |
| Plank, upright | 30 | the standard post — and it TOPPLES |
| Offcut | 45 | small, solid, load-bearing |
| Brick | 40 | the one piece that fills its cell |
| Rafter | 25 | roofs, in two directions |
| Arch | 35 | open underneath — a pig fits |
| Pillar | 28 | the slenderest upright, and it topples |
| Shelf | 20 | one plank deep, snaps easily |
| Crate | 18 | hollow: the weak point of any fort |
| Rope, strung | 8 | **cut it and everything on it comes down** |
| Rope, hanging | 8 | **things hang from it** |
| Pulley | 22 | |
| **Dynamite** | 10 | goes off — see below |
| **Glass** | 6 | the most fragile thing in the game |
| **Stone** | 90 | the least |

Pigs take 34. A helmet doubles that and a crown trebles it.

---

## How things fall

The five rules that decide every collapse. They are worth knowing,
because a fort is a puzzle about them.

**1. A beam is judged at its ends.** A plank spanning a gap is held if
both ends are supported, TIPS over the end it still has if one goes, and
falls flat if neither does. This is why knocking out one post of a doorway
brings the lintel down at an angle instead of dropping it straight — and
why the thing under that angle gets hit.

**2. Uprights topple, everything else slides.** Shove a post and it goes
over. Shove an offcut and it just moves along. The upright is what you
want to hit.

**3. A single piece is also held by being wedged.** A block with nothing
under it will still stand if there is something solid on both sides. Take
one of those away and it drops.

**4. Rope carries tension and nothing else.** A strung rope needs both
ends tied; cut it anywhere and the whole thing comes down at once, because
a rope has nothing to pivot on. Anything directly under a rope is HANGING
from it and is held by nothing else — so cutting the rope drops the load
in the same instant. Look for the stone hanging over a pig.

**5. Dynamite removes what is near it.** A charge that takes a hit throws
everything within two cells away from itself and kills any pig in that
square outright. A second charge inside the blast goes off too. A spent
charge is just a crate afterwards; it will not go off twice.

---

## The birds

Six of them: red, yellow, blue, black, white and green. They differ in
plumage and in nothing else — there are no special abilities in this
game. A fort gives you between three and six of them, and which ones is
decided by how far into the fifty you are.

---

## The forts

Fifty of them. The number of structures, how tall the tallest is, and
whether there is dynamite, glass, stone or rope in it all grow with the
fort number. The eight shapes — hut, bridge, pyramid, tower, gatehouse,
keep, manor, citadel — rotate for variety, but the citadel only turns up
once you are most of the way through.

**The sky and the ground change every few forts** — day, dawn, dusk,
night, snow and desert — so fifty forts do not look like one long
afternoon. It is the same world underneath: the theme moves the colour
behind the sky and restacks the bands of soil, and nothing else.

The forts stand in three places: an outbuilding on the left, the main fort
in the middle, and an annexe on the right. Late forts have all three, and
they are meant to lean on each other. Bringing the outbuilding down onto
the main fort is usually cheaper than hitting the main fort twice.

Every level is a plain text file on the development disc, and the level
compiler will read back anything you draw. That is a story for another
document.

---

## Credits

**REVIVE8BIT — 2026 — VASPER**

Written for the Amstrad CPC in Z80 assembly. Mode 0, 160×200, sixteen
colours, hardware ring scrolling, and not one byte to spare.
