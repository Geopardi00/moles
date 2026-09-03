# Moles — Game Design and Technical Direction

This document is the persistent source of truth for high-level design and architectural decisions. Read it before any major gameplay feature, architecture change, terrain-system decision, or broad refactor. Update it when a meaningful decision changes; keep implementation trivia in code and supporting documentation instead.

## 1. High-level game concept

Moles is a 2D puzzle-platformer inspired by classic Lemmings. A group of visually similar creatures enters a large scrolling level and moves autonomously. The player solves the level indirectly by assigning limited-use actions to creatures and changing the routes available through the environment.

The visual target is hand-drawn, high-definition, and organic rather than visibly tile- or pixel-based. Destructible terrain and environmental simulations are important long-term features, but they follow a proven movement, level, and ability-assignment foundation.

## 2. Core gameplay loop

`Spawn → autonomous movement → encounter problem → player assigns ability → environment/path changes → creatures continue → reach goal`

The player controls the solution, not direct creature movement. The core challenge is predicting autonomous behavior, planning interventions, and managing limited ability resources.

## 3. Locked design pillars

- Creatures walk, fall, land, and react to walls autonomously. The player does not directly steer or jump them.
- Interaction is ability-first: select an ability, then click a creature.
- Ability supplies are limited and configured per level.
- Abilities are normally temporary actions, not permanent character classes. A typical flow is `WALKING → ACTION → WALKING`.
- Basic abilities begin immediately after a valid assignment. Direction comes from creature state where appropriate.
- Rescue requirements and future Bronze/Silver/Gold thresholds are level-specific and data-driven.
- Constant time pressure is not fundamental. Timers may be used by selected levels or optional challenges.
- Early levels generally contain 10–30 creatures; later levels may contain more.
- Levels are scrolling spaces and are not constrained to one screen.
- Pause and 1×/2×/4× simulation controls are core. Player-facing planning and targeting must remain usable while paused.
- Normal creatures do not physically collide with one another and may overlap. Purpose-built effects such as BLOCK influence other creatures through explicit trigger areas.
- Creatures walk off ledges. The prototype has non-fatal falls: fall, land, resume walking.
- A creature that walks into a blocking wall reverses horizontal direction.
- Terrain will eventually be mostly destructible, but final terrain destruction is not part of the foundation milestone.
- Terrain technology must support organic hand-drawn art rather than dictate a visible block/tile aesthetic.

## 4. Current architectural principles

- Prefer small reusable scenes with clear ownership.
- Keep level configuration data-driven and expose useful tuning values in the Inspector.
- Use a simple state model for creatures and typed GDScript where practical.
- Treat an ability as a player command and a state as the creature's current behavior; do not merge the two concepts.
- Use signals for events crossing ownership boundaries, such as spawn, rescue, and death.
- Keep UI, camera, level orchestration, and creature behavior separate.
- Avoid hard-coded level references, duplicated ability behavior, speculative frameworks, and giant coordinating scripts.
- Preserve deterministic, inspectable movement behavior suitable for larger populations.
- Add automated smoke coverage for important simulation invariants alongside manual visual testing.

## 5. Planned gameplay systems

### Foundation systems

- Autonomous walking, falling, landing, and wall reversal
- Configurable creature spawning
- Exit and hazard triggers
- Scrolling camera independent from creatures
- Pause and simulation speed controls
- Level rescue/failure loop
- Ability selection, creature targeting, and limited inventories

### Candidate abilities

- Dig, Mine, Build, Block, Bomb
- Rope or ladder, Drill, Chop, and directional explosives

### Future environment candidates

- Pumps, valves, water redirection, fire, floating objects, falling trees, electrical hazards, moving machinery, sand, and material reactions

Candidate systems are not commitments or current implementation scope.

## 6. Terrain and destruction philosophy

The eventual terrain architecture should separate:

1. visual appearance;
2. terrain/material data;
3. collision;
4. surface decoration.

A smooth hand-drawn dirt hill may use a fine internal grid or mask without exposing that structure visually. Likely materials include dirt, rock, sand, wood, metal, and ice, each with ability/environment interactions.

A hybrid world is expected:

- dirt, rock, and sand use a destructible terrain representation;
- bridges, pipes, machinery, doors, and beams remain scene objects;
- grass, roots, and stones are decoration;
- backgrounds use normal artwork.

Milestone 3 selected a custom 8 px mask/grid with chunk-local collision rebuilding after comparing it against a fine-grid/TileMapLayer baseline. Visual rendering remains independent from the internal terrain representation.

## 7. Current development milestones

### Milestone 0 — Autonomous Creature Simulation (complete)

Deliver a reusable creature, deterministic walking/falling/landing/wall behavior, non-colliding crowds, configurable spawner, exit counter, kill zone, scrolling test level, independent camera, pause, and 1×/2×/4× speed controls using placeholder visuals and static terrain.

Success criterion: 30 creatures run around the movement test level for an extended period with predictable, stable behavior. An automated 30-creature smoke test supplements the in-editor visual test.

Status: completed on 2026-08-14. The automated pause and 30-creature route test passes, and the in-editor manual test has been accepted.

Excluded: abilities, destructible terrain, liquids, final art, medals, and fall damage.

### Milestone 1 — Level Loop (complete)

Add total/saved/required counts, data-driven level configuration, completion, failure, and restart. This begins only after Milestone 0 is reliable.

