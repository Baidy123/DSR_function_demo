# SDD ledger — plan: docs/superpowers/plans/2026-11-23-cinematic-camera-controller.md

Spec: docs/superpowers/specs/2026-11-23-cinematic-camera-controller-design.md
Worktree: /Users/wzy/projects/godot_projects/DSR_function_demo/.worktrees/cinematic-camera-controller
Branch: cinematic-camera-controller
Baseline: ed1f528; `run_regressions.py --check` => Catalog OK.

## Pre-flight scan

| Tasks / area | Producer | Consumer | Finding and ruling |
| --- | --- | --- | --- |
| 1 → 2 | `CinematicShot3D.runtime_snapshot()` fields | Cinematic camera test and executor | Consistent: transform, projection/lens, timing, shake and pause fields are all named in both tasks. |
| 2 → 3 | `start_cinematic_shot(source, snapshot, request_id)` | Controller executor | Consistent signature; legacy `start_presentation()` remains for compatibility. |
| 3 → 4 | `play_shot() -> Dictionary` | Wave and SceneFlowAction | Consistent admission contract; busy is non-destructive. |
| 3 → 5 | `play_shot`, `cancel_shot`, `get_snapshot` | Debug panel | Consistent; debug task does not write camera state directly. |
| 3 and 4 | `scene_director.gd` request kind and dispatch | Wave/flow trigger | Ordered: controller request kind first, trigger integration second. |
| 3 and 6 | Pause/cancel interfaces | Interruption matrix | Ordered: controller lifecycle must pass before interruption suite. |
| 1 self-check | Shot config/test | Test expects `invalid_enter_seconds` | Step 4 explicitly changes validation order; no contradiction remains. |
| 2 self-check | Three-phase loop | Large delta test | Plan mandates preserving the three-transition loop; no single-phase shortcut. |
| 3 self-check | Public controller/SceneDirector API | Controller and director snippets | `execute_request`, `pause_token`, `complete_cinematic_request` are explicitly declared. |
| 4 self-check | New Wave path vs old presentation | Migration | New path has priority; old path is fallback/skip only. |
| 5 self-check | Debug panel input/output | DebugSettings | Panel reads controller API only; no camera ownership. |
| 6 self-check | Interruption assertions | Pause/camera cleanup | Matrix checks camera, pause ledger, mouse and business state after every case. |

Rulings: none required during pre-flight.

## Tasks

- [x] Task 1: CinematicShot3D 单镜头定义
- [x] Task 2: PresentationCamera 自由机位、缩放与抖动
- [x] Task 3: CinematicCameraController 与 SceneDirector 集成
- [x] Task 4: Wave 和 SceneFlowAction 触发 Shot
- [x] Task 5: CinematicCameraDebug 调试面板
- [x] Task 6: 特殊打断矩阵、真实渲染和文档收尾

Task 1: implementer base ed1f528; commit 3a90964; focused 6/6 + Catalog OK; task review clean.
Task 1: Ruling — brief's 7/7 expected count is a typo; the six verbatim assertions cover every listed requirement and the reviewer confirmed no seventh check was omitted. Cost if wrong: one small missing assertion could be added later without changing production API.
Task 1: minor (deferred) — runtime-only group membership is not visible to editor group queries.
Task 1: minor (deferred) — programmatic shake_frequency=0 passes validation although inspector minimum is 0.01.
Task 1: minor (deferred) — cinematic_shot_test preloads unused Shot constant.
Task 1: minor (deferred) — new script/test UID sidecars should be generated before final commit.
Task 1: complete (commits ed1f528..3a90964, review clean)

Task 2: implementer base 3a90964; cinematic-shot executor implementation dispatched.
Task 2: implementer commit 98b3e2f; cinematic_camera_test 5/5, presentation_camera_test 49/49, Catalog OK; task review dispatched with deepseek-flash.
Task 2: untracked UID sidecars retained for final cleanup; no unrelated source changes.
Task 2: review ❌ — target projection/non-numeric properties not applied; cinematic occlusion lease missing; shake envelope incorrect per phase; RETURN captures shaken pose; rotation shake not Shot-local; tests too shallow.
Task 2: fix round 1/5 — fresh deepseek-flash implementer because user disallows the original pro model; findings and covering-test requirements dispatched.
Task 2: fix round 1/5 (8 attempted; cinematic_camera_test 57/57, presentation_camera_test 49/49, Catalog OK; commit dc56491) — scoped re-review dispatched with deepseek-flash.
Task 2: fix round 1/5 (7 addressed, 1 minor open — missing shake fields can fail after lease acquisition; commits 98b3e2f..dc56491)
Task 2: minor (deferred) — malformed shake-enabled snapshot with missing shake keys can still error after lease acquisition; valid CinematicShot3D snapshot always supplies them, and controller validation will reject malformed shots before this executor in Task 3.
Task 2: complete (commits 3a90964..dc56491, 1 deferred minor)

