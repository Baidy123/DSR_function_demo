# SceneDirector Inspector Event Authoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a typed, inspector-authored SceneDirector event queue with categorized actions, then migrate the tavern opening orchestration without changing existing wave, NPC, quest, equipment, or scene-transition business rules.

**Architecture:** `SceneEventDefinition` stores immutable trigger/condition/action configuration, while `SceneEventRunner` owns per-run state and delegates each step to a stateless `SceneAction` Resource through `SceneActionContext`. The new runner uses the existing SceneDirector request scheduler, pause coordinator, wave runtime, script executor, and transition transaction; legacy `SceneFlowRule` remains live during migration. A runtime-independent editor plugin supplies categorized creation and readable array summaries.

**Tech Stack:** Godot 4.7.2, GDScript, Godot Resource/InspectorPlugin/UndoRedo APIs, existing SceneDirector/SceneRequest/SceneEventTrigger infrastructure, project SceneTree and editor regression scripts.

**Spec:** `docs/superpowers/specs/2026-11-25-scene-event-authoring-design.md`

## Global Constraints

- Use the current local workspace as the behavior and resource baseline; do not pull, merge, rebase, or replace it with remote content.
- Preserve existing node paths, script UIDs, scene/resource references, user-authored values, Wave → Squad → Enemy deployment, and enemy AI ownership.
- Event definitions and actions are inspector Resources; spatial routes, seats, camera markers, NPCs, doors, Waves, and interactables remain scene nodes.
- SceneDirector coordinates ordering, queuing, pause, cancellation, and results; business components retain movement, spawning, inventory, quest, money, dialogue, and transition semantics.
- Event action lists remain linear. Branches are separate events with different conditions; do not add graphs, loops, jumps, or a general scripting language.
- Keep legacy `SceneFlowRule` and `SceneFlowAction` operational until all actual consumers and compatibility tests are migrated; do not delete or rewrite their UIDs.
- Run only the targeted checks named in each task unless a new failure or concrete uncertainty justifies broader coverage.
- Preserve existing assertions and user parameters. Report old and new failures separately; never loosen a test or alter saved gameplay values to make the suite green.
- At each independently verifiable stage, review and stage only that stage's files, commit, and push with `git push origin HEAD:main`; never use `git add .` or force-push.

## Review Focus

- A queued event whose flag, target, or player validity changes before start must recheck conditions and cancel without executing its first action; Task 2 adds the regression.
- A copied inline event/action Resource must not share mutable configuration with its source unless explicitly saved as an external `.tres`; Task 6 adds save/reload and duplication coverage.
- Cancellation during an NPC route, camera presentation, audio wait, or door tween must stop the provider and ignore late completion signals; Tasks 3–5 add provider-specific checks.
- A blocked Wave spawn must remain pending while a static deployment error must fail the action with the original reason; Task 3 adds both cases.
- Scene unload, region reset, and player death must release request/pause ownership exactly once even when an action synchronously completes during cancellation; Tasks 1, 2, and 8 pin this lifecycle.

---

## File Map

### New runtime model

- `movement_demo/scripts/systems/scene_events/scene_event_definition.gd` — immutable event identity, scope, trigger combination, conditions, actions, and failure policy.
- `movement_demo/scripts/systems/scene_events/scene_condition.gd` — abstract read-only condition contract.
- `movement_demo/scripts/systems/scene_events/scene_action.gd` — abstract stateless action contract and inspector metadata.
- `movement_demo/scripts/systems/scene_events/scene_action_context.gd` — one action execution identity, request ownership, target resolution, terminal result, and cancellation.
- `movement_demo/scripts/systems/scene_events/scene_event_runner.gd` — subscriptions, condition recheck, serial action advancement, region reset, cancellation, and diagnostics.

### Conditions

- `movement_demo/scripts/systems/scene_events/conditions/scene_method_condition.gd` — compatibility read-only method query.
- `movement_demo/scripts/systems/scene_events/conditions/scene_flag_condition.gd` — GameState-compatible boolean flag check.
- `movement_demo/scripts/systems/scene_events/conditions/scene_item_condition.gd` — item count check.
- `movement_demo/scripts/systems/scene_events/conditions/scene_quest_condition.gd` — QuestController status check.
- `movement_demo/scripts/systems/scene_events/conditions/scene_wave_condition.gd` — director Wave status check.
- `movement_demo/scripts/systems/scene_events/conditions/scene_node_condition.gd` — node existence, visibility, enabled state, or group membership check.