Status: completed on 2026-08-27. Automated coverage passes for data-driven requirements, completion, early failure, outcome pause-locking, and a full scene restart. Manual visual testing has accepted both the successful-completion and early-failure paths, including their HUD state, pause locking, and restart behavior.

Confirmed outcome rules:

- A level normally completes only after every creature has resolved as saved or lost and the rescue requirement has been met. Reaching the minimum early does not discard opportunities to save more creatures.
- A level fails early when losses make the rescue requirement mathematically impossible.
- Completed and failed simulations pause and remain locked until restart.

### Milestone 2 — Ability Assignment Foundation (complete)

Prove `select DIG → hover/highlight creature → assign → decrement resource → DIGGING → WALKING`. Terrain modification may initially be deliberately crude because the assignment loop is the experiment.

Status: completed on 2026-08-27. DIG inventory is level-configured; ability selection, hover highlighting, click assignment while running or paused, resource consumption, invalid-target rejection, and the temporary `DIGGING → WALKING` action are covered by an automated smoke test and accepted manual visual testing. Terrain collision was intentionally unchanged at this milestone; Milestone 4 now integrates the selected mask/chunk terrain.

### Milestone 3 — Destructible Terrain Prototype (complete)

In a separate experimental scene, compare fine-cell terrain and a custom mask/grid with chunk-based collision rebuilding. Evaluate organic presentation, excavation feel, CPU cost, material identification, and future liquid compatibility.

Status: completed on 2026-08-27. Automated excavation, material lookup, collision removal/preservation, chunk-local rebuilding, and reset coverage passes. Manual comparison accepted Option B, the custom 8 px mask with chunk-local collision rebuilding, as the smoother excavation experience.

Preliminary experiment result:

- The 16 px `TileMapLayer` baseline is simpler and cheaper per dig, but its presentation and collision resolution are visibly tied to coarse cells and every occupied cell contributes a collision unit.
- The custom 8 px mask removes roughly four times as many samples for the same world-space excavation. After switching to boundary contours, one 16-dig headless debug run took 12,336 µs versus 5,126 µs for the TileMap baseline while rebuilding only 30 touched chunks in total.
- The custom mask provides direct per-sample material data, finer excavation edges, fewer merged collision units, and a natural shared data field for future liquid/material simulation.
- Decision: continue with the custom mask/chunk direction. Chunk rebuilds now emit merged exposed-boundary segments rather than solid row rectangles. A bounded 30-creature test remained stable through 24 live digs with all creatures returning to `WALKING`; the slowest rebuild in that debug run was 1,552 µs. The terrain backend is ready for DIG integration into a normal level.

### Milestone 4 — Destructible DIG Integration (complete)

Replace the movement lab's starting platform with the selected mask/chunk terrain and connect accepted DIG assignments to real material removal and collision rebuilding. DIG must only highlight and accept creatures with destructible material beneath them; rejected static-terrain targets must not consume inventory.

Status: completed on 2026-08-27. Automated coverage verifies material-aware targeting, paused assignment, one-use continuous excavation through the final platform layer, empty material lookup, collision breakthrough, resumed autonomous movement, unchanged no-DIG level completion/restart, and the 30-creature live-rebuild stress case. Manual testing accepted the corrected continuous-DIG behavior.

### Milestone 5 — First DIG Puzzle (complete)

Prove the complete puzzle loop in a small data-driven level: creatures remain trapped on an upper route until one limited-use DIG assignment opens persistent destructible terrain, allowing the population to reach the exit below and complete the level. Restart must restore terrain, inventory, creatures, and counters.

Status: completed on 2026-08-27. The `First Dig` level has 10 creatures, an 8-creature requirement, and 3 DIG uses; it is now the first entry in the level catalog. Automated coverage confirms that no creature reaches the exit before intervention, one DIG opens the persistent route, all 10 are rescued, completion locks the simulation, and restart restores terrain, inventory, counters, pause, and 1× speed. Manual visual and gameplay testing has been accepted.

### Milestone 6 — BUILD Ability and Bridge Puzzle (complete)

Add BUILD as a second limited-use ability and prove that the assignment foundation supports more than DIG. A walking creature builds a flat bridge in its current facing direction, one segment at a time, then returns to `WALKING`. Construction changes the shared terrain mask persistently and pauses with the simulation.

Status: completed on 2026-08-27. The `Bridge the Gap` test level provides 2 BUILD uses and requires all 5 creatures to cross a gap. Automated coverage verifies paused assignment and inventory/HUD updates, frozen construction while paused, facing-dependent terrain placement, one-BUILD completion with all creatures rescued, outcome locking, and full terrain/inventory restart restoration. Manual visual and gameplay testing has been accepted.

### Milestone 7 — Combined DIG + BUILD Puzzle (complete)

Prove that the two implemented abilities compose in one authored solution rather than functioning only in isolated demonstrations. The population must first DIG through a sealed upper shelf, then BUILD across a gap on the lower route; neither intervention alone reaches the exit.

Status: completed on 2026-08-27. The `Down and Across` level has 5 creatures, requires all 5 rescues, and provides exactly 1 DIG plus 1 BUILD. Automated coverage verifies independent inventory/HUD updates, persistent removal and addition in separate terrain masks, frozen BUILD progression while paused, the required two-action completion route, outcome locking, and restart restoration of both terrains and inventories. Manual visual and gameplay testing has been accepted.

