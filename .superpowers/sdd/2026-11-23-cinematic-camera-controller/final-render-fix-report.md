# Cinematic Interruption Final Render Fix Report

Date: 2026-11-23
Branch: `cinematic-camera-controller`
Worktree: `/Users/wzy/projects/godot_projects/DSR_function_demo/.worktrees/cinematic-camera-controller`
Observed failing base: `6d6445b`
Constraint: no subagents and no pro model were used.

## Failure

The required real-render command:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path movement_demo \
  --script res://tests/cinematic_interruption_test.gd -- --capture
```

reported `CINEMATIC INTERRUPTION: 232/233 passed` on final HEAD `6d6445b`. The only failure was:

```text
FAIL failed spawn: player camera Transform/lens and player Transform unchanged
```

The same matrix passed in headless mode. The failed-spawn fixture had a valid `CinematicShot3D` path, but its Wave deployment failed and the controller remained idle with no request or pause.

## Root Cause

The failed-spawn fixture captured `view_baseline` after only four physics steps and one process handoff. That was earlier than the normal player camera rig and Phantom camera follow had necessarily converged from their initial scene pose. The pending source-camera lens/follow settling could continue during the subsequent eight sampled steps under the real renderer.

The shared `_assert_clean()` assertion was therefore doing its intended job: it observed a changed source camera or player transform after the recorded baseline. There was no evidence that a Shot, request, pause, or presentation-camera takeover had occurred. The failure was fixture timing, not cinematic leakage.

The raw failure was not reproduced in one normal run or eight additional unmodified real-render runs on this machine. The timing boundary is still structurally present in the old fixture and matches the reported Metal failure.

## Fix

The initial fixture fix changed only the interruption test and its testing documentation. The focused-review follow-ups below replaced the original synchronous observability signal with a callback-free, monotonic presentation activation counter.

- Added `_await_view_settled()` to wait for the source camera Transform, complete source lens state, and player Transform to remain equal for three consecutive frame cycles.
- The wait is bounded to 240 frames, reports a diagnostic on timeout, and records `view_settled` in the fixture.
- The failed-spawn assertion now explicitly verifies that natural player/camera settling completed before baseline capture.
- Installed a test-only `node_added` probe and per-frame current-camera sampling for the failed Wave window. The case now verifies that no `PresentationCamera` was created, replaced, or made current, while retaining the existing request, foreground, pause, controller-idle, and `_assert_clean()` checks.
- Kept shared `_assert_clean()` semantics unchanged for cases with actual cinematic ownership.
- Updated `docs/testing.md` to the final 224/224 headless and 238/238 real-render totals, and documented the stabilization and callback-free no-takeover checks. Updated the camera guide to point at the stabilized fixture explanation instead of a baseline failure.

No camera ownership or timing behavior, Phantom follow, weapon FOV, player occlusion, scene, resource, or UID files were modified. `PresentationCamera` exposes the read-only counter described in the final follow-up.

## Verification

| Check | Result |
| --- | --- |
| `cinematic_interruption_test` headless | 224/224 passed |
| `cinematic_interruption_test -- --capture` real OpenGL/Metal | 238/238 passed |
| Earlier real-render capture runs after fixture timing stabilization but before the counter tests | 235/235 on all five previous runs |
| `cinematic_controller_test` headless | 126/126 passed |
| `scene_director_test` headless | 151/151 passed |
| `python3 movement_demo/tests/run_regressions.py --check` | `Catalog OK` |
| `git diff --check` | no output |

The five real-render capture hashes remain unchanged, including the identical player baseline and returned-view hashes:

- `00-player-baseline.png`: `9a9f2bd7a629f6f3c0db00fbed38d0443e2fff3ea897e24dd3a23e7ef41844a0`
- `04-returned-player-view.png`: `9a9f2bd7a629f6f3c0db00fbed38d0443e2fff3ea897e24dd3a23e7ef41844a0`

Expected diagnostics remain limited to the macOS root-certificate warning and the deliberately failing Wave's missing-Squad warning. Neither is an assertion failure.

## Concerns

- The original race could not be reproduced on demand after the failure report, so the evidence is the reported failing output plus the structurally unstable four-frame baseline in the old fixture. The fixed sequence passed five consecutive real-render runs.
- `movement_demo/tests/tavern_layout_test.gd.uid` remains untracked and was deliberately not staged.
- The pre-existing uncommitted `progress.md` change was preserved and not included in this fix commit.

## Focused Review Follow-up

A focused review found that the first no-takeover probe could miss a synchronous `make_current()` followed by source restoration inside one call window: it counted newly added cameras but sampled camera ownership only at frame ends.

An intermediate follow-up added a custom synchronous `PresentationCamera.became_current` signal. A further focused review identified that signal as an Important reentrancy risk: a listener could cancel before `start_cinematic_shot()` returned, leaving controller state inconsistent. That signal was removed entirely in the final follow-up below.

## Final Callback-Free Counter Follow-up

`PresentationCamera` now exposes the read-only property `presentation_activation_count`. The private backing count increments immediately after each actual `PresentationCamera.make_current()` call in:

- `start_presentation()`
- `start_cinematic_shot()`

The counter is monotonic, never resets, and introduces no listener, callback, or ownership/timing change. The failed-spawn test no longer references `became_current`.

The failed-spawn fixture now:

- Starts and cancels one real cinematic presentation manually, then verifies the activation counter increased by exactly one and the source camera was restored.
- Samples the counter again before the failed Wave and verifies it is unchanged after the failure window.
- Keeps the existing `SceneTree.node_added` observer only for unexpected camera creation or replacement.
- Installs test-only camera lifecycle connections, verifies they remain present before cleanup, explicitly disconnects them, verifies they are absent, and only then clears the probe's tracking dictionaries.
- Retains controller-idle, request, foreground, pause, source Transform/lens, player Transform, instance-identity, no-new-camera, and frame-end current-camera checks.
- Retains the settled baseline and all prior behavior checks.

Evidence:

- Red with the old signal-based interface: `CINEMATIC INTERRUPTION: 222/224 passed`. The self-test and failed-Wave assertions both failed because no activation counter existed, while the signal-removal condition also failed.
- Green headless: `CINEMATIC INTERRUPTION: 224/224 passed`.
- Green real OpenGL/Metal with `-- --capture`: `CINEMATIC INTERRUPTION: 238/238 passed`.
- `cinematic_controller_test` 126/126, `scene_director_test` 151/151, `run_regressions.py --check` reports `Catalog OK`.

Documentation now states that the failed Wave left the callback-free activation counter unchanged, created no replacement, left no probe connection, and retained all prior idle/request/pause/baseline invariants.
