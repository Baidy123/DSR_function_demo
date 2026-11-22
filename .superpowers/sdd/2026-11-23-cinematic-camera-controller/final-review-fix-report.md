# Cinematic Camera Final Review Fix Report

Date: 2026-11-23
Branch: `cinematic-camera-controller`
Worktree: `/Users/wzy/projects/godot_projects/DSR_function_demo/.worktrees/cinematic-camera-controller`
Implementation commit: `05456b5` (`fix: close cinematic camera review gaps`)
Model/process constraint: no subagents and no pro model were used.

## Outcome

All final-review findings were addressed with focused failing-first tests and then verified across the required cinematic, scene, pause, presentation, reinforcement, catalog, diff, headless, and real-render checks.

Production boundaries remain unchanged where required:

- One active Shot; new Shot requests are busy/non-destructive and are not queued.
- Dialogue keeps player lock/foreground semantics and does not acquire world pause.
- Shot `pause_world` remains the only cinematic world-pause owner.
- Player Phantom following, weapon FOV, and player occlusion logic were not modified.
- Existing scene structure, node paths, resources, and UIDs were preserved.
- `movement_demo/tests/tavern_layout_test.gd.uid` was left unstaged and untracked.

## Findings Fixed

### Critical 1: Queued foreground bypass

Root cause:

- Scheduler queue promotion only checked whether foreground was currently occupied.
- Shot admission only checked the active foreground kind, not non-dialogue requests already queued.

Fix:

- `SceneRequestScheduler.has_queued_non_dialogue_foreground()` exposes queued shop/guide/presentation-style foreground.
- Shot admission rejects with `busy` when such a foreground is queued.
- Before a queued non-background request starts, the scheduler now calls `SceneDirector.can_start_queued_request()`.
- The scheduler rechecks immediately at the promotion boundary and keeps the foreground queued while a Shot is active.

Focused tests:

- Dialogue plus queued shop, guide, and presentation each block Shot admission without camera/pause side effects.
- A queued Shot followed by a queued shop proves the promotion recheck: the Shot starts, the shop remains queued, and the shop provider never begins until the Shot is gone.

TDD evidence:

- Red: `CINEMATIC CONTROLLER: 94/102 passed`.
- Green: `CINEMATIC CONTROLLER: 102/102 passed`.

### Important 2: Completion barrier

Root cause:

- Completion waited for the legacy `_active_presentation` but not the cinematic controller/request.

Fix:

- Added `_cinematic_barrier_active()` covering both a non-terminal cinematic request and a non-idle controller.
- Completion condition now waits for the barrier.
- `_finish_completion()` rechecks the barrier before promoting to completed.

Focused tests:

- `COMPLETE_SCENE` while an unpaused Shot is entering remains in `running`, keeps completion pending, then promotes only after the Shot returns to the player camera.
- Automatic `encounter_completed` follows the same barrier through later Shot phases.

TDD evidence:

- Red: `CINEMATIC CONTROLLER: 106/109 passed`.
- Green: `CINEMATIC CONTROLLER: 109/109 passed`.

### Important 3: Region reset scope

Root cause:

- `reset_region()` unconditionally cancelled `_cinematic_request`.
- Wave shots used the direct controller default instead of explicit REGION scope.

Fix:

- `CinematicCameraController.play_shot(shot, scope = SCOPE_SCENE)` now exposes explicit `SCOPE_SCENE` and `SCOPE_REGION`.
- Direct play and direct scene requests are SCENE scope.
- Wave-triggered shots call with `SCOPE_REGION`.
- `PLAY_CINEMATIC_SHOT` continues to use the owning `SceneFlowRule.scope`.
- Region reset cancels only REGION cinematic requests with a matching/no scope owner; SCENE shots survive and keep their own pause.

Focused tests:

- Direct `play_shot()` is request scope 0 and survives region reset.
- A region request is scope 1 and is cancelled by region reset.
- `PLAY_CINEMATIC_SHOT` preserves both SCENE and REGION rule scopes and corresponding reset behavior.
- A real Wave Shot is scope 1 and region reset cancels it and restores the player camera.

TDD evidence:

- Red: `CINEMATIC CONTROLLER: 115/118 passed`.
- Green: `CINEMATIC CONTROLLER: 118/118 passed`.
- Real Wave scope test passed in the final `CINEMATIC WAVE TRIGGER: 59/59`.