### Milestone 8 — Playable Level Flow (complete)

Replace the editor-only level-launch workflow with a player-facing entry screen. Present authored puzzles from a data-driven catalog, launch any selected level, and allow return to level selection while running, paused, or viewing a completion/failure result.

Status: completed on 2026-08-27. The project now starts on a `Moles` level-selection screen backed by `LevelCatalog` and `LevelMenuEntry` resources. All gameplay HUDs expose `Levels [Esc]`, result overlays expose `Choose Level [Esc]`, and navigation normalizes pause-lock and simulation speed before changing scenes. Automated coverage verifies ordered catalog rendering, loadable scene references, configured level launch, return from a locked/paused level, rebuilt menu state, and no leaked pause or speed state. Manual visual and navigation testing has been accepted. The catalog currently contains six puzzle levels.

### Milestone 9 — BLOCK Ability and Crowd Redirection (complete)

Add BLOCK as the first ability whose active creature influences other autonomous creatures. A walking mole becomes a temporary stationary blocker; an explicit trigger area reverses approaching walkers without introducing creature-to-creature physics collision. When the blocking duration ends, the blocker returns to `WALKING`.

Status: completed on 2026-08-27. The `Hold the Line` level provides exactly 1 BLOCK for 5 creatures and requires 4 rescues. The leader blocks near a dangerous ledge, redirects all 4 followers toward the exit, then resumes walking and becomes the permitted single loss. Automated coverage verifies paused assignment, independent three-ability inventory/HUD state, frozen blocker timing while paused, exactly four trigger-based redirects, the intended 4-saved/1-lost completion, outcome locking, and full restart restoration. Manual visual and gameplay testing has been accepted.

### Milestone 10 — BOMB Ability and Delayed Terrain Breach (complete)

Add BOMB as a delayed, direction-aware terrain intervention with an intentional creature cost. A valid walking mole becomes stationary in `BOMBING`; its fuse advances only with the simulation. Detonation excavates a persistent circular opening ahead of its facing direction, rebuilds affected terrain collision, and resolves the assigned mole as lost.

Status: completed on 2026-08-27. The `Breaching Charge` level provides exactly 1 BOMB for 5 creatures and requires 4 rescues. The leader detonates beside a destructible wall, opening a complete route for the remaining 4 creatures. Automated coverage verifies material-aware targeting, paused assignment and fuse, independent four-ability inventory/HUD state, no terrain change before detonation, full-depth persistent excavation, the bomber's registered loss, 4-saved/1-lost completion, outcome locking, and full restart restoration. Manual visual and gameplay testing has been accepted.

### Milestone 11 — MINE Ability and Directional Tunneling (complete)

Add MINE as a continuous moving excavation ability distinct from vertical DIG. A valid walking mole enters `MINING`, moves diagonally downward in its current facing direction, and repeatedly excavates a forward/down circular region until no destructible material remains in its path. The resulting tunnel remains part of the shared terrain route.

Status: completed on 2026-08-27. The `Downward Passage` level provides exactly 1 MINE for 6 creatures and requires all 6 rescues. One diagonal tunnel through a thick upper shelf lets the entire population reach the lower exit route. Automated coverage verifies facing-aware targeting, paused assignment and initial excavation, frozen movement and subsequent pulses while paused, independent five-ability inventory/HUD state, continuous forward/down removal without excavation behind the miner, persistent tunnel traversal by all 6 creatures, outcome locking, and full restart restoration. Manual visual and gameplay testing has been accepted.

### Milestone 12 — Results and Progression (complete)

Add explicit per-level Bronze, Silver, and Gold rescue thresholds. Each threshold is authored as a rescued-creature count in the level definition rather than derived from a global percentage or shared formula.

Confirmed medal rules:

- Bronze is the minimum rescue count and therefore the level's success threshold.
- Silver and Gold are progressively higher rescue counts: `0 <= Bronze <= Silver <= Gold <= total creatures`.
- A completed level awards the highest threshold reached from its final saved count. Medal evaluation waits until every creature has resolved, preserving the existing completion rule.
- Finishing below Bronze is a failure and awards no medal.
- Thresholds measure rescued creatures only. Ability usage, completion time, and optional objectives do not affect the Milestone 12 medal.
- Levels with unavoidable losses, such as `Breaching Charge`, may set Gold below the total population.

Implementation scope:

- Extend `LevelDefinition` with explicit Bronze, Silver, and Gold rescue-count fields; Bronze replaces the current count/percentage requirement as the authoritative success threshold.
- Migrate every catalog level to valid authored thresholds without changing its currently accepted pass/fail route.
- Add reusable medal evaluation to the level result flow and present the earned tier on the outcome overlay.
- Cover no-medal, Bronze, Silver, and Gold outcomes, invalid threshold ordering, outcome locking, and restart behavior with an automated Milestone 12 smoke test and manual visual acceptance.

Excluded: persistent best medals, save-data/versioning, locked-level progression, ability-efficiency medals, timers, and final medal artwork. Those can follow after the per-level evaluation and presentation rules are proven.

Status: completed on 2026-09-02. `LevelDefinition` now owns validated explicit rescue-count thresholds and medal evaluation; Bronze drives completion and early failure. All existing level resources have been migrated without changing their accepted success routes, and the HUD presents the three targets plus the final earned tier. The complete Milestone 0–12 automated smoke suite passes. Rendered visual acceptance at the configured 1152×648 window size confirms that the updated goal row and result overlay remain readable, centered, and unclipped.

