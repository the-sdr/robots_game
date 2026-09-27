# Project Vision

This is the game's source of truth. It is owned and edited by the project owners. Claude may propose changes but must get explicit approval before altering this file.

## Game concept

**Robots** — an exploration game about a robot waking up in the remains of a failed civilization. Nature has reclaimed almost everything. The immediate goal is small and personal; what it's really about is larger and sadder.

## Original gameplay pillars

From the initial project brief, still the long-term target:

- **Open-world exploration**
- **Robot crafting system** — building multiple types of functional robots
- **Turn-based zombie combat** — reactive defense and QTE timing mechanics
- **Dynamic day & night system** (deferred — see Future plans)
- **Pets** NPC companions to tame, keep and unlock more game mechanics
- **Robot characters** NPC robots to drive the story and mission

## Current direction: the nesting-doll structure, dungeons within the open world

The world is built as a sequence of enclosed spaces. The starting area/dungeon reveals the main city. Nothing is visible or reachable ahead of schedule, every boundary is both a visual block and a physical one.

1. **Area 1 — the house.** Enclosed interior. Player spawns here, facing a charging station (placeholder design, functionally and narratively important — this is the robot's actual origin point). One door out. Learn controls, feel contained, get bearings. 
2. **Area 2 — the garden/forest maze (~3,000 m², about 48 × 62 m).** Immediately surrounding the house. Densely packed trees and strategically placed walls *are* the maze walls — not a separate structure — interwoven with a few reclaimed ancient wall fragments (ruins, vines draped over them) as curated accents, not a corridor system of their own. One single path winds through; everything else is sealed, sight and collision both. Ends at a modest raised vantage point (a small hill) framed by trees parting at the crest. Disorienting, exploration, slow reveal. Player feels lost but curious.
3. **Area 3 — the ruined city.** Revealed at the top of the hill, glimpsed beyond the tree line. Player feels reward from discovery. Currently a distant skyline (non-walkable depth); intended to become the next full explorable area.
4. **Area 4+ — the town.** Content inside the buildings, more areas as part of the town to explore. Future state of multiple mini dungeons with story, characters and items for crafting.

## The player robot

The player is a small tracked robot, currently a placeholder. Twin treads, a thin column torso, a wide chest, two jointed arms with claw hands, and a binocular head on a thin neck. It's built from simple primitive shapes rather than an imported model.

It's deliberately **modular** — treads, torso, arms and head are separate parts in the scene tree. That mirrors where the robot crafting pillar is headed: robots assembled from interchangeable parts. The final art can replace each part individually without changing the structure.

## Visual style decisions

- Starting point (pragmatic): **stylized low-poly**, not realistic — Quaternius's Stylized Nature MegaKit and Medieval Village MegaKit, which share a compatible hand-painted look. These are placeholders on the way to the target below.
- The Downtown City MegaKit and the older Ultimate Textured Building Pack are more grounded/realistic in style and visibly clash with the above — used deliberately anyway for the house exterior and the distant city skyline specifically, since those elements benefit from reading as "other," not part of the organic world. A future pass may need a shared color-grade to unify them further once the city becomes a real area.
- Target: **painterly, beautiful, atmospheric** — not low-poly in look.
- Lighting: procedural sky, mid-morning sun angle, warm light color, soft noise-shaped clouds (not a flat texture).
- All assets are CC0 (Quaternius), no attribution required.

## Curated over procedural

Narrative-relevant structure (the maze path, points of interest, building placement) is hand-placed, not randomly generated — the world should feel designed, not scattered. Exception: sheer background *density* — filling a hand-defined area with thousands of trees/bushes so the forest reads as impenetrable — is generated (seeded/reproducible, not true randomness), since authoring that volume by hand isn't practical and it carries no narrative weight itself; the shape of the area it fills, what it excludes (buildings, the maze path), and the maze's actual walls/path are still hand-designed. Same logic covers cloud puffs. Deterministic *formulas* for placement (e.g. a tree ring computed from an angle, or a dense grid minus a path corridor) are treated as curated, since the shape is a deliberate design choice even though the math is automated — what's avoided is true randomness driving where meaningful content ends up.

## Future plans / open ideas

- Replace the player's placeholder primitive robot with final art, keeping the part-by-part structure so it can feed into the crafting system.
- Door interaction (the house door doesn't open yet — deferred on purpose).
- Finalize the charging station's design (currently a simple placeholder dark pad, post, glowing core).
- Build a charging mechanic so that the player robot can charge up energy. Chargers are solar powered so won’t be unlimited, needs resource allocation.
- Make the house interior more interesting/detailed.
- Make a mechanic for escaping the house. Potentially have destructible environments, a smashing tool for the robot to help navigate the forest.
- Give the area 2 dead ends real content (they currently hold placeholder collectible parts).
- Day/night cycle (explicitly deferred from the original brief). Charging stations refill from solar power during the day, max out after midday, player can draw power from them to charge up.
- Narrative idea, not yet committed: give the robot a small, banal surface goal (e.g. reach the charging station, find a specific object) that turns out to carry a much larger, tragic story underneath as the world is explored — fits the "civilization has failed, nature reclaimed it" setting well.
- Eventually connect area 3 (city) into a fully walkable, explorable district rather than a distant reveal. More dungeons. More characters. More puzzles, More tools, more crafting, a grand narrative to drive it all. 