### Core action catalog

- `movement_demo/scripts/systems/scene_events/actions/flow/wait_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/flow/wait_signal_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/flow/complete_scene_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/combat/spawn_wave_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/combat/wait_wave_cleared_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/presentation/camera_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/presentation/dialogue_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/presentation/play_audio_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/actor/move_actor_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/actor/seat_actor_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/actor/set_actor_visible_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/world/set_door_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/world/call_interaction_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/state/set_flag_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/state/give_equipment_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/state/update_quest_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/transition/change_scene_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/transition/restart_scene_action.gd`
- `movement_demo/scripts/systems/scene_events/actions/advanced/run_provider_action.gd` — explicit compatibility escape hatch; not shown ahead of typed actions.

### Editor authoring

- `movement_demo/addons/scene_event_inspector/plugin.cfg` — editor plugin registration.
- `movement_demo/addons/scene_event_inspector/plugin.gd` — inspector plugin lifecycle.
- `movement_demo/addons/scene_event_inspector/inspector.gd` — SceneDirector/event/action property routing.
- `movement_demo/addons/scene_event_inspector/event_sequence_property.gd` — event/action list UI, summaries, duplicate/remove/reorder, and UndoRedo.
- `movement_demo/addons/scene_event_inspector/action_picker.gd` — categorized action creation menu.

### Existing integration and migration

- `movement_demo/scripts/systems/scene_director.gd` — owns and advances the new runner beside the legacy flow runner.
- `movement_demo/scripts/world/enemy_wave_controller.gd` — exports `event_sequences` and passes them to SceneDirector.
- `movement_demo/scripts/world/tavern_npc.gd` — preserves movement implementation while accepting explicit route/point parameters needed by `MoveActorAction`.
- `movement_demo/scripts/world/tavern_seat.gd` — keeps seat mechanics; only document/test its action-provider contract.
- `movement_demo/scripts/world/opening_sequence.gd` — reduced from cross-object orchestration to opening input/phase/objective adapter after migration.
- `movement_demo/scenes/main.tscn` — stores the opening event definitions inline on SceneDirector.
- `movement_demo/project.godot` — enables the inspector plugin.
- Current docs listed in the spec section 14 — updated only when the corresponding implementation is real.

### Tests

- `movement_demo/tests/scene_event_runtime_test.gd` — event identity, serial execution, generation, failure, and cancellation.
- `movement_demo/tests/scene_event_condition_test.gd` — typed conditions and start-time recheck.
- `movement_demo/tests/scene_action_catalog_test.gd` — core Flow/Combat/Presentation/Transition actions.
- `movement_demo/tests/scene_actor_action_test.gd` — NPC route, seat, visibility, door, state, equipment, quest, and cancellation.
- `movement_demo/tests/scene_event_inspector_test.gd` — editor creation, category menus, UndoRedo, duplication, save/reload, and summaries.
- Existing `equipment_grant_test.gd`, `opening_flow_test.gd`, `scene_reinforcement_test.gd`, `scene_event_node_test.gd`, `scene_request_test.gd`, `scene_script_cancellation_test.gd`, `scene_transition_request_test.gd`, `scene_director_authority_test.gd`, and `level_flow_test.gd` — retained and extended where ownership moves.

---

### Task 1: Typed event runtime and execution identity