### Milestone 13 — Persistent Medal Progression (complete)

Persist the best medal earned for each catalog level and use that progress to unlock the campaign sequentially. A fresh profile begins with only Level 1 available; earning Bronze or better unlocks the immediately following catalog entry.

Confirmed progression rules:

- Each `LevelDefinition` owns a stable, non-empty level ID used as the save key.
- Only levels launched through the player-facing catalog may write progress. Direct editor and smoke-test scene launches remain isolated from player saves.
- The saved result is monotonic: Silver replaces Bronze and Gold replaces Bronze or Silver, while failures and lower-ranked replays never downgrade the best medal.
- Level 1 is always unlocked. Every later entry is unlocked only when the immediately preceding catalog level has a saved Bronze, Silver, or Gold medal.
- Progress uses a single versioned local profile. Missing or malformed data falls back to fresh progress; a save from a newer unsupported schema is never overwritten.

Implementation scope:

- Add stable IDs to all six catalog level definitions and let catalog entries reference those definitions rather than duplicate their titles.
- Add an autoloaded progress store backed by `user://progress.cfg`, with schema version 1 and per-level best-medal values.
- Record matching active-level completions, expose progress changes, and present best-medal and lock requirements on the level-selection buttons.
- Cover fresh profiles, sequential unlocks, persistence reloads, medal upgrades/non-downgrades, failed and mismatched runs, invalid data, newer schemas, and direct-scene isolation with automated smoke tests.

Excluded: multiple profiles, cloud synchronization, a user-facing progress reset, a direct Next Level button, optional medal constraints, and final medal artwork.

Status: completed on 2026-09-03. The versioned progress store, active-level write gate, stable catalog identities, linear Bronze unlocks, and best-medal menu presentation are implemented. The complete Milestone 0–13 smoke suite passes. Manual visual acceptance at 1920×1080 and 1152×648 confirms fresh, locked, completed, and newly unlocked menu states are centered, readable, and unclipped.

### Milestone 14 — Production Terrain and Material Pipeline

Convert the proven single-material mask prototype into the production foundation for authored organic terrain. Levels must support multiple materials in one shared field, material-aware abilities, imported terrain layouts, hand-painted texture fills, and chunk-local visual/collision updates without exposing the 8 px simulation grid.

The first production palette is Empty, Dirt, Rock, Bedrock, and Constructed terrain. Dirt accepts DIG, MINE, and BOMB; Rock accepts MINE and sufficiently strong BOMB effects; Bedrock rejects all current removal abilities; Constructed terrain is created by BUILD and may later be removed by DIG, MINE, or BOMB. Exact future water, heat, and electrical properties remain deferred until their simulations use them.

Milestone 14 begins hand-drawn terrain production with one representative burrow biome, a small reusable texture/decal kit, and one scrolling terrain laboratory. It does not redraw the existing campaign or introduce liquids, fire, new creature abilities, or final character animation.

Success criterion: an imported multi-material level remains visually organic before and after repeated excavation, preserves material rules and reset behavior, rebuilds only touched chunks, and remains stable with 30 creatures under a destruction stress pass.

Status: completed on 2026-09-03. The terrain field now stores palette-backed material IDs, imports exact-color authored PNG maps, applies shared DIG/MINE/BOMB/BUILD rules, restores cached source bytes on reset, emits dirty regions, and rebuilds chunk-local collision plus padded shader visuals. The production lab demonstrates organic caves, overhangs, islands, scrolling, live edits, timing, and four debug views using Dirt, Rock, Bedrock, Constructed, exposed-rim art, and eight transparent decals. The complete Milestone 0–14 smoke suite passes; a 30-creature, 50-edit mixed-material stress run remains stable, and manual acceptance at 1920×1080 and 1152×648 confirms readable UI, organic fresh cuts, and seamless chunk boundaries.

### Milestone 15 — Environmental Reactions Sandbox (planned)

Add deterministic, bounded environmental simulation on top of the production terrain field. Implement a chunked liquid layer capable of carrying typed liquids but tune only water initially. Water flows into terrain openings, interacts with sources, drains, reservoirs, pumps, and valves, and freezes correctly with pause and simulation speed controls.

Replace BOMB's direct terrain edit with a reusable explosion event carrying position, radius, strength, and heat. Add material-dependent blast resistance, destructible scene props, bounded fire spread across explicitly flammable targets, explosion ignition, and water extinguishing. Validate the systems in a resettable chain-reaction laboratory rather than a production level.

Success criterion: a repeatable explosion breaches a reservoir, water reacts to the new terrain opening, and the resulting flow changes or extinguishes a fire hazard with deterministic results, complete restart restoration, and stable 1×/2×/4× simulation.

### Milestone 16 — First Production Vertical Slice (planned)

Build the first production-quality 8–12 minute level after Milestones 14 and 15 pass their technical and visual gates. The recommended sequence is: BOMB breaches a resistant wall and releases water; one mole uses the new SWIM ability to reach a pressure plate or valve; redirected water extinguishes a fire blocking the colony; an existing construction or excavation ability opens the final route.