Task 3: implementer base dc56491; controller + SceneDirector integration dispatched with deepseek-flash max.
Task 3: carried ruling — controller must validate shot configuration before creating a request; executor must not be relied on to recover from malformed shake snapshots.
Task 3: implementer commit 244554b; controller 65/65, scene director 151/151, pause menu 50/50, Catalog OK; task review dispatched with deepseek-flash.
Task 3: extra modified file `enemy_wave_runtime.gd` is proposed as infrastructure filtering for the new visible SceneDirector child; review must validate scope.
Task 3: review ❌ — shot_finished emitted before request settlement can orphan request; explicit cancellation settles as failed; direct duplicate cinematic request overwrites active slot; tests miss these paths.
Task 3: fix round 1/5 — resumed original deepseek-flash implementer with lifecycle findings.
Task 3: fix round 1/5 (3 attempted; controller 83/83, scene director 151/151, pause menu 50/50, Catalog OK; commit 2234066) — scoped re-review dispatched with deepseek-flash.
Task 3: fix round 2/5 — original 3 findings addressed, but re-review found Important re-entrant cancellation leak because `_cinematic_request` is assigned after `execute_request()` emits public start signals.
Task 3: fix round 2/5 (controller 91/91, scene director 151/151, pause menu 50/50, Catalog OK; commit 6b08355) — scoped re-review dispatched with deepseek-flash.
Task 3: fix round 2/5 (1 addressed, 0 open — commits 2234066..6b08355)
Task 3: complete (commits dc56491..6b08355, review clean)

Task 4: implementer base 6b08355; Wave and SceneFlowAction trigger integration dispatched with deepseek-flash max.
Task 4: implementer commit d685ddc; wave trigger 43/43, reinforcement 119/119, scene director 151/151, Catalog OK; task review dispatched with deepseek-flash.
Task 4: review ❌ — invalid non-empty Shot path falls through to legacy; legacy fields still affect deployment authorization when new Shot path exists; missing editor warning setter is minor.
Task 4: fix round 1/5 — resumed original deepseek-flash implementer with priority findings.
Task 4: fix round 1/5 (wave trigger 57/57, reinforcement 119/119, scene director 151/151, Catalog OK; commit e35493d) — scoped re-review dispatched with deepseek-flash.
Task 4: fix round 1/5 (3 addressed, 0 open — commits d685ddc..e35493d)
Task 4: minor (deferred) — setter warning refresh is implemented but not behaviorally verified in headless test.
Task 4: complete (commits 6b08355..e35493d, 1 deferred minor)

Task 5: implementer base e35493d; CinematicCameraDebug panel dispatched with deepseek-flash max.
Task 5: implementer commit d4c71cd; debug 29/29, controller 91/91, Catalog OK; task review dispatched with deepseek-flash.
Task 5: `debug_mode_test` still aborts at pre-existing `CoordinatorPaths/Overlay` mismatch; report preserves original assertion. Review must ensure no new debug side effect.
Task 5: review clean — Minor deferred: active status can show selected shot's pause_world; scene A→B replacement not covered; new debug script/test UID sidecars pending.
Task 5: complete (commits e35493d..d4c71cd, 3 deferred minors)

Task 6: implementer base d4c71cd; interruption matrix, real render, UID cleanup and docs dispatched with deepseek-flash max.
Task 6: implementer commit 85382db; six cinematic suites pass; interruption 160/160 headless and 174/174 rendered; related regressions pass; Catalog OK.
Task 6: known baseline camera_occlusion_test remains 44/46 on ed1f528; unrelated tavern UID remains untracked. Task review dispatched with deepseek-flash.
Task 6: review ❌ — dialogue pause coexistence test fabricated a pause token; terminal cleanup misses scheduler request and active shake; failed-spawn fixture has no configured Shot. Spec/docs overstate independent dialogue world pause.
Task 6: Ruling — production dialogue uses its real control/lock path (`pause_world=false`), not a world-pause token; Shot `pause_world` is the only cinematic world pause. Tests/docs must reflect the real path. Cost if wrong: dialogue handling remains as existing production behavior rather than changing gameplay pause semantics.
Task 6: fix round 1/5 — resumed original deepseek-flash implementer.
Task 6: fix round 1/5 (interruption 200/200 headless, 214/214 rendered; commit c5e4cc9) — scoped re-review dispatched with deepseek-flash.
Task 6: fix round 2/5 — finding 1 partially fixed because cinematic_controller_test still uses fabricated pausing dialogue token; clean helper doesn't compare source pose/lens; load cases no active shake; testing docs overclaim.
Task 6: fix round 2/5 (controller 90/90, interruption 219/219 headless, 233/233 rendered; commit 00efe5a) — scoped re-review dispatched with deepseek-flash.
Task 6: fix round 2/5 (3 addressed, 0 open; commits c5e4cc9..00efe5a)
Task 6: complete (commits d4c71cd..00efe5a, review clean)

Final whole-branch review: base ed1f528, head 00efe5a; dispatched with deepseek-flash max.
Deferred minors for final triage:
- Task 1: runtime-only Shot group membership not visible to editor group queries.
- Task 1: programmatic shake_frequency=0 passes validation though inspector minimum is 0.01.
- Task 1: unused Shot preload in cinematic_shot_test.
- Task 2: malformed shake snapshot can error after lease acquisition, but controller validation blocks malformed Shots.
- Task 4: Wave warning setter refresh only statically/headless-setter tested.

Final review ❌ — Critical queued foreground can start during active Shot; Important completion does not wait for unpaused Shot; region reset cancels SCENE-scoped Shot; Shot can start while pause menu active; unpaused occlusion target stays frozen. Minor shake fade/frequency edge cases, ledger boxes, unrelated UID.
Final fix wave: one fresh deepseek-flash implementer dispatched with all findings; one scoped re-review will follow.
Final fix wave: all Critical and Important findings plus public Minors fixed with focused tests; cinematic suites pass headless, interruption passes real-render capture, related scene/pause/presentation/reinforcement/catalog checks pass.