**Files:**
- Create: `movement_demo/scripts/systems/scene_events/scene_event_definition.gd`
- Create: `movement_demo/scripts/systems/scene_events/scene_condition.gd`
- Create: `movement_demo/scripts/systems/scene_events/scene_action.gd`
- Create: `movement_demo/scripts/systems/scene_events/scene_action_context.gd`
- Create: `movement_demo/scripts/systems/scene_events/scene_event_runner.gd`
- Test: `movement_demo/tests/scene_event_runtime_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: existing `SceneEventSubscription.connect_trigger(host, trigger, callback)`, `SceneDirector.request_action(kind, context)`, and `SceneRequest` terminal/result contract.
- Produces: `SceneEventDefinition`, `SceneCondition.matches(context) -> bool`, `SceneAction.begin(context)`, `SceneAction.advance(context, delta)`, `SceneAction.cancel(context, reason)`, `SceneActionContext`, and `SceneEventRunner.configure/trigger_event/advance/reset_region/cancel_all/release/snapshot`.

- [ ] **Step 1: Write the failing runtime test**

Create `scene_event_runtime_test.gd` with fixture actions that synchronously complete, remain pending, fail, and emit a late completion. Assert stable `event_id` uniqueness diagnostics, AUTO/TRIGGERS/MANUAL start modes, `trigger_event(event_id)` lookup, strict action order, one terminal result per context, generation rejection of late signals, STOP versus CONTINUE failure policy, and REGION reset without replaying SCENE events.

- [ ] **Step 2: Run the runtime test and confirm the missing classes fail**

Run:

```powershell
& 'E:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:/godot/movement_demo' --script res://tests/scene_event_runtime_test.gd
```

Expected: nonzero exit or parse/load failure naming `SceneEventDefinition`, `SceneActionContext`, or `SceneEventRunner`.

- [ ] **Step 3: Implement the immutable configuration and runtime contracts**

Use these exact public shapes:

```gdscript
class_name SceneEventDefinition extends Resource
enum Scope { SCENE, REGION }
enum Combination { ANY, ALL }
enum FailurePolicy { STOP, CONTINUE }
enum StartMode { AUTO, TRIGGERS, MANUAL }
@export var event_id: StringName
@export var label: String
@export var enabled := true
@export var scope: Scope = Scope.SCENE
@export var start_mode: StartMode = StartMode.TRIGGERS
@export var combination: Combination = Combination.ANY
@export var triggers: Array[SceneEventTrigger] = []
@export var conditions: Array[SceneCondition] = []
@export var actions: Array[SceneAction] = []
@export var failure_policy: FailurePolicy = FailurePolicy.STOP
```

`SceneActionContext` owns `generation`, `event_id`, `action_index`, a `state: Dictionary`, at most one active `SceneRequest`, and `complete()`, `fail(reason)`, `cancel(reason)`, `resolve(path)`, and `request(kind, target, parameters, options)` helpers. Terminal methods must be idempotent and cancel the owned request exactly once.

- [ ] **Step 4: Implement `SceneEventRunner` using existing subscriptions**

Deep-duplicate definitions for runtime isolation, subscribe before actions can emit, collect triggers as facts, evaluate all conditions, execute one action at a time, and preserve independent waiting across events. `AUTO` starts after initialization, `TRIGGERS` requires at least one valid trigger, and `MANUAL` starts only through `trigger_event(event_id) -> bool`. Do not place request scheduling or pause policy in the runner; all such work goes through SceneDirector.

- [ ] **Step 5: Register and run the targeted test**

Add `scene_event_runtime_test` to the systems list in `run_regressions.py`, run the direct command above, then run:

```powershell
python movement_demo/tests/run_regressions.py --check
```

Expected: runtime test PASS with no `SCRIPT ERROR`/`ERROR`, and `Catalog OK`.

- [ ] **Step 6: Commit and push Task 1**

Stage only the five new runtime files, the test, and registry. Commit `feat: add typed scene event runtime`, push with `git push origin HEAD:main`, and record the exact test result.

---

### Task 2: Typed conditions and SceneDirector coexistence

**Files:**
- Create: the six condition files under `scripts/systems/scene_events/conditions/`
- Modify: `movement_demo/scripts/systems/scene_director.gd`
- Modify: `movement_demo/scripts/world/enemy_wave_controller.gd`
- Test: `movement_demo/tests/scene_event_condition_test.gd`
- Modify: `movement_demo/tests/scene_request_test.gd`
- Modify: `movement_demo/tests/scene_event_node_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: Task 1 `SceneCondition`, `SceneEventRunner`, Task 1 context identity, existing GameState/QuestController/Wave APIs.
- Produces: `event_sequences: Array[SceneEventDefinition]` on the SceneDirector host, `SceneDirector.trigger_event(event_id: StringName) -> bool`, and typed condition Resources that remain read-only.

- [ ] **Step 1: Write failing condition and coexistence tests**