This milestone adds final-quality hand-painted terrain, background, foreground, props, environmental effects, audio, and gameplay-ready character sprites for the states used by the slice. Character animation is isolated behind a visual component and does not change collision or deterministic movement. Required animations are idle/walk, fall/land, swim, the selected existing ability actions, exit, and death; unused legacy actions may retain placeholders until later production milestones.

Success criterion: first-time players can read the materials, understand the environmental chain, and finish the authored puzzle without developer explanation; no placeholder visuals remain on its intended route; the level remains stable with 30 creatures, active environmental simulation, pause, 4× speed, restart, medals, and progression.

CLIMB, rope/ladder traversal, additional liquids/materials, and campaign-wide art replacement follow the vertical slice rather than expanding its scope.

## 8. Decisions already made

- Godot 4.6, GDScript, and 2D
- `CharacterBody2D` for normal creatures; not `RigidBody2D`
- Creature states through Milestone 11: `WALKING`, `FALLING`, `DIGGING`, `MINING`, `BUILDING`, `BLOCKING`, `BOMBING`, `EXITING`, and `DEAD`
- Static Godot collision shapes/polygons for Milestone 0 terrain
- No normal creature-to-creature physics collision
- No automatic ledge avoidance
- Placeholder visuals during foundation work
- Camera navigation is independent of creatures

## 9. Open design questions

- Whether later milestones should add optional medal constraints beyond rescued-creature counts
- Final core ability roster and per-ability targeting modes
- Safe-fall threshold and fall-protection abilities
- Maximum supported creature population and target platforms/performance budgets
- Exact camera feature set beyond keyboard panning
- Material interaction matrix for terrain and environmental systems

## 10. Confirmed technical decisions

- Collision layers for the foundation:
  - Layer 1: terrain/world
  - Layer 2: creature bodies
  - Layer 3: goal triggers
  - Layer 4: hazard triggers
  - Layer 5: selection/interaction areas
- Creature bodies occupy Layer 2 and mask only Layer 1. Therefore creatures collide with terrain but never with one another.
- Goal and hazard `Area2D` nodes mask Layer 2 and do not physically block movement.
- Each creature owns a larger child selection `Area2D` on Layer 5 for future comfortable targeting.
- Ability selection and targeting use an always-processing scene-local controller. Valid assignments begin immediately while paused; the assigned action advances only after simulation resumes.
- Ability supplies live in the per-level `LevelDefinition`; inventory is decremented only after the creature accepts a valid assignment.
- DIG targeting is valid only while a creature is `WALKING` with destructible material directly beneath it. One accepted assignment removes an initial circular mask region, then the creature descends and requests repeated excavation steps until a step removes no further destructible cells. Collision is rebuilt only for affected chunks; pausing freezes both descent and subsequent excavation steps.
- MINE targeting is valid only while a creature is `WALKING` with destructible material forward and below its facing direction. One accepted assignment makes an initial directional cut, then moves diagonally and requests repeated forward/down excavation until a pulse removes no material. Pausing freezes both movement and subsequent excavation pulses; the finished tunnel remains available to every creature.
- BUILD targeting is valid only for a `WALKING` creature when the first bridge segment is in bounds and empty. One accepted assignment places a horizontal sequence of persistent mask-terrain segments in the creature's facing direction, then returns it to `WALKING`. Construction waits while paused and uses top-surface-only collision so bridge ends connect cleanly to authored platforms without artificial vertical walls.
- BLOCK targeting accepts a `WALKING` creature. The blocker becomes stationary for a fixed duration and enables a non-physical `Area2D` that reverses only walkers approaching from either side. Blocking duration and redirection freeze with the simulation; the assigned creature returns to `WALKING` when time expires.
- BOMB targeting accepts a `WALKING` creature only when destructible material is found within several probes ahead of its facing direction. The creature remains stationary through a paused-aware fuse; detonation excavates a circular region centered ahead of that direction, rebuilds touched collision chunks, and registers the bomber as lost after the terrain mutation.
- Destructible terrain will proceed from the custom fine-resolution mask with chunk-local collision rebuilding tested in Milestone 3. Visual rendering remains separate from mask/material data. Collision is generated only for exposed boundaries, merged into collinear segments within each touched chunk.
- Production terrain reserves material ID `0` for Empty and begins with stable IDs `1 Dirt`, `2 Rock`, `3 Bedrock`, and `4 Constructed`. Ability acceptance is owned by these material definitions so targeting and mutation share one rule source.
- Authored terrain uses exact-color, lossless palette PNGs at one source pixel per 8×8 world cell. CPU material/collision chunks remain authoritative; one-cell-padded GPU visual chunks provide seamless hand-painted fills, organic contour warping, and exposed-rim treatment without changing physics.
- The world uses normal pausable processing. Simulation control, HUD, and camera use `PROCESS_MODE_ALWAYS` so they remain interactive while `SceneTree.paused` freezes the world.
- Simulation rates use `Engine.time_scale` values of 1, 2, and 4. Pause uses `SceneTree.paused`, not a zero time scale.
- Camera travel is measured using real elapsed time so camera speed does not change with simulation speed.
- Milestone 0 uses scene-local simulation control. A global/autoload service is deferred until multiple level scenes demonstrate that it is necessary.
- Population, spawn settings, and rescue requirements live in a per-level `LevelDefinition` resource.
- Catalog levels author explicit Bronze, Silver, and Gold rescued-creature counts in `LevelDefinition`. Bronze is the authoritative success requirement; percentage-derived requirements are no longer used.
- A reusable `LevelController` owns progress and outcome rules. Level scenes connect world events to it, while the HUD only presents its state and requests actions.
- A reusable `GameplayLevel` coordinator now binds population, outcomes, abilities, destructible terrain, HUD, and restart behavior for both the movement lab and authored puzzle scenes.
- The project entry point is a level-selection scene backed by a data-driven catalog resource. Gameplay levels own a configurable route back to this selector; returning from any simulation state clears pause locking, unpauses, and restores 1× speed before the scene change.
- Catalog levels use stable IDs for versioned local medal persistence. The selection screen marks a launched level as active, matching completions save only medal improvements, and catalog order derives linear Bronze-based unlocking without coupling the progress store to scene paths.
- Restart reloads the current level scene and restores an unpaused 1× simulation with fresh counters.
- The gameplay design resolution is 1920×1080, with `Camera2D.zoom` remaining at `Vector2(1, 1)` for the baseline view. World geometry, creature tuning, triggers, and camera bounds are authored directly for that coordinate system rather than using a scaled physics parent.