### Important 4: Reverse pause-menu admission

Root cause:

- The active cinematic check prevented opening the pause menu during a Shot, but did not prevent the reverse order.

Fix:

- `ScenePauseCoordinator.has_non_dialogue_control_owner()` reports managed pause/menu owners while excluding dialogue only.
- Cinematic admission rejects when the normal pause menu or another managed non-dialogue owner already holds control.

Focused tests:

- Open the real pause menu, then call `play_shot()`: rejected as `busy`, source camera remains current, no Shot request, no extra pause.
- Acquire a separate managed pause owner, then call `play_shot()`: rejected without switching camera or leaking pause.

TDD evidence:

- Red: `CINEMATIC CONTROLLER: 119/124 passed`.
- Green: `CINEMATIC CONTROLLER: 124/124 passed`.

### Important 5: Unpaused cinematic occlusion focus

Root cause:

- The cinematic occlusion target was positioned only at cut-in.
- Unpaused player movement left occlusion rays targeting the old player position.

Fix:

- `PresentationCamera` refreshes the cinematic occlusion focus from the source's latest follow actor on every cinematic tick.
- The same refresh runs during RETURN, so the latest player/source focus is used instead of the cut-in or previous RETURN position.
- If the source has no follow actor, the latest source view is used to derive a finite ground focus.
- `player_camera.gd` and `camera_occlusion.gd` were not changed.

Focused test:

- Uses the real `player_camera.gd` occlusion handoff and three `camera_fadeable` meshes.
- Moving the player during HOLD restores the old blocker and fades the new blocker.
- Moving again during RETURN fades the latest blocker, not the cut-in position.

TDD evidence:

- Red: `CINEMATIC CAMERA: 59/61 passed`.
- Green: `CINEMATIC CAMERA: 61/61 passed`.

### Minor 6: Shake fade durations

Root cause:

- Fade durations could exceed ENTER/RETURN phase lengths, leaving nonzero shake at a phase finish.

Fix:

- MOVE fade-in is clamped to `enter_seconds`.
- RETURN fade-out is clamped to `return_seconds`.
- RETURN completion therefore reaches zero shake amplitude before camera restoration.

Focused test:

- Uses 0.2-second phases with 1.0-second authored fade durations.
- Verifies midpoint fade, full RETURN start amplitude, near-finish clamped amplitude `0.05`, and zero at completion.

### Minor 7: Compounded noise frequency

Root cause:

- `FastNoiseLite` retained its default internal frequency while the Shot frequency was also supplied as the sample coordinate.

Fix:

- Both position and rotation noise sources explicitly set `frequency = 1.0`.
- The authored Shot frequency is applied once via sample phase.

Focused test:

- The independent expected transform builds noise with unit frequency and the authored phase.
- The rendered/executor test now validates the actual frequency path rather than mirroring the default noise frequency.

TDD evidence for Minors 6-7:

- Red: `CINEMATIC CAMERA: 63/67 passed`.
- Green: `CINEMATIC CAMERA: 67/67 passed`.

### Minor 8: Malformed direct snapshot and zero frequency

Root cause:

- Programmatic `shake_frequency = 0` passed the Shot validator despite the inspector minimum.
- Direct cinematic snapshot validation accepted the same invalid value and could acquire ownership before the executor rejected it.

Fix:

- Shot validation returns `invalid_shake_frequency` for non-finite or values below `0.01`.
- Controller and executor snapshot validation enforce the same minimum.
- Direct malformed snapshots reject before SceneRequest ownership, pause acquisition, camera switch, or occlusion lease.

Focused tests:

- Programmatic zero frequency returns `invalid_shake_frequency`.
- Direct missing-shake-key snapshot fails as `invalid_shot` with no request/camera/pause.
- Direct zero-frequency snapshot fails with no request/camera/pause.
- Executor zero-frequency snapshot rejects before acquiring the occlusion lease.

TDD evidence:

- Red: `CINEMATIC SHOT: 6/7`, `CINEMATIC CONTROLLER: 125/126`, camera malformed-snapshot checks failing.
- Green: `CINEMATIC SHOT: 7/7`, `CINEMATIC CONTROLLER: 126/126`, `CINEMATIC CAMERA: 67/67`.

### Minor 9: Ledger checkbox reconciliation

