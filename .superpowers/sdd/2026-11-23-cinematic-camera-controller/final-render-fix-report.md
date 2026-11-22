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

The initial fixture fix changed only the interruption test and its testing documentation; the focused-review follow-up below added the presentation activity signal.

- Added `_await_view_settled()` to wait for the source camera Transform, complete source lens state, and player Transform to remain equal for three consecutive frame cycles.
- The wait is bounded to 240 frames, reports a diagnostic on timeout, and records `view_settled` in the fixture.
- The failed-spawn assertion now explicitly verifies that natural player/camera settling completed before baseline capture.
- Installed a test-only `node_added` probe and per-frame current-camera sampling for the failed Wave window. The case now verifies that no `PresentationCamera` was created, replaced, or made current, while retaining the existing request, foreground, pause, controller-idle, and `_assert_clean()` checks.
- Kept shared `_assert_clean()` semantics unchanged for cases with actual cinematic ownership.
- Updated `docs/testing.md` to the final 222/222 headless and 236/236 real-render totals, and documented the stabilization and synchronous no-takeover checks. Updated the camera guide to point at the stabilized fixture explanation instead of a baseline failure.

No camera ownership or timing behavior, Phantom follow, weapon FOV, player occlusion, scene, resource, or UID files were modified. `PresentationCamera` later gained the synchronous observability signal described in the focused-review follow-up.

## Verification

| Check | Result |
| --- | --- |
| `cinematic_interruption_test` headless | 222/222 passed |
| `cinematic_interruption_test -- --capture` real OpenGL/Metal | 236/236 passed |
| Same real-render capture repeated five times after the fixture timing fix | 235/235 on all five previous runs; later synchronous-probe run passed 236/236 |
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

Godot 4.7 does not expose a built-in `Camera3D.became_current` signal in this engine build. The project `PresentationCamera` therefore now emits `became_current` synchronously immediately after either real activation path calls `make_current()`:

- `start_presentation()`
- `start_cinematic_shot()`

This adds observability only; presentation ownership and camera timing are unchanged.

The failed-spawn test now:

- Connects `became_current` for the existing controller `PresentationCamera`.
- Uses `SceneTree.node_added` to connect any `PresentationCamera` created during the failed Wave window.
- Counts activations by camera instance ID, so a same-call activation plus restore is detected even when the final current-camera sample is unchanged.
- Retains controller-idle, request, foreground, pause, source Transform/lens, player Transform, instance-identity, no-new-camera, and frame-end current-camera checks.
- Disconnects every probe connection and verifies no connection remains.

The focused counter self-test starts a real cinematic presentation activation, verifies exactly one synchronous activation was counted, cancels the presentation, verifies the source camera was restored, and clears the self-test count before the failed Wave request.

Evidence:

- Red with the old production interface: `CINEMATIC INTERRUPTION: 220/222 passed`; the new self-test and zero-activation assertions failed because `PresentationCamera` had no `became_current` signal.
- Green headless: `CINEMATIC INTERRUPTION: 222/222 passed`.
- Green real OpenGL/Metal with `-- --capture`: `CINEMATIC INTERRUPTION: 236/236 passed`.
- Existing checks after the follow-up: `cinematic_controller_test` 126/126, `scene_director_test` 151/151, `run_regressions.py --check` reports `Catalog OK`, and `git diff --check` is empty.

Documentation now states that the failed Wave emitted zero synchronous `became_current` activations, created no replacement, left no probe connection, and retained all prior idle/request/pause/baseline invariants.