## 11. Undecided technical experiments

- Contour simplification and chunk-size tuning at production level scale
- CPU versus GPU responsibilities for visual terrain updates
- Liquid and granular simulation representation/resolution
- Navigation/prediction overlays for puzzle planning
- Replay or deterministic command recording requirements

## 12. Milestone 0 implementation plan

### Files and responsibilities

- `scenes/creatures/creature.tscn` and `scripts/creatures/creature.gd`: reusable body, placeholder visual, selection area, movement, and initial state machine
- `scenes/gameplay/creature_spawner.tscn` and `scripts/gameplay/creature_spawner.gd`: interval-based population creation and spawn events
- `scenes/gameplay/exit_zone.tscn` and `scripts/gameplay/exit_zone.gd`: rescue trigger only
- `scenes/gameplay/kill_zone.tscn` and `scripts/gameplay/kill_zone.gd`: death trigger only
- `scripts/core/simulation_controller.gd`: pause and 1×/2×/4× state
- `scripts/camera/free_camera_2d.gd`: real-time keyboard camera panning
- `scripts/ui/simulation_hud.gd`: counters, buttons, status display, and help text
- `scenes/levels/movement_test.tscn` and `scripts/levels/gameplay_level.gd`: static test geometry plus reusable level event coordination
- `scripts/tests/milestone_0_smoke_test.gd`: headless population/rescue regression test

### `Creature.tscn` node tree

```text
Creature (CharacterBody2D)
├── VisualRoot (Node2D)
│   ├── Body (Polygon2D)
│   ├── Face (Polygon2D)
│   └── DirectionMarker (Polygon2D)
├── BodyCollision (CollisionShape2D)
├── SelectionArea (Area2D)
│   └── SelectionCollision (CollisionShape2D)
└── StateLabel (Label, debug-only)
```

### `movement_test.tscn` node tree

```text
MovementTest (Node2D)
├── World (Node2D)
│   ├── Background (Polygon2D)
│   ├── Terrain (Node2D)
│   │   └── StaticBody2D platforms/walls with matching visuals
│   ├── Creatures (Node2D)
│   ├── CreatureSpawner (instance)
│   ├── ExitZone (instance)
│   └── KillZone (instance)
├── SimulationController (Node)
├── CameraRig (Node2D)
│   └── Camera2D
└── HUD (CanvasLayer)
```

### Input actions

- `camera_left`, `camera_right`, `camera_up`, `camera_down`: WASD
- `simulation_pause`: P
- `simulation_speed_1`, `simulation_speed_2`, `simulation_speed_4`: number keys 1, 2, and 4

### Implementation and test order

1. Create and parse the reusable creature scene; test a single walker against a wall and ledge.
2. Add the spawner and verify overlapping bodies never collide.
3. Add exit/hazard triggers and rescue counting.
4. Add independent camera movement.
5. Add pause/speed controller and an always-processing HUD; verify the world freezes while camera/UI still work.
6. Run the full test room and automated 30-creature smoke test.

## 13. Milestone 14 implementation plan

### Goal and boundaries

Milestone 14 upgrades `ChunkedMaskTerrain` from a binary occupancy field with one color/material per node into an authored multi-material terrain system. Existing DIG, MINE, BUILD, and BOMB puzzles must keep their accepted behavior while the new terrain laboratory proves the production path.

Included: multi-material data, imported material maps, ability/material rules, hand-painted terrain rendering, visual edge treatment, chunk-local updates, authoring/debug tools, migration compatibility, automated stress coverage, and manual visual acceptance.

Excluded: liquid simulation, fire/heat propagation, new abilities, final character sprites, campaign-wide level conversion, granular sand, decoration physics, and production audio.

### Terrain data and public interfaces