Assert exact bool flag, item count, quest status, Wave status, node state/group, and method-query behavior. Add a queued-event case: trigger while a foreground guide is active, change the flag or delete the target, release the guide, and assert the first action never starts. In `scene_event_node_test`, assert legacy rules and new event sequences can listen to the same SceneEvent without consuming each other's signal.

- [ ] **Step 2: Run the new condition test and existing request/event tests**

Run each script directly. Expected: the new test fails on missing condition classes/`event_sequences`; existing tests still pass before integration.

- [ ] **Step 3: Implement condition Resources**

Use `func matches(context: SceneActionContext) -> bool` and `func diagnostics(context) -> PackedStringArray`. Conditions may resolve `/root/GameState` or paths relative to the SceneDirector host, but must never mutate state. `SceneMethodCondition` validates a public method with the existing `SceneScriptExecutor.method_error` helper and requires a bool result.

- [ ] **Step 4: Integrate the new runner without replacing legacy flows**

Add `_events` beside `_flows` in `scene_director.gd`; configure it from binding key `events`; expose `trigger_event(event_id: StringName) -> bool`; advance, reset, cancel, release, and include it in `debug_snapshot()`. Add `@export var event_sequences: Array[SceneEventDefinition] = []` to `enemy_wave_controller.gd` and pass both `"events": event_sequences` and `"rules": scene_rules`.

- [ ] **Step 5: Run targeted coexistence verification**

Run `scene_event_condition_test.gd`, `scene_event_node_test.gd`, and `scene_request_test.gd`, then `run_regressions.py --check`. Expected: all direct scripts pass, no duplicate action execution, Catalog OK.

- [ ] **Step 6: Commit and push Task 2**

Commit `feat: integrate typed scene event conditions` and push only the condition, director, controller, test, and registry files.

---

### Task 3: Flow, combat, presentation, and transition actions

**Files:**
- Create: Flow, Combat, Presentation, and Transition action files listed in the File Map
- Test: `movement_demo/tests/scene_action_catalog_test.gd`
- Modify: `movement_demo/tests/scene_reinforcement_test.gd`
- Modify: `movement_demo/tests/scene_transition_request_test.gd`
- Modify: `movement_demo/tests/director_shot_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: Task 1 `SceneActionContext.request`, existing request kinds `wave`, `presentation`, `dialogue`, `completion`, and `transition`.
- Produces: the exact core types `WaitAction`, `WaitSignalAction`, `CompleteSceneAction`, `SpawnWaveAction`, `WaitWaveClearedAction`, `CameraAction`, `DialogueAction`, `PlayAudioAction`, `ChangeSceneAction`, and `RestartSceneAction`.

- [ ] **Step 1: Write failing catalog tests for every action type**

For each type, instantiate the Resource, configure paths/parameters, run through `SceneEventRunner`, and assert the request kind and real completion boundary. Include zero-duration wait, missing target, invalid dialogue resource, cancelled camera, AudioStreamPlayer finish/stop, transition failure, and restart parameters.

- [ ] **Step 2: Add Wave blocked/error regression before implementation**

Extend `scene_reinforcement_test`: a dynamically occupied spawn remains pending and later completes; a static invalid deployment returns failed with the runtime reason. Assert `SpawnWaveAction` does not complete on request acceptance and camera presentation starts only after `wave_committed`.

- [ ] **Step 3: Run new and affected tests to capture failures**

Run `scene_action_catalog_test`, `scene_reinforcement_test`, `scene_transition_request_test`, and `director_shot_test`. Expected: only new typed-action assertions fail; preserve any unrelated baseline result exactly.

- [ ] **Step 4: Implement the ten action Resources**

Each action validates and resolves only its own fields, submits through `SceneActionContext`, and lets the existing executor determine pause/cancellation/transaction behavior. `PlayAudioAction` targets `AudioStreamPlayer`/`AudioStreamPlayer3D`, supports PLAY/STOP, optionally waits for `finished`, and stops only playback started by its own execution when cancelled.

Every action script declares the `class_name` shown in the approved SceneAction tree; do not rely on path-only anonymous Resource scripts in inspector menus.

- [ ] **Step 5: Run the catalog and affected director tests**

Expected: all new assertions pass; blocked versus failed Wave behavior remains distinct; transition prepare/commit/discard tests remain unchanged.

- [ ] **Step 6: Commit and push Task 3**

Commit `feat: add core scene event actions`, stage only the new action files and affected tests/registry, then push.

---

### Task 4: Actor actions and cancellable fixed NPC movement

**Files:**
- Create: `actions/actor/move_actor_action.gd`
- Create: `actions/actor/seat_actor_action.gd`
- Create: `actions/actor/set_actor_visible_action.gd`
- Modify: `movement_demo/scripts/world/tavern_npc.gd`
- Test: `movement_demo/tests/scene_actor_action_test.gd`
- Modify: `movement_demo/tests/scene_script_cancellation_test.gd`
- Modify: `movement_demo/tests/opening_flow_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: existing `TavernNPC.begin_scene_action/cancel_scene_action`, `TavernRoute.world_points/finish_action`, and `TavernSeat.begin_scene_action/cancel_scene_action`.
- Produces: typed move/route, seat/leave, and physical visibility actions without moving pathfinding or seat geometry into SceneDirector.