- Tasks 1-6 in `.superpowers/sdd/2026-11-23-cinematic-camera-controller/progress.md` are now checked.
- The ledger records the final fix wave and successful verification scope.

### Minor 10: Unrelated UID

- `movement_demo/tests/tavern_layout_test.gd.uid` remains untracked and was not staged.

## Verification

### Cinematic suites

| Check | Result |
| --- | --- |
| `cinematic_shot_test` | 7/7 passed |
| `cinematic_camera_test` | 67/67 passed |
| `cinematic_controller_test` | 126/126 passed |
| `cinematic_wave_trigger_test` | 59/59 passed |
| `cinematic_debug_test` | 33/33 passed |
| `cinematic_interruption_test` headless | 219/219 passed |
| `cinematic_interruption_test -- --capture` real renderer | 233/233 passed |

The rendered run used:

`OpenGL API 4.1 Metal - 91.7 - Compatibility - Apple M6`

Five captures were written under `movement_demo/logs/cinematic-camera-capture/`, which is ignored and not committed.

### Related suites and checks

| Check | Result |
| --- | --- |
| `scene_director_test` | 151/151 passed |
| `scene_reinforcement_test` headless | 119/119 passed |
| `pause_menu_test` headless | 50/50 passed |
| `presentation_camera_test` headless | 49/49 passed |
| `shop_catalog_test` | 39/39 passed |
| `python3 movement_demo/tests/run_regressions.py --check` | `Catalog OK` |
| `git diff --check` | clean, no output |

### Render capture hashes

| Capture | SHA-256 |
| --- | --- |
| `00-player-baseline.png` | `9a9f2bd7a629f6f3c0db00fbed38d0443e2fff3ea897e24dd3a23e7ef41844a0` |
| `01-free-camera-composition.png` | `35ab6df7522cf52c3275e25d5a03c9461d2c54b60cdb2ed0ba6d062d93c2cd2c` |
| `02-orthographic-zoom.png` | `7eb7d4e8e83b758af19e38b3b9ed119327680bce46a0cf0a640e2f49cca13660` |
| `03-deterministic-shake-midpoint.png` | `263d0cd8506d6774470f02c7f3018c78021af0e57aea2f475bcbd41303c065e1` |
| `04-returned-player-view.png` | `9a9f2bd7a629f6f3c0db00fbed38d0443e2fff3ea897e24dd3a23e7ef41844a0` |

The baseline and returned-player captures match, while free composition, zoom, and shake are distinct.

## Files Changed

Production:

- `movement_demo/scripts/systems/scene_director.gd`
- `movement_demo/scripts/systems/scene_request_scheduler.gd`
- `movement_demo/scripts/systems/scene_pause_coordinator.gd`
- `movement_demo/scripts/systems/cinematic/cinematic_camera_controller.gd`
- `movement_demo/scripts/systems/cinematic/cinematic_shot_3d.gd`
- `movement_demo/scripts/systems/presentation_camera.gd`

Tests:

- `movement_demo/tests/cinematic_shot_test.gd`
- `movement_demo/tests/cinematic_camera_test.gd`
- `movement_demo/tests/cinematic_controller_test.gd`
- `movement_demo/tests/cinematic_wave_trigger_test.gd`
- `movement_demo/tests/cinematic_interruption_test.gd`

Documentation and ledger:

- `docs/gameplay/CAMERA.md`
- `docs/gameplay/SCENE_DIRECTOR.md`
- `docs/gameplay/ENEMY_WAVES.md`
- `docs/project-layout.md`
- `docs/testing.md`
- `docs/superpowers/specs/2026-11-23-cinematic-camera-controller-design.md`
- `.superpowers/sdd/2026-11-23-cinematic-camera-controller/progress.md`

## Concerns and Known Boundaries

- Godot still emits the macOS `get_system_ca_certificates` `ret != noErr` startup diagnostic. It did not affect exit codes or assertions.
- The intentionally failed-spawn fixtures still emit the expected “本波还没有小队” warning.
- `shop_catalog_test` intentionally logs its duplicate-ID warning while asserting the validation path.
- The known baseline `camera_occlusion_test` result remains outside this fix scope; `player_camera.gd` and `camera_occlusion.gd` were not modified. The new cinematic moving-player test covers the presentation handoff without changing player occlusion logic.
- `movement_demo/tests/tavern_layout_test.gd.uid` remains untracked as requested.