- Add a `TerrainMaterialDefinition` resource with a stable byte-sized ID, display/debug color, DIG/MINE compatibility, blast resistance, and an indestructible flag. Do not add speculative water, heat, or electrical fields until Milestone 15 consumes them.
- Add a `TerrainMaterialPalette` resource that owns unique material definitions and validates reserved ID `0` as Empty. The initial IDs are `1 Dirt`, `2 Rock`, `3 Bedrock`, and `4 Constructed`.
- Replace the terrain node's binary `_solid` array with a `PackedByteArray` of per-cell material IDs. Keep the 8 px default cell size and current chunk-local boundary collision strategy.
- Preserve compatibility helpers such as `get_material_at()`, `excavate_circle()`, and `fill_rectangle()` while routing them through material-aware operations. Add explicit operation queries so targeting and mutation use the same rule: DIG removes Dirt/Constructed; MINE removes Dirt/Rock/Constructed; BOMB compares strength against blast resistance; BUILD writes Constructed only into Empty cells.
- Emit a terrain-region-changed signal containing the dirty cell bounds after a successful edit. Future water simulation will query that region instead of coupling itself to DIG, MINE, BUILD, or BOMB.
- Keep procedural `WAVY_GROUND`, `SOLID_RECTANGLE`, and `EMPTY` initialization for existing levels/tests. Add an authored-map source mode rather than forcing immediate campaign migration.

### Authored map and art contract

- Add a `TerrainMapDefinition` resource referencing a lossless, nearest-filtered palette PNG plus its palette. One source pixel represents one 8×8 world-cell and must map exactly to Empty, Dirt, Rock, Bedrock, or Constructed; unknown colors fail validation instead of silently becoming terrain.
- Convert the source image into cached material bytes when the terrain initializes. Reset restores that original byte buffer exactly.
- Render terrain as chunk visuals driven by material-ID/occupancy textures. CPU code owns terrain data and collision; a CanvasItem shader owns material fill selection, anti-aliased occupancy edges, subtle contour noise, and exposed-edge/rim treatment.
- Give each visual chunk a one-cell sampling border so filtering and edge treatment remain seamless across chunk boundaries. Only dirty chunks update after terrain edits.
- Use seamless hand-painted fill textures rather than small terrain tiles. Surface roots, stones, grass, cracks, and similar details remain separate transparent decals so the internal grid never dictates the illustration style.
- Author art at native game density with larger source masters retained outside runtime exports. The first runtime kit should contain seamless Dirt, Rock, and Bedrock fills (recommended 1024×1024 PNGs), one Constructed fill, one exposed-earth/rim texture, 6–10 transparent detail decals, and a small palette/style reference sheet.
- Do not bake collision outlines, ability rules, lighting, large unique level silhouettes, or background scenery into the reusable fill textures.

### Integration and migration

- Move material acceptance decisions out of `GameplayLevel` probe assumptions and into terrain operation queries while preserving the existing player-facing targeting rules and inventory consumption guarantees.
- Give BOMB an explicit provisional strength sufficient for Dirt and Rock but never Bedrock. Milestone 15 will promote this edit into a reusable explosion event without changing the material result.
- Make BUILD write Constructed material through the shared terrain API. Existing separate build-terrain nodes may remain during migration, but their data and rendering use the same palette and operation rules.
- Convert only the new terrain laboratory to authored-map initialization. Existing six puzzle levels keep procedural sources unless a minimal compatibility migration is required by the refactor.
- Add debug toggles for material IDs/colors, collision contours, chunk boundaries, dirty chunks, and last/total rebuild timing. Debug presentation must never affect exported gameplay behavior.

### Implementation order

1. Add and validate material and palette resources; convert binary occupancy to material bytes while keeping all current tests green.
2. Centralize operation compatibility and migrate DIG, MINE, BUILD, and BOMB queries/mutations without changing puzzle outcomes.
3. Add authored palette-map initialization, exact reset, and invalid-map diagnostics.
4. Add chunk-based material texture rendering and shader-driven fill/edge treatment with temporary textures.
5. Integrate the first hand-painted terrain kit and tune scale, repetition, edge softness, contour noise, and chunk seams.
6. Build the scrolling production terrain laboratory and add authoring/debug controls.
7. Run regression, destruction stress, performance measurement, and manual visual acceptance before declaring the pipeline ready for environmental simulation.

### Automated and manual acceptance

- Verify palette validation, unique/nonzero IDs, exact color-to-material import, invalid-color rejection, material lookup, and exact reset.
- Verify the complete operation matrix, including rejected targets consuming no inventory and Bedrock surviving every current ability.
- Verify only touched chunks rebuild after circular removal and rectangular construction, including edits crossing chunk boundaries.
- Verify imported overhangs, caves, isolated islands, map edges, and empty regions generate stable collision.
- Extend the 30-creature terrain stress test with at least 50 mixed DIG/MINE/BOMB edits across multiple materials and record average/worst rebuild time and dirty-chunk count.
- Run the full Milestone 0–13 smoke suite unchanged, then add a Milestone 14 smoke test covering the new pipeline.
- At both 1920×1080 and 1152×648, inspect intact terrain, fresh cuts, overlapping cuts, material boundaries, chunk seams, camera scrolling, and reset. Normal play must not reveal obvious 8 px squares or visual/collision disagreement.

Milestone 14 is complete only when the temporary shader textures can be replaced by the first hand-painted kit without code or collision changes.

## 14. Changelog / decision log