- [ ] **Step 1: Write the failing actor action test**

Cover: move to one Marker3D, traverse an authored TavernRoute in child order, use explicit points without mutating the NPC's authored route, reject empty/missing routes, leave an occupied seat before movement, sit/leave via TavernSeat, show/hide physical presence, and preserve daily `patrol_on_ready` behavior.

- [ ] **Step 2: Add cancellation and late-arrival assertions**

Cancel midway through movement and assert physics processing stops, gate ownership closes, no route finish child action runs, and a later frame cannot complete the cancelled event. Cancel scripted seating and assert no stale collision exception or input lock.

- [ ] **Step 3: Run actor, cancellation, and opening tests before changes**

Expected: new typed actor tests fail; record current opening assertions and any pre-existing local scene differences without changing them.

- [ ] **Step 4: Implement the three Actor actions and minimal NPC parameter support**

`MoveActorAction` exports `actor_path`, exactly one of `target_path`/`route_path`, `vanish_at_end`, and optional speed override; it submits a `script` provider request and restores temporary speed override on every terminal path. `SeatActorAction` exports actor/seat paths and SIT/LEAVE mode and uses existing scripted parameters. `SetActorVisibleAction` uses `set_physical_presence` when available, otherwise `visible`, and completes synchronously.

- [ ] **Step 5: Run targeted actor verification**

Run `scene_actor_action_test`, `scene_script_cancellation_test`, and `opening_flow_test`. Expected: typed tests pass, opening behavior and existing route finish modes remain unchanged.

- [ ] **Step 6: Commit and push Task 4**

Commit `feat: add directed npc actor actions` and push only actor actions, the minimal NPC change, tests, and registry.

---

### Task 5: World and state actions

**Files:**
- Create: World and State action files listed in the File Map
- Create: `actions/advanced/run_provider_action.gd`
- Modify: `movement_demo/scripts/world/player_equipment_grant.gd` only if a typed validation helper is required; preserve its script UID and provider contract
- Test: extend `movement_demo/tests/scene_actor_action_test.gd`
- Modify: `movement_demo/tests/equipment_grant_test.gd`
- Modify: relevant quest/interaction test selected after `run_regressions.py --list`

**Interfaces:**
- Consumes: `RangeDoor.begin_scene_action`, public curtain/door methods, `Interactable.interact`, `GameState.set_flag`, `PlayerEquipmentGrant`, and `QuestController.set_status/accept/refuse/complete/fail`.
- Produces: `SetDoorAction`, `CallInteractionAction`, `SetFlagAction`, `GiveEquipmentAction`, `UpdateQuestAction`, and explicit `RunProviderAction` fallback.

- [ ] **Step 1: Write failing world/state assertions**

Assert door open/close waits for the real tween and cancellation kills it; interaction reports blocked versus interacted; set-flag validates the state target; equipment grant preserves synchronous transaction semantics and rejects invalid mixtures without partial inventory change; quest action maps its enum to the existing public methods and emits the original quest signal once.

- [ ] **Step 2: Run the actor aggregate, equipment, quest, and interaction tests**

Expected: new typed action assertions fail while existing provider tests retain their baseline.

- [ ] **Step 3: Implement typed world/state actions**

