# Project Vision

This is the game's source of truth. Keep it current as decisions get made —
when direction changes, update this file in the same session, not later.

## Game concept

**Robots** — an exploration game about a robot waking up in the remains of a
failed civilization. Nature has reclaimed almost everything. The immediate
goal is small and personal; what it's really about is larger and sadder.

## Original gameplay pillars

From the initial project brief, still the long-term target:

- **Open-world exploration**
- **Robot crafting system** — building multiple types of functional robots
- **Turn-based zombie combat** — reactive defense and QTE timing mechanics
- **Dynamic day & night system** (deferred — see Future plans)

## Current direction: the nesting-doll structure

The world is built as a sequence of enclosed spaces, each one revealing the
next only once you've found your way through the last. Nothing is visible
or reachable ahead of schedule — every boundary is both a visual block and a
physical one.

1. **Area 1 — the house.** Enclosed interior. Player spawns here, facing a
   charging station (placeholder design, functionally and narratively
   important — this is the robot's actual origin point). One door out.
2. **Area 2 — the garden/forest maze (~150-200 sqm).** Immediately
   surrounding the house. Densely packed trees *are* the maze walls — not a
   separate structure — interwoven with a few reclaimed ancient wall
   fragments (ruins, vines draped over them) as curated accents, not a
   corridor system of their own. One single path winds through; everything
   else is sealed, sight and collision both. Ends at a modest raised
   vantage point (a small hill) framed by trees parting at the crest.
3. **Area 3 — the ruined city.** Revealed at the top of the hill, glimpsed
   beyond the tree line. Currently a distant skyline (non-walkable depth);
   intended to become the next full explorable area.

**Open items on area 2:** the current maze path has no branching dead-ends
(single winding route) — a scale trade-off. Genuine "get lost a little"
branches are wanted and can be added now that the area's scale is correct.

## Visual style decisions

- Primary aesthetic: **stylized/painterly low-poly**, not realistic —
  matches Quaternius's Stylized Nature MegaKit and Medieval Village MegaKit,
  which share a compatible hand-painted look.
- The Downtown City MegaKit and the older Ultimate Textured Building Pack
  are more grounded/realistic in style and visibly clash with the above —
  used deliberately anyway for the house exterior and the distant city
  skyline specifically, since those elements benefit from reading as
  "other," not part of the organic world. A future pass may need a shared
  color-grade to unify them further once the city becomes a real area.
- Lighting: procedural sky, mid-morning sun angle, warm light color, soft
  noise-shaped clouds (not a flat texture).
- All assets are CC0 (Quaternius), no attribution required.

## Curated over procedural

Narrative-relevant structure (the maze path, points of interest, building
placement) is hand-placed, not randomly generated — the world should feel
designed, not scattered. Exception: sheer background *density* — filling a
hand-defined area with thousands of trees/bushes so the forest reads as
impenetrable — is generated (seeded/reproducible, not true randomness),
since authoring that volume by hand isn't practical and it carries no
narrative weight itself; the shape of the area it fills, what it excludes
(buildings, the maze path), and the maze's actual walls/path are still
hand-designed. Same logic covers cloud puffs. Deterministic *formulas*
for placement (e.g. a tree ring computed from an angle, or a dense grid
minus a path corridor) are treated as curated, since the shape is a
deliberate design choice even though the math is automated — what's
avoided is true randomness driving where meaningful content ends up.

## Future plans / open ideas

- Replace the player's placeholder cube with a real robot model.
- Door interaction (the shed door doesn't open yet — deferred on purpose).
- Finalize the charging station's design (currently a simple placeholder:
  dark pad, post, glowing core).
- Make the shed interior more interesting/detailed.
- Consider adding branching dead-ends to the area 2 maze.
- Day/night cycle (explicitly deferred from the original brief).
- Narrative idea, not yet committed: give the robot a small, banal surface
  goal (e.g. reach the charging station, find a specific object) that
  turns out to carry a much larger, tragic story underneath as the world
  is explored — fits the "civilization has failed, nature reclaimed it"
  setting well.
- Eventually connect area 3 (city) into a fully walkable, explorable
  district rather than a distant reveal.