- 2026-08-14: Established the initial game concept, locked design pillars, terrain philosophy, and milestone roadmap from the project brief.
- 2026-08-14: Confirmed Milestone 0 collision layers and a pause architecture based on `SceneTree.paused` plus always-processing control nodes.
- 2026-08-14: Added an automated 30-creature smoke target to complement manual visual validation.
- 2026-08-14: Kept simulation control scene-local for the first vertical slice; autoload promotion remains a later evidence-based decision.
- 2026-08-14: Implemented the Milestone 0 movement lab and passed the automated pause plus 30-creature spawn/navigation/rescue test.
- 2026-08-14: Accepted the Milestone 0 manual test and created Git checkpoint `5cf7a1c` on `main`.
- 2026-08-14: Implemented the Milestone 1 data-driven level loop, including count/percentage rescue requirements, completion, early failure, outcome locking, and restart.
- 2026-08-14: Confirmed that normal completion waits for all creatures to resolve so later rescue ranks remain meaningful.
- 2026-08-14: Standardized gameplay framing on 1920×1080 at camera zoom 1.0 and rescaled the movement lab directly into that coordinate system.
- 2026-08-27: Accepted Milestone 1 after manual success- and failure-route testing confirmed counters, outcomes, pause locking, camera/HUD behavior while paused, and restart behavior.
- 2026-08-27: Implemented the Milestone 2 DIG assignment slice with level-configured inventory, hover targeting, direct paused assignment, placeholder action feedback, and automated `DIGGING → WALKING` coverage.
- 2026-08-27: Accepted Milestone 2 manual testing and began the isolated Milestone 3 terrain comparison.
- 2026-08-27: Implemented the side-by-side Milestone 3 terrain lab. Automated tests favor the custom 8 px mask/chunk direction provisionally; manual feel review and contour/load validation remain.
- 2026-08-27: Accepted Milestone 3 manual testing and selected Option B, the custom mask with chunk-local collision rebuilding, as the terrain direction.
- 2026-08-27: Replaced prototype row-run collision with chunk-local exposed-boundary contours. A 30-creature, 24-dig stress test passed without fall-throughs or unstable movement in a bounded test room.
- 2026-08-27: Implemented Milestone 4's first real destructible gameplay slice by replacing the movement lab start platform with mask terrain and connecting valid DIG assignments to material and collision removal.
- 2026-08-27: Manual Milestone 4 testing exposed that DIG stopped after one pulse and could leave the final platform layer intact. DIG now continues descending and excavating until it breaks through or reaches non-diggable space, using only one inventory item.
- 2026-08-27: Accepted the corrected continuous-DIG behavior and completed Milestone 4. Began Milestone 5's first ability-required puzzle slice.
- 2026-08-27: Implemented the `First Dig` puzzle. One DIG opens the lower exit route for all 10 creatures, and automated coverage verifies completion plus full terrain/inventory restart restoration.
- 2026-08-27: Accepted the `First Dig` manual gameplay test and completed Milestone 5.
- 2026-08-27: Implemented and accepted Milestone 6's BUILD slice and `Bridge the Gap` level. One facing-dependent BUILD creates a persistent walkable bridge for all 5 creatures; automated and manual pause, inventory, completion, and restart verification passes.
- 2026-08-27: Implemented and accepted Milestone 7's `Down and Across` puzzle, requiring exactly one DIG followed by one BUILD. Automated and manual verification proves both terrain mutations compose, all 5 creatures are rescued, and restart restores both systems.
- 2026-08-27: Implemented and accepted Milestone 8's data-driven level-selection entry screen and in-level return navigation. Automated and manual verification confirms catalog rendering, scene launch, and clean return from running, paused, and outcome states.
- 2026-08-27: Implemented and accepted Milestone 9's BLOCK ability and `Hold the Line` puzzle. A temporary blocker redirects four followers through an explicit trigger area without physical creature collision; automated and manual assignment, pause, 4/5 outcome, and restart verification passes.
- 2026-08-27: Implemented and accepted Milestone 10's BOMB ability and `Breaching Charge` puzzle. A paused-aware directional charge sacrifices its assigned mole and opens a full-depth persistent wall breach for four followers; automated and manual 4/5 outcome and restart verification passes.
- 2026-08-27: Implemented and accepted Milestone 11's MINE ability and `Downward Passage` puzzle. One facing-dependent continuous diagonal excavation creates a persistent tunnel used by all 6 creatures; automated and manual targeting, pause, completion, and restart verification passes.
- 2026-09-01: Defined Milestone 12 around explicit per-level Bronze, Silver, and Gold rescue-count thresholds. Bronze becomes the success requirement; persistence, unlocking, and non-rescue medal constraints remain deferred.
- 2026-09-02: Implemented and accepted Milestone 12 medal configuration, validation, outcome evaluation, HUD presentation, and resource migration. The complete Milestone 0–12 smoke suite passes, and rendered visual testing confirms the HUD and result overlay remain readable and unclipped.
- 2026-09-03: Implemented and accepted Milestone 13 persistent medal progression. Stable level IDs, a versioned local progress store, active-level write isolation, monotonic best medals, linear Bronze unlocks, and progression-aware catalog presentation pass the complete Milestone 0–13 smoke suite and manual visual acceptance at both target window sizes.
- 2026-09-03: Defined Milestones 14–16 as the production-terrain pipeline, environmental-reactions sandbox, and first production vertical slice. Hand-drawn terrain begins with a constrained Milestone 14 kit; gameplay character sprites and required state animations enter with the Milestone 16 vertical slice.
- 2026-09-03: Implemented and accepted Milestone 14. Exact-color authored material maps, shared operation rules, cached reset data, padded chunk shaders, a scrolling production terrain lab, five seamless terrain textures, eight transparent decals, and expanded automated stress coverage establish the production terrain foundation for Milestone 15 environmental reactions.