Prefer explicit provider requests. `SetDoorAction` requires either the provider contract or a validated public `request_open(bool)` adapter; it must not directly animate meshes. `GiveEquipmentAction` targets a configured `PlayerEquipmentGrant` node. `UpdateQuestAction` uses a fixed enum, never an arbitrary method string.

- [ ] **Step 4: Implement and constrain the advanced fallback**

`RunProviderAction` may target only nodes with `begin_scene_action` and `cancel_scene_action`; it is categorized Advanced and has no arbitrary method mode. Keep legacy `CALL_METHOD` only in legacy SceneFlow compatibility.

- [ ] **Step 5: Run targeted verification**

Run the same four test areas plus `run_regressions.py --check`. Expected: typed actions pass, no duplicated flag/quest/equipment effects, Catalog OK.

- [ ] **Step 6: Commit and push Task 5**

Commit `feat: add world and state scene actions` and push the reviewed file set.

---

### Task 6: Categorized inspector authoring

**Files:**
- Create: all five `movement_demo/addons/scene_event_inspector/` files listed in the File Map
- Modify: `movement_demo/project.godot`
- Test: `movement_demo/tests/scene_event_inspector_test.gd`
- Modify: `movement_demo/tests/run_regressions.py` by adding `"scene_event_inspector_test.gd": "standalone --headless --editor --script"` to `SPECIAL`

**Interfaces:**
- Consumes: Tasks 1–5 Resource classes and Godot `EditorInspectorPlugin`, `EditorProperty`, `EditorUndoRedoManager`.
- Produces: categorized action picker, event/action list editing, readable collapsed summaries, duplication isolation, and diagnostics; runtime remains usable if the plugin is disabled.

- [ ] **Step 1: Write the failing headless editor test**

Open a temporary scene containing the real SceneDirector host. Assert the plugin recognizes `event_sequences`, lists the eight categories in spec order, creates each core action subtype, reorders/removes/duplicates with UndoRedo, and produces summaries such as `03 角色/NPC：Runner 沿 RunnerToStaffDoor 移动`.

- [ ] **Step 2: Add persistence and sharing assertions**

Save/reload a scene with inline event/action Resources and assert NodePaths and hidden fields survive. Duplicate an event/action and mutate the copy; assert the source is unchanged. Explicitly save one action as external `.tres` and assert two references intentionally share it.

- [ ] **Step 3: Run the editor test before plugin implementation**

Run:

```powershell
& 'E:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path 'E:/godot/movement_demo' --script res://tests/scene_event_inspector_test.gd
```

Expected: failure because the plugin/classes do not exist or the property uses the native editor.

- [ ] **Step 4: Implement the plugin with native UndoRedo**

Intercept only the SceneDirector host's `event_sequences` and the event `actions` property. Build action creation from an explicit registry of category, display name, icon hint, and script class; do not scan arbitrary project scripts at runtime. Every add/remove/duplicate/reorder operation must create one UndoRedo action and deep-duplicate inline subresources.

- [ ] **Step 5: Verify plugin-disabled runtime and editor behavior**

Run the editor test, then disable the plugin in a temporary copy of project configuration and run `scene_event_runtime_test.gd`; runtime must still load and execute saved Resources. Restore the original project configuration without overwriting user changes.

- [ ] **Step 6: Commit and push Task 6**

Commit `feat: add scene event inspector authoring` and push only plugin, test, registry, and the reviewed `project.godot` change.

---

### Task 7: Migrate tavern opening orchestration in two reviewable slices

**Files:**
- Modify: `movement_demo/scenes/main.tscn`
- Modify: `movement_demo/scripts/world/opening_sequence.gd`
- Modify: `movement_demo/scripts/ui/dialogue_ui.gd` only for stable typed cue emission if existing cue signals are insufficient
- Modify: `movement_demo/tests/opening_flow_test.gd`
- Modify: `movement_demo/tests/equipment_grant_test.gd`
- Modify: `movement_demo/tests/tavern_layout_test.gd` only if its registered path exists and the new structure changes its documented structural assertion
- Modify: `docs/gameplay/TAVERN_AUTHORING.md`

**Interfaces:**
- Consumes: the full typed action catalog, existing dialogue cue signals, TavernRoute/TavernSeat providers, and PlayerEquipmentGrant.
- Produces: opening cross-object sequences stored on `Main/SceneDirector.event_sequences`; `Opening` retains only proximity/input, phase/condition queries, objective text, and compatibility signals needed by event triggers.

