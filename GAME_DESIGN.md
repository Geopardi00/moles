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
- Normal creatures do not physically collide with one another and may overlap. Purpose-built effects such as a future Blocker may influence other creatures through queries or trigger areas.
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

The final terrain representation is deliberately undecided. A fine-grid/TileMapLayer approach and a custom mask/grid with chunked collision rebuilding must be compared in an isolated prototype before adoption.

## 7. Current development milestones

### Milestone 0 — Autonomous Creature Simulation (complete)

Deliver a reusable creature, deterministic walking/falling/landing/wall behavior, non-colliding crowds, configurable spawner, exit counter, kill zone, scrolling test level, independent camera, pause, and 1×/2×/4× speed controls using placeholder visuals and static terrain.

Success criterion: 30 creatures run around the movement test level for an extended period with predictable, stable behavior. An automated 30-creature smoke test supplements the in-editor visual test.

Status: completed on 2026-08-14. The automated pause and 30-creature route test passes, and the in-editor manual test has been accepted.

Excluded: abilities, destructible terrain, liquids, final art, medals, and fall damage.

### Milestone 1 — Level Loop (current)

Add total/saved/required counts, data-driven level configuration, completion, failure, and restart. This begins only after Milestone 0 is reliable.

Status: implemented on 2026-08-14. Automated coverage passes for data-driven requirements, completion, early failure, outcome pause-locking, and a full scene restart. Manual visual sign-off remains.

Confirmed outcome rules:

- A level normally completes only after every creature has resolved as saved or lost and the rescue requirement has been met. Reaching the minimum early does not discard opportunities to save more creatures.
- A level fails early when losses make the rescue requirement mathematically impossible.
- Completed and failed simulations pause and remain locked until restart.

### Milestone 2 — Ability Assignment Foundation

Prove `select DIG → hover/highlight creature → assign → decrement resource → DIGGING → WALKING`. Terrain modification may initially be deliberately crude because the assignment loop is the experiment.

### Milestone 3 — Destructible Terrain Prototype

In a separate experimental scene, compare fine-cell terrain and a custom mask/grid with chunk-based collision rebuilding. Evaluate organic presentation, excavation feel, CPU cost, material identification, and future liquid compatibility.

## 8. Decisions already made

- Godot 4.6, GDScript, and 2D
- `CharacterBody2D` for normal creatures; not `RigidBody2D`
- Initial creature states: `WALKING`, `FALLING`, `EXITING`, and `DEAD`
- Static Godot collision shapes/polygons for Milestone 0 terrain
- No normal creature-to-creature physics collision
- No automatic ledge avoidance
- Placeholder visuals during foundation work
- Camera navigation is independent of creatures

## 9. Open design questions

- Exact Bronze/Silver/Gold threshold rules and whether medals have additional constraints
- Final core ability roster and per-ability targeting modes
- Safe-fall threshold and fall-protection abilities
- Maximum supported creature population and target platforms/performance budgets
- Whether pause permits assignment directly or queues an assignment for the first resumed simulation tick
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
- The world uses normal pausable processing. Simulation control, HUD, and camera use `PROCESS_MODE_ALWAYS` so they remain interactive while `SceneTree.paused` freezes the world.
- Simulation rates use `Engine.time_scale` values of 1, 2, and 4. Pause uses `SceneTree.paused`, not a zero time scale.
- Camera travel is measured using real elapsed time so camera speed does not change with simulation speed.
- Milestone 0 uses scene-local simulation control. A global/autoload service is deferred until multiple level scenes demonstrate that it is necessary.
- Population, spawn settings, and rescue requirements live in a per-level `LevelDefinition` resource.
- Rescue requirements may be authored as an exact count or a percentage; percentage requirements round upward to a whole creature.
- A reusable `LevelController` owns progress and outcome rules. Level scenes connect world events to it, while the HUD only presents its state and requests actions.
- Restart reloads the current level scene and restores an unpaused 1× simulation with fresh counters.
- The gameplay design resolution is 1920×1080, with `Camera2D.zoom` remaining at `Vector2(1, 1)` for the baseline view. World geometry, creature tuning, triggers, and camera bounds are authored directly for that coordinate system rather than using a scaled physics parent.

## 11. Undecided technical experiments

- Fine-grid/TileMapLayer terrain versus custom mask/grid and chunked collision
- Collision contour generation and chunk size for destructible terrain
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
- `scenes/levels/movement_test.tscn` and `scripts/levels/movement_test.gd`: static test geometry and level-local event coordination
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

## 13. Changelog / decision log

- 2026-08-14: Established the initial game concept, locked design pillars, terrain philosophy, and milestone roadmap from the project brief.
- 2026-08-14: Confirmed Milestone 0 collision layers and a pause architecture based on `SceneTree.paused` plus always-processing control nodes.
- 2026-08-14: Added an automated 30-creature smoke target to complement manual visual validation.
- 2026-08-14: Kept simulation control scene-local for the first vertical slice; autoload promotion remains a later evidence-based decision.
- 2026-08-14: Implemented the Milestone 0 movement lab and passed the automated pause plus 30-creature spawn/navigation/rescue test.
- 2026-08-14: Accepted the Milestone 0 manual test and created Git checkpoint `5cf7a1c` on `main`.
- 2026-08-14: Implemented the Milestone 1 data-driven level loop, including count/percentage rescue requirements, completion, early failure, outcome locking, and restart.
- 2026-08-14: Confirmed that normal completion waits for all creatures to resolve so later rescue ranks remain meaningful.
- 2026-08-14: Standardized gameplay framing on 1920×1080 at camera zoom 1.0 and rescaled the movement lab directly into that coordinate system.