- [ ] **Step 1: Add structural assertions before moving configuration**

Extend `opening_flow_test` to require named event IDs for visitor entrance, commissioner seating, merchant seating/catalog, delivery/equipment, runner departure, and scene transition. Assert `Opening` no longer directly requests presentation, dialogue, shop, seat, equipment, or runner route actions after final migration.

- [ ] **Step 2: Run current opening and equipment tests to capture the intended red state**

Expected: behavioral assertions retain the current baseline; new structural assertions fail because orchestration is still in `opening_sequence.gd`.

- [ ] **Step 3: Slice A — migrate equipment and runner delivery/departure**

Add inline event definitions on SceneDirector using `MoveActorAction`, `SetActorVisibleAction`, `GiveEquipmentAction`, and existing dialogue/route triggers. Remove only the corresponding `_deliver`, crate, grant, and departure orchestration that is now owned by the events; retain phase adapter methods needed by unconverted steps.

- [ ] **Step 4: Verify and stage Slice A as its own major step**

Run `equipment_grant_test`, `scene_actor_action_test`, and `opening_flow_test` in default, blocked-seat, and blocked-approach modes used by the existing script. Review the `main.tscn` diff for unrelated local scene/resource changes. Commit `refactor: migrate opening delivery events`, push, and report retained baseline failures separately.

- [ ] **Step 5: Slice B — migrate dialogue, camera, curtain, seating, and transition sequences**

Build the remaining named events with typed triggers/conditions/actions. Preserve dialogue text/resources, cue names, authored positions, seat paths, merchant browse-only behavior, transition transaction, and objective/phase semantics. Reduce `opening_sequence.gd` to the agreed local adapter boundary; do not move NPC motion, seat geometry, shop settlement, or dialogue rendering into it or the director.

- [ ] **Step 6: Update tavern authoring documentation for the completed migration**

Replace `Opening → EquipmentGrant` orchestration instructions with SceneDirector Event Sequences instructions while keeping the actual grant node/route/seat editing paths. Clearly distinguish local NPC patrol from directed event movement.

- [ ] **Step 7: Verify and stage Slice B**

Run the full existing `opening_flow_test` modes and `scene_interaction_test`, `shop_flow_test`, `scene_transition_request_test`, and `scene_script_cancellation_test`. If rendered capture is available, run the existing `opening_flow_test.gd -- --capture` command and inspect saved frames; do not commit capture output. Commit `refactor: author opening through scene events`, include the reviewed tavern documentation update, and push.

---

### Task 8: Convert compatibility fixtures and verify formal scene boundaries

**Files:**
- Modify: `movement_demo/tests/scene_reinforcement_test.gd`
- Modify: `movement_demo/tests/scene_transition_request_test.gd`
- Modify: `movement_demo/tests/equipment_grant_test.gd`
- Modify: `movement_demo/tests/scene_director_authority_test.gd`
- Modify: `movement_demo/tests/scene_director_test.gd` as required by new snapshots
- Inspect but do not change without saved event data: `movement_demo/scenes/world/levels/lvl_1.tscn` through `lvl_5.tscn`
- Modify: `docs/gameplay/SCENE_DIRECTOR.md`
- Modify: `docs/gameplay/ENEMY_WAVES.md`

**Interfaces:**
- Consumes: migrated opening and both new/legacy runners.
- Produces: typed-action regression fixtures; preserved legacy compatibility coverage; documented proof that existing Wave sequence modes remain deployment behavior rather than invented scene events.

- [ ] **Step 1: Convert primary test fixtures to typed events while retaining one legacy matrix**

Use `SceneEventDefinition` and typed actions in reinforcement, transition, and equipment tests. Keep a focused legacy `SceneFlowRule` test proving old saved Resources still execute; do not duplicate every scenario across both systems.

- [ ] **Step 2: Add formal-scene structure assertions**

In `scene_director_authority_test`, assert tavern and five levels expose the new event array, have one director, and retain Wave → Squad → Enemy children. Assert levels with no authored cross-object events keep `event_sequences` empty rather than receiving fabricated events.

- [ ] **Step 3: Run targeted director, Wave, and five-level verification**

Run `scene_event_runtime_test`, `scene_event_node_test`, `scene_reinforcement_test`, `scene_transition_request_test`, `equipment_grant_test`, `scene_director_authority_test`, and `level_flow_test`. Include `enemy_wave_events_test` through the enemy runner or direct Godot command. Expected: typed fixtures pass, legacy compatibility passes, actual Wave spawning/search/clear behavior is unchanged.

- [ ] **Step 4: Run rendered ownership verification when display service is available**

Run the existing `scene_reinforcement_test.gd -- --mouse-ownership-only` and `scene_director_authority_test.gd -- --capture` modes. Inspect mouse capture, camera return, dialogue/shop closure, death cancellation, and generated screenshots; do not commit logs or images.

- [ ] **Step 5: Update director and Wave authoring docs**

Make Event Sequences the primary complex-flow workflow, retain SceneEvent/Wave Event Nodes for simple direct Wave triggers, label SceneFlowRule as compatibility-only, and document why Wave deployment remains under SceneDirector children.

- [ ] **Step 6: Commit and push Task 8**

Commit `test: validate typed scene events across formal scenes` and push only reviewed tests/docs and any necessary saved-scene serialization changes.

---

### Task 9: Documentation, cleanup gate, and final focused review

**Files:**
- Modify: `README.md`
- Modify: `docs/project-layout.md`
- Modify: `docs/README.md`
- Modify: `docs/TODO.md`
- Modify: `docs/testing.md`
- Modify: `docs/superpowers/specs/2026-11-25-scene-event-authoring-design.md` only to record implemented status without rewriting user requirements
- Modify/Delete legacy runtime files only if repository-wide reference search proves they are no longer required; otherwise leave them documented as compatibility code

**Interfaces:**
- Consumes: Tasks 1–8 verified implementation and actual test output.
- Produces: accurate current documentation, no false completion claims, and a final reviewed diff ready for handoff.

- [ ] **Step 1: Search for remaining orchestration and legacy consumers**

Use `rg` for `SceneFlowRule`, `SceneFlowAction`, `request_action(&"script"`, opening cross-object helper names, and direct transition/presentation calls. Classify every hit as current typed infrastructure, intentional local business behavior, compatibility code, test, or missed migration. Fix only missed in-scope migration; do not perform unrelated refactors.

- [ ] **Step 2: Decide the legacy cleanup gate from evidence**

If any saved resource, public compatibility interface, or retained test still consumes `scene_flow_*`, keep the files and mark them compatibility-only. Delete only files with zero runtime/resource/test references and preserve `.uid` implications explicitly; a cleaner tree is not sufficient reason to break old scenes.

- [ ] **Step 3: Run final targeted verification**

At minimum run all new tests plus `scene_request_test`, `scene_event_node_test`, `scene_script_cancellation_test`, `scene_transition_request_test`, `opening_flow_test`, `scene_reinforcement_test`, `scene_director_authority_test`, `equipment_grant_test`, and `level_flow_test`, followed by `python movement_demo/tests/run_regressions.py --check`. Add broader tests only for an observed new failure or modified neighboring subsystem.

- [ ] **Step 4: Perform static and diff verification**

Run `git diff --check`, review `git diff --stat`/`--numstat`, inspect every scene/resource diff for accidental imported values, confirm no logs/caches/captures are staged, and verify all new `.gd` files have their Godot-generated `.uid` files only when Godot actually created them.

- [ ] **Step 5: Update current documentation with real results**

Document the final directories, public extension contract, inspector workflow, migrated opening scope, retained compatibility code, exact test commands/results, pre-existing failures, and untested rendered/manual areas. Do not copy historical pass counts as current evidence.

- [ ] **Step 6: Request final code review before the completion commit**

Use the repository's requesting-code-review workflow against the complete implementation diff. Resolve Critical/Important findings, rerun only affected checks, and record any accepted lower-priority limitation.

- [ ] **Step 7: Commit, push, and verify the remote**

Commit `docs: complete scene event authoring migration`, push with `git push origin HEAD:main`, compare `git rev-parse HEAD` with `git ls-remote origin refs/heads/main`, and report the commit, branch, commands, results, retained failures, and remaining compatibility scope.
