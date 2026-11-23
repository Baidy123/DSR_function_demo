# 剧情演出相机通用控制器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增加场景级单次剧情镜头控制器，让剧情节点和真实刷怪都能播放可手摆、可缩放、可抖动并可靠恢复玩家相机的 Shot。

**Architecture:** `CinematicCameraController` 作为可见 SceneDirector 子节点统一接收单 Shot 请求；`CinematicShot3D` 保存完整机位与镜头参数；现有 `presentation_camera.gd` 扩展为通用执行器。SceneDirector 继续持有暂停、死亡、加载、区域和取消权威，玩家相机内部的 Phantom、武器视野与遮挡职责不变。

**Tech Stack:** Godot 4.7.2、GDScript、SceneDirector/SceneRequest、ScenePauseCoordinator、现有 PresentationCamera、Godot headless/OpenGL 测试脚本。

**Spec:** `docs/superpowers/specs/2026-11-23-cinematic-camera-controller-design.md`

## Global Constraints

- 只管理剧情演出相机，不改 Phantom Camera 跟随、武器 Aim Range、玩家相机 Size/FOV 或遮挡透明逻辑。
- 一次只允许一个活动 Shot；活动期间新请求返回 `busy`，不排队、不替换。
- 每个 Shot 独立配置 `pause_world`。
- 镜头可与对话并存；商店、普通交互、引导或其他前台请求存在时拒绝新镜头。
- 镜头与对话各自释放暂停令牌，任何一方结束都不能提前解除另一方的暂停。
- 死亡、切场、加载、区域复位、控制器卸载和调试取消必须走同一取消路径。
- 保留 `scripts/systems/presentation_camera.gd`、`scenes/player/presentation_camera.tscn` 的路径、脚本 UID 和旧公开接口。
- 保留既有 Wave/Squad、玩家相机、Phantom 节点和关卡节点路径。
- 单 Shot 无队列、无自动接力；返回玩家最新画面后才报告完成。
- 抖动必须确定性可复现，并只叠加在运行时相机，不写回 Shot 或玩家相机。
- 自动测试同时覆盖实际行为和特殊打断后的暂停/相机所有权清理。

---

### Task 1: CinematicShot3D 单镜头定义

**Files:**
- Create: `movement_demo/scripts/systems/cinematic/cinematic_shot_3d.gd`
- Create: `movement_demo/scenes/cinematic/cinematic_shot_3d.tscn`
- Create: `movement_demo/tests/cinematic_shot_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: Godot `Camera3D` 的 Transform、projection、size、fov、near/far、offsets、environment、attributes、compositor。
- Produces: `class_name CinematicShot3D`、`GROUP`、`Easing`、`configuration_error() -> StringName`、`runtime_snapshot() -> Dictionary`。

- [ ] **Step 1: 写失败测试**

```gdscript
extends SceneTree

const Shot = preload("res://scripts/systems/cinematic/cinematic_shot_3d.gd")
const ShotScene = preload("res://scenes/cinematic/cinematic_shot_3d.tscn")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func _run() -> void:
	var shot: Camera3D = ShotScene.instantiate()
	root.add_child(shot)
	check(shot is Camera3D and not shot.current, "Shot scene is an inactive Camera3D")
	check(shot.is_in_group(&"cinematic_shot"), "Shot joins the cinematic_shot group")
	check(not shot.is_processing() and not shot.is_physics_processing(), "Shot does not self-tick")
	check(shot.configuration_error() == &"", "Default Shot configuration is valid")
	var snapshot: Dictionary = shot.runtime_snapshot()
	check(snapshot.has("transform") and snapshot.has("size") and snapshot.has("enter_seconds"),
		"Runtime snapshot contains pose, lens and timing")
	shot.enter_seconds = NAN
	check(shot.configuration_error() == &"invalid_enter_seconds", "Invalid enter time is rejected")
	shot.free()
	print("CINEMATIC SHOT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_shot_test.gd
```

Expected: FAIL because the Shot script/scene does not exist.

- [ ] **Step 3: 实现最小 Shot 定义**

```gdscript
@tool
class_name CinematicShot3D
extends Camera3D

const GROUP := &"cinematic_shot"
enum Easing { LINEAR, SMOOTH, EASE_IN, EASE_OUT, EASE_IN_OUT }

@export_range(0.0, 10.0, 0.05, "suffix:s") var enter_seconds := 0.6
@export_range(0.0, 30.0, 0.05, "suffix:s") var hold_seconds := 1.2
@export_range(0.0, 10.0, 0.05, "suffix:s") var return_seconds := 0.6
@export var pause_world := true
@export var transition_easing: Easing = Easing.SMOOTH
@export var shake_enabled := false
@export var shake_position_amplitude := Vector3(0.1, 0.05, 0.1)
@export var shake_rotation_degrees := Vector3.ONE
@export_range(0.01, 60.0, 0.01) var shake_frequency := 12.0
@export_range(0.0, 5.0, 0.01) var shake_fade_in_seconds := 0.15
@export_range(0.0, 5.0, 0.01) var shake_fade_out_seconds := 0.25
@export var shake_seed := 0

func _ready() -> void:
	current = false
	set_process(false)
	set_physics_process(false)
	if not Engine.is_editor_hint(): add_to_group(GROUP)

func configuration_error() -> StringName:
	for value in [enter_seconds, hold_seconds, return_seconds,
			shake_frequency, shake_fade_in_seconds, shake_fade_out_seconds]:
		if not is_finite(float(value)) or float(value) < 0.0: return &"invalid_timing"
	if not is_finite(enter_seconds): return &"invalid_enter_seconds"
	if not shake_position_amplitude.is_finite() or not shake_rotation_degrees.is_finite():
		return &"invalid_shake"
	return &""

func runtime_snapshot() -> Dictionary:
	return {
		"transform": global_transform,
		"projection": projection, "keep_aspect": keep_aspect,
		"size": size, "fov": fov, "frustum_offset": frustum_offset,
		"near": near, "far": far, "cull_mask": cull_mask,
		"h_offset": h_offset, "v_offset": v_offset,
		"environment": environment, "attributes": attributes, "compositor": compositor,
		"enter_seconds": enter_seconds, "hold_seconds": hold_seconds,
		"return_seconds": return_seconds, "pause_world": pause_world,
		"transition_easing": transition_easing, "shake_enabled": shake_enabled,
		"shake_position_amplitude": shake_position_amplitude,
		"shake_rotation_degrees": shake_rotation_degrees,
		"shake_frequency": shake_frequency,
		"shake_fade_in_seconds": shake_fade_in_seconds,
		"shake_fade_out_seconds": shake_fade_out_seconds, "shake_seed": shake_seed,
	}
```

Create the scene with one root `Camera3D`, `current = false`, script set to the new script, and no processing.

- [ ] **Step 4: 修正错误码测试**

`configuration_error()` 必须按测试期望返回 `invalid_enter_seconds`，因此先单独检查
`enter_seconds`，再检查其余时间值。

```gdscript
if not is_finite(enter_seconds) or enter_seconds < 0.0:
	return &"invalid_enter_seconds"
```

- [ ] **Step 5: 注册并运行测试**

Add `"cinematic_shot_test"` to `SYSTEM_TESTS` in `movement_demo/tests/run_regressions.py`, then run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_shot_test.gd
python3 movement_demo/tests/run_regressions.py --check
```

Expected: `CINEMATIC SHOT: 7/7 passed` and `Catalog OK`.

- [ ] **Step 6: 提交**

```bash
git add movement_demo/scripts/systems/cinematic/cinematic_shot_3d.gd \
  movement_demo/scenes/cinematic/cinematic_shot_3d.tscn \
  movement_demo/tests/cinematic_shot_test.gd movement_demo/tests/run_regressions.py
git commit -m "feat: add cinematic shot definition"
```

---

### Task 2: 扩展 PresentationCamera 执行自由机位、缩放与抖动

**Files:**
- Modify: `movement_demo/scripts/systems/presentation_camera.gd`
- Create: `movement_demo/tests/cinematic_camera_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: Task 1 的 `runtime_snapshot()` 字典。
- Produces: `start_cinematic_shot(source: Camera3D, snapshot: Dictionary, request_id: int) -> bool`、`is_cinematic_shot() -> bool`；旧 `start_presentation(source, focus, options, id)` 保持。

- [ ] **Step 1: 写失败测试**

```gdscript
extends SceneTree

const Shot = preload("res://scripts/systems/cinematic/cinematic_shot_3d.gd")
const Presentation = preload("res://scenes/player/presentation_camera.tscn")

var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var world: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var source := Camera3D.new()
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.size = 12.0
	source.position = Vector3(0, 8, 6)
	source.rotation_degrees.x = -55.0
	world.add_child(source)
	source.make_current()
	var shot: Camera3D = Shot.new()
	shot.position = Vector3(8, 5, -4)
	shot.rotation_degrees = Vector3(-48, 25, 0)
	shot.size = 6.0
	shot.enter_seconds = 1.0
	shot.hold_seconds = 1.0
	shot.return_seconds = 1.0
	world.add_child(shot)
	var camera: Camera3D = Presentation.instantiate()
	world.add_child(camera)
	camera.presentation_finished.connect(func(id: int, result: StringName):
		results.append({"id": id, "result": result}))
	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 41), "Shot starts")
	check(camera.is_current() and camera.global_transform.is_equal_approx(source.global_transform),
		"Enter starts from the player view")
	camera.advance_presentation(1.0)
	check(camera.is_cinematic_shot() and is_equal_approx(camera.size, 6.0),
		"Enter ends at the authored pose and size")
	source.global_position += Vector3(3, 0, 0)
	source.size = 14.0
	camera.advance_presentation(1.0)
	check(camera.global_transform.is_equal_approx(shot.global_transform), "Hold uses the authored pose")
	camera.advance_presentation(1.0)
	check(source.is_current() and source.get_viewport().get_camera_3d() == source,
		"Return restores the latest player camera")
	print("CINEMATIC CAMERA: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1
```

- [ ] **Step 2: 运行并确认失败**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_camera_test.gd
```

Expected: FAIL with a missing `start_cinematic_shot` method.

- [ ] **Step 3: 添加通用 Shot 执行分支**

Keep legacy `_presentation_focus` fields and methods. Add:

```gdscript
var _cinematic_mode := false
var _target_transform: Transform3D
var _enter_transform: Transform3D
var _return_transform: Transform3D
var _target_properties: Dictionary
var _shot_options: Dictionary
var _shake_position_noise: FastNoiseLite
var _shake_rotation_noise: FastNoiseLite
var _base_shot_transform: Transform3D

func start_cinematic_shot(source: Camera3D, snapshot: Dictionary, request_id: int) -> bool:
	if is_presenting() or not is_inside_tree() or not is_node_ready():
		return false
	if not _valid_camera(source) or source == self or get_viewport().get_camera_3d() != source:
		return false
	_source = source
	_start_view = source.get_global_transform_interpolated()
	_target_transform = snapshot.transform
	_target_properties = snapshot.duplicate(true)
	_shot_options = snapshot.duplicate(true)
	_request_id = request_id
	_move_seconds = maxf(0.0, float(snapshot.enter_seconds))
	_hold_seconds = maxf(0.0, float(snapshot.hold_seconds))
	_return_seconds = maxf(0.0, float(snapshot.return_seconds))
	_elapsed = 0.0
	_phase = Phase.MOVE
	_cinematic_mode = true
	_copy_view(source)
	global_transform = _start_view
	reset_physics_interpolation()
	_create_shake_noise(snapshot)
	make_current()
	return true

func is_cinematic_shot() -> bool:
	return _cinematic_mode and is_presenting()
```

In `advance_presentation`, route to `_advance_cinematic(delta)` when `_cinematic_mode`.

- [ ] **Step 4: 实现进入、停留、返回和抖动**

```gdscript
func _advance_cinematic(delta: float) -> void:
	var remaining := delta
	for transition in 3:
		var duration := _phase_duration()
		var step := minf(remaining, maxf(0.0, duration - _elapsed))
		_elapsed += step
		remaining -= step
		var progress := _elapsed / duration if duration > 0.0 else 1.0
		var weight := _easing_weight(progress)
		_sample_cinematic_pose(weight)
		global_transform = _base_shot_transform
		_apply_shake()
		_update_occlusion(step)
		if _elapsed < duration: return
		_elapsed = 0.0
		match _phase:
			Phase.MOVE: _phase = Phase.HOLD
			Phase.HOLD:
				_phase = Phase.RETURN
				_return_from = global_transform
				_capture_return_lens()
			Phase.RETURN:
				_finish(&"completed", true)
				return
```

`_easing_weight()` 按 `transition_easing` 将线性进度转换为对应曲线。
`_sample_cinematic_pose()` 按当前 Phase 设置 `_base_shot_transform`：

- MOVE：玩家起始 Transform 到 Shot Transform；
- HOLD：固定 Shot Transform；
- RETURN：`_return_from` 到重新刷新后的玩家最新 Transform。

`_sample_cinematic_pose()` 同时插值 `size`、`fov`、`h_offset`、`v_offset` 和
`frustum_offset`；非数值属性在切入时复制。保留现有三阶段循环，不能使用只处理
一个 Phase 的单次权重函数，否则大 delta 会丢失 MOVE→HOLD→RETURN 的剩余时间。

`_apply_shake()`：

```gdscript
func _apply_shake() -> void:
	if not bool(_shot_options.get("shake_enabled", false)): return
	var amplitude := _shake_envelope()
	var phase := _elapsed * float(_shot_options.shake_frequency)
	var source_basis := _base_shot_transform.basis
	var local_position := Vector3(
		_shake_position_noise.get_noise_1d(phase),
		_shake_position_noise.get_noise_1d(phase + 31.0),
		_shake_position_noise.get_noise_1d(phase + 67.0))
	var local_rotation := Vector3(
		_shake_rotation_noise.get_noise_1d(phase + 13.0),
		_shake_rotation_noise.get_noise_1d(phase + 47.0),
		_shake_rotation_noise.get_noise_1d(phase + 89.0))
	global_transform.origin += source_basis * (local_position
		* _shot_options.shake_position_amplitude * amplitude)
	rotation_degrees += local_rotation * _shot_options.shake_rotation_degrees * amplitude
```

- [ ] **Step 5: 返回和清理**

In RETURN start, store current pose/lens in `_return_from`; after player camera refresh,
interpolate to the latest source pose and lens. In `_finish()`, clear `_cinematic_mode`,
noise objects, target dictionaries and all existing source/occlusion leases. Existing
`start_presentation()` continues to use the old path and existing tests.

- [ ] **Step 6: 运行定向测试**

Add `"cinematic_camera_test"` to `SYSTEM_TESTS`, then run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_camera_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/presentation_camera_test.gd
```

Expected: both scripts exit 0; old PresentationCamera behavior remains covered.

- [ ] **Step 7: 提交**

```bash
git add movement_demo/scripts/systems/presentation_camera.gd \
  movement_demo/tests/cinematic_camera_test.gd movement_demo/tests/run_regressions.py
git commit -m "feat: execute authored cinematic shots"
```

---

### Task 3: CinematicCameraController 与 SceneDirector 集成

**Files:**
- Create: `movement_demo/scripts/systems/cinematic/cinematic_camera_controller.gd`
- Create: `movement_demo/scenes/cinematic/cinematic_camera_controller.tscn`
- Modify: `movement_demo/scenes/world/scene_director.tscn`
- Modify: `movement_demo/scripts/world/enemy_wave_controller.gd`
- Modify: `movement_demo/scripts/systems/scene_director.gd`
- Modify: `movement_demo/scripts/systems/scene_pause_coordinator.gd`
- Create: `movement_demo/tests/cinematic_controller_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: `CinematicShot3D.runtime_snapshot()`、`PresentationCamera.start_cinematic_shot()`、`advance_presentation()`、`cancel_presentation()`、SceneDirector `request_action()`。
- Produces: `CinematicCameraController.bind_director(director: Node)`、`play_shot(shot: CinematicShot3D) -> Dictionary`、`execute_request(request: SceneRequest) -> Dictionary`、`cancel_shot(reason: StringName = &"manual") -> bool`、`advance(delta: float) -> void`、`pause_token() -> int`、`get_snapshot() -> Dictionary`；SceneDirector `complete_cinematic_request(id: int, result: StringName) -> void`。

- [ ] **Step 1: 写失败测试**

```gdscript
extends SceneTree

const ControllerScene = preload("res://scenes/cinematic/cinematic_camera_controller.tscn")
const ShotScene = preload("res://scenes/cinematic/cinematic_shot_3d.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var host := Node.new()
	host.name = "SceneDirector"
	root.add_child(host)
	var controller = ControllerScene.instantiate()
	host.add_child(controller)
	var shot: Camera3D = ShotScene.instantiate()
	shot.name = "DebugShot"
	host.add_child(shot)
	check(controller.get_snapshot().phase == &"idle", "Controller starts idle")
	var busy: Dictionary = controller.play_shot(shot)
	check(not busy.accepted and busy.result == &"no_director", "Standalone controller rejects without director")
	print("CINEMATIC CONTROLLER: 2/2 passed")
	quit()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
```

The first version must fail because the controller scene/script does not exist.

- [ ] **Step 2: 创建控制器场景与接口**

Scene:

```text
CinematicCameraController (Node, script)
└── PresentationCamera (presentation_camera.tscn)
```

Script skeleton:

```gdscript
class_name CinematicCameraController
extends Node

signal shot_started(request_id: int, shot: CinematicShot3D)
signal shot_phase_changed(request_id: int, phase: StringName)
signal shot_finished(request_id: int, result: StringName)

const Shot = preload("res://scripts/systems/cinematic/cinematic_shot_3d.gd")

var _director: Node
var _camera: Camera3D
var _shot: CinematicShot3D
var _request
var _phase: StringName = &"idle"
var _pause_token := 0
var _last_error: StringName

func bind_director(director: Node) -> void:
	_director = director

func play_shot(shot: CinematicShot3D) -> Dictionary:
	if _phase != &"idle":
		return _admission(&"busy")
	if not is_instance_valid(shot) or not is_instance_valid(_director):
		return _admission(&"no_director" if not is_instance_valid(_director) else &"invalid_shot")
	var error: StringName = shot.configuration_error()
	if not error.is_empty():
		return _admission(error)
	var request = _director.request_action(&"cinematic_shot", {
		"source": self, "target": shot, "origin": &"cinematic",
		"parameters": {"snapshot": shot.runtime_snapshot()},
	})
	if not request.has_started():
		return _admission(request.reason)
	return {"accepted": true, "request_id": request.id, "result": &"started", "reason": &""}

func get_snapshot() -> Dictionary:
	return {
		"phase": _phase, "shot": _shot, "request_id": _request.id if _request != null else 0,
		"pause_world": _shot.pause_world if is_instance_valid(_shot) else false,
		"last_error": _last_error,
	}

func pause_token() -> int:
	return _pause_token

func _admission(result: StringName, request_id: int = 0) -> Dictionary:
	return {
		"accepted": result == &"started",
		"request_id": request_id,
		"result": result,
		"reason": &"" if result == &"started" else result,
	}
```

- [ ] **Step 3: 将控制器接入 SceneDirector**

Add default child `CinematicCameraController` and `CinematicShots` to
`scenes/world/scene_director.tscn`. In `enemy_wave_controller.gd`:

```gdscript
@export_node_path("Node") var cinematic_controller_path: NodePath = ^"CinematicCameraController"

var cinematic_controller: Node:
	get: return get_node_or_null(cinematic_controller_path)
```

Pass `"cinematic_controller": cinematic_controller` in director `configure()`.
After creating the internal director core, call:

```gdscript
if cinematic_controller != null:
	cinematic_controller.bind_director(director)
```

In `scene_director.gd` add `_cinematic_controller` binding, `_cinematic_request`,
and accept `cinematic_shot` in `request_action()`. Mark it background so a dialogue
foreground request can coexist:

```gdscript
if kind == &"cinematic_shot":
	request._background = true
```

Add a `cinematic_shot` branch in `SceneDirector.execute_request()`:

```gdscript
&"cinematic_shot":
	execute_cinematic_shot_request(request)
```

Add:

```gdscript
func execute_cinematic_shot_request(request: Request) -> void:
	_cinematic_request = request
	var controller = _bindings.get("cinematic_controller")
	var result: Dictionary = controller.execute_request(request)
	if not result.accepted:
		_cinematic_request = null
		request.fail(result.reason)
```

Expose `CinematicCameraController.execute_request(request: SceneRequest) -> Dictionary`
that validates source camera, starts `PresentationCamera`, and links completion to
controller state. It reads `request.node(&"target")` and
`request.parameters.snapshot`. On finish:

```gdscript
_director.complete_cinematic_request(_request.id, result)
```

Add `SceneDirector.complete_cinematic_request(id, result)` that completes the matching
request and clears `_cinematic_request`.

```gdscript
func complete_cinematic_request(id: int, result: StringName) -> void:
	if _cinematic_request == null or _cinematic_request.id != id: return
	var request = _cinematic_request
	_cinematic_request = null
	if result == &"completed":
		request.complete({"cinematic_result": result})
	else:
		request.fail(String(result))
```

- [ ] **Step 4: 暂停、推进和取消**

Add `ScenePauseCoordinator.can_advance_cinematic(token)`:

```gdscript
func can_advance_cinematic(token: int) -> bool:
	if not _tokens.has(token) or not _tokens[token].pause or _previous_pause: return false
	for entry in _tokens.values():
		if entry.pause and entry.reason not in [&"cinematic_shot", &"dialogue"]:
			return false
	return true
```

Controller acquires `Pauses.for_tree(get_tree()).acquire(self, &"cinematic_shot", true, shot.pause_world)`
only when `pause_world` is true and stores the returned token in `_pause_token`.
SceneDirector calls `controller.advance(delta)` while active, before normal action
advancement, when not dead/loading and either the token is 0 or
`can_advance_cinematic(controller.pause_token())`. On death/load/reset/unload:

```gdscript
if cinematic_controller != null:
	cinematic_controller.cancel_shot(reason)
```

Block pause menu while controller is active:

```gdscript
if cinematic_controller != null and cinematic_controller.get_snapshot().phase != &"idle":
	return
```

- [ ] **Step 5: 忙与前台规则**

Before SceneDirector accepts dialogue/shop/interact/guide while a cinematic shot is
active, reject non-dialogue foreground requests:

```gdscript
if kind not in [&"cinematic_shot", &"dialogue"] \
		and _cinematic_controller != null \
		and _cinematic_controller.get_snapshot().phase != &"idle":
	request._settle(&"rejected", &"cinematic_busy")
	return request
```

Before accepting `cinematic_shot`, reject when foreground scheduler owns a kind other
than dialogue. Add `foreground_kind()` to `scene_request_scheduler.gd`.

- [ ] **Step 6: 运行控制器、场景与暂停测试**

Add real director fixtures to `cinematic_controller_test.gd` covering:

- accepted shot creates one current PresentationCamera;
- second request returns `busy`;
- `pause_world` token is acquired and released;
- dialogue request remains paused when shot completes;
- death/load/reset/unload cancel clears request and camera ownership;
- pause menu cannot open during shot.

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_controller_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/scene_director_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/pause_menu_test.gd
```

Expected: all exit 0 and controller snapshots return to `idle`.

- [ ] **Step 7: 提交**

```bash
git add movement_demo/scripts/systems/cinematic/cinematic_camera_controller.gd \
  movement_demo/scenes/cinematic/cinematic_camera_controller.tscn \
  movement_demo/scenes/world/scene_director.tscn \
  movement_demo/scripts/world/enemy_wave_controller.gd \
  movement_demo/scripts/systems/scene_director.gd \
  movement_demo/scripts/systems/scene_pause_coordinator.gd \
  movement_demo/tests/cinematic_controller_test.gd movement_demo/tests/run_regressions.py
git commit -m "feat: integrate cinematic camera controller"
```

---

### Task 4: Wave 和 SceneFlowAction 触发 Shot

**Files:**
- Modify: `movement_demo/scripts/world/enemy_wave_definition.gd`
- Modify: `movement_demo/scripts/systems/scene_director.gd`
- Modify: `movement_demo/scripts/systems/scene_flow_action.gd`
- Modify: `movement_demo/scripts/systems/scene_flow_runner.gd`
- Create: `movement_demo/tests/cinematic_wave_trigger_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: Task 3 的 `CinematicCameraController.play_shot(shot) -> Dictionary`。
- Produces: Wave `cinematic_shot_path: NodePath`；SceneFlowAction `PLAY_CINEMATIC_SHOT`。

- [ ] **Step 1: 写失败测试**

Use the existing `scene_reinforcement_test.gd` fixture pattern:

```gdscript
func check_shot_waits_for_real_commit() -> void:
	reinforcement.set("cinematic_shot_path", ^"../../CinematicShots/WaveShot")
	var before: Dictionary = controller.get_snapshot()
	host.request_wave(reinforcement)
	check(before.phase == &"idle" and controller.get_snapshot().phase == &"idle",
		"Shot does not start before a real deployment")
	await process_frame
	check(controller.get_snapshot().phase != &"idle",
		"Shot starts only after wave_committed")
```

Expected: FAIL because `cinematic_shot_path` is not exported and no controller request exists.

- [ ] **Step 2: 添加 Wave 字段与提交优先级**

In `enemy_wave_definition.gd`:

```gdscript
## 新式单镜头。真实部署成功后由 CinematicCameraController 执行。
## 与旧 Show Spawn Presentation 同时存在时，本次 Shot 优先，旧配置不重复播放。
@export_node_path("Node") var cinematic_shot_path: NodePath
```

Show this field in the Wave “出场镜头” group. `_get_configuration_warnings()` checks
that the target exists and is `CinematicShot3D` when non-empty.

In `SceneDirector._present_committed_wave()`:

```gdscript
var shot_path: NodePath = wave.get("cinematic_shot_path") if wave.get("cinematic_shot_path") != null else NodePath()
if not shot_path.is_empty():
	var shot := wave.get_node_or_null(shot_path)
	var controller = _bindings.get("cinematic_controller")
	if controller != null and shot is CinematicShot3D:
		var admission: Dictionary = controller.play_shot(shot)
		if not admission.accepted and admission.result != &"busy":
			report_action_error("camera", "Cinematic shot rejected: %s" % admission.reason)
		return
	report_action_error("camera", "Cinematic shot path is missing or invalid; falling back to legacy presentation")
```

Only fall back to legacy presentation when no new path is supplied.

- [ ] **Step 3: 添加 SceneFlowAction 类型**

Append at the end of `SceneFlowAction.Kind` to preserve old numeric values:

```gdscript
## 播放 Target Path 指定的 CinematicShot3D；完成后继续。
PLAY_CINEMATIC_SHOT
```

`_validate_property()` shows only `target_path` for this kind.

In `scene_flow_runner.gd`:

```gdscript
Action.Kind.PLAY_CINEMATIC_SHOT:
	_submit(entry, &"cinematic_shot", target, {})
```

`entry.request` waits until the shot request completes. A busy/rejected request
uses existing action failure handling.

- [ ] **Step 4: 运行 Wave 与流程测试**

Add `"cinematic_wave_trigger_test"` to `SYSTEM_TESTS`; run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_wave_trigger_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/scene_reinforcement_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/scene_director_test.gd
```

Expected: new Shot waits for commit, old presentation fields remain compatible,
and busy does not roll back deployed enemies.

- [ ] **Step 5: 提交**

```bash
git add movement_demo/scripts/world/enemy_wave_definition.gd \
  movement_demo/scripts/systems/scene_director.gd \
  movement_demo/scripts/systems/scene_flow_action.gd \
  movement_demo/scripts/systems/scene_flow_runner.gd \
  movement_demo/tests/cinematic_wave_trigger_test.gd movement_demo/tests/run_regressions.py
git commit -m "feat: trigger cinematic shots from waves and scene flows"
```

---

### Task 5: CinematicCameraDebug 调试面板

**Files:**
- Create: `movement_demo/scripts/debug/cinematic_camera_debug.gd`
- Create: `movement_demo/scenes/debug/cinematic_camera_debug.tscn`
- Modify: `movement_demo/scripts/debug/debug_settings.gd`
- Create: `movement_demo/tests/cinematic_debug_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: `CinematicCameraController.play_shot()`、`cancel_shot()`、`get_snapshot()`；`cinematic_shot` 节点组。
- Produces: Debug 总开关控制的 CanvasLayer 面板。

- [ ] **Step 1: 写失败测试**

```gdscript
extends SceneTree

const DebugScene = preload("res://scenes/debug/cinematic_camera_debug.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var host := Node.new()
	root.add_child(host)
	var shot := Camera3D.new()
	shot.set_script(load("res://scripts/systems/cinematic/cinematic_shot_3d.gd"))
	shot.add_to_group(&"cinematic_shot")
	host.add_child(shot)
	var panel = DebugScene.instantiate()
	host.add_child(panel)
	panel.refresh()
	check(panel.shot_names() == ["Camera3D"], "Debug panel lists scene shots")
	check(panel.current_status() == "idle", "Debug panel shows idle")
	quit()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
```

Expected: FAIL because the debug scene/script does not exist.

- [ ] **Step 2: 实现只读调试面板**

Scene structure:

```text
CinematicCameraDebug (CanvasLayer)
└── Panel
    └── Content
        ├── Title
        ├── ShotList (OptionButton)
        ├── Status (Label)
        ├── Play (Button)
        └── Cancel (Button)
```

The script exposes testable helpers:

```gdscript
func refresh() -> void
func shot_names() -> PackedStringArray
func current_status() -> String
```

`refresh()` enumerates nodes in `cinematic_shot`, sorted by `get_path()`.
Play and Cancel only call controller public methods. No direct camera writes.

- [ ] **Step 3: 接入 DebugSettings**

In `debug_settings.gd`, alongside `CoordinatorPaths`, instantiate the debug scene
only for debug builds and enable/disable it through the existing `changed` signal.
Debug off clears list/status but does not create a controller or pause.

- [ ] **Step 4: 运行测试**

Add `"cinematic_debug_test"` to `SYSTEM_TESTS`; run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_debug_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/debug_mode_test.gd
```

Expected: panel lists only local shots, play/cancel delegates, and disabling Debug
releases UI state without affecting camera ownership.

- [ ] **Step 5: 提交**

```bash
git add movement_demo/scripts/debug/cinematic_camera_debug.gd \
  movement_demo/scenes/debug/cinematic_camera_debug.tscn \
  movement_demo/scripts/debug/debug_settings.gd \
  movement_demo/tests/cinematic_debug_test.gd movement_demo/tests/run_regressions.py
git commit -m "feat: add cinematic camera debug panel"
```

---

### Task 6: 特殊打断矩阵、真实渲染和文档收尾

**Files:**
- Create: `movement_demo/tests/cinematic_interruption_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`
- Modify: `README.md`
- Modify: `docs/gameplay/CAMERA.md`
- Modify: `docs/gameplay/SCENE_DIRECTOR.md`
- Modify: `docs/gameplay/ENEMY_WAVES.md`
- Modify: `docs/project-layout.md`
- Modify: `docs/TODO.md`
- Modify: `docs/testing.md`

**Interfaces:**
- Consumes: completed Tasks 1–5.
- Produces: 可重复的特殊打断验收、真实渲染截图检查和完整维护文档。

- [ ] **Step 1: 写完整打断测试**

Create one test case per spec matrix row. Use one harness with counters:

```gdscript
func _assert_clean(label: String) -> void:
	var snapshot: Dictionary = controller.get_snapshot()
	check(snapshot.phase == &"idle", label + ": controller idle")
	check(source.is_current(), label + ": player camera restored")
	check(Pause.for_tree(self).snapshot().count == 0, label + ": no pause token leaked")
	check(not world.paused, label + ": world unpaused")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, label + ": mouse restored")
```

Required cases:

```text
death_during_enter
death_during_hold
death_during_return
scene_load_cancel
region_reset_cancel
controller_unload_cancel
source_camera_removed
source_camera_not_current
shot_removed_during_play
second_shot_busy
debug_cancel
dialogue_and_shot_coexist
dialogue_ends_first
shot_ends_first
no_pause_death_cancel
failed_spawn_has_no_shot
two_waves_same_frame_busy
no_source_camera
external_camera_takeover
pause_menu_blocked
return_source_lost
```

Each case must assert the expected result, not only the clean state. For example:

```gdscript
check(result == &"cancelled", "death returns cancelled")
check(not shot.global_transform.is_equal_approx(source.global_transform),
	"cancelled shot leaves no shake offset on the source camera")
```

- [ ] **Step 2: 添加上升式真实渲染检查**

Add a `--capture` branch to the interruption test:

- one free camera pose;
- one orthographic zoom;
- one deterministic shake midpoint;
- one returned player view.

Save screenshots under `res://logs/cinematic-camera-capture/`. Do not commit them.

- [ ] **Step 3: 运行完整定向回归**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_shot_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_camera_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_controller_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_wave_trigger_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_debug_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/cinematic_interruption_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/presentation_camera_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/scene_reinforcement_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/scene_director_test.gd
python3 movement_demo/tests/run_regressions.py --check
```

Then run the interruption/camera test with a real renderer and `-- --capture`.

- [ ] **Step 4: 更新文档**

- README: add cinematic camera row and configuration entry.
- CAMERA: document shot fields, phases, shake, player-camera boundary, debug panel.
- SCENE_DIRECTOR: document controller child hierarchy and `PLAY_CINEMATIC_SHOT`.
- ENEMY_WAVES: document `Cinematic Shot Path` and legacy fallback priority.
- project-layout: document controller, Shot, executor and tests.
- TODO: mark implemented scope and leave multi-shot timeline out.
- testing: record exact final counts, expected diagnostics and rendered screenshots.

- [ ] **Step 5: 最终验证与提交**

```bash
git diff --check
python3 movement_demo/tests/run_regressions.py --check
git status --short
```

Commit only source, tests, UID sidecars and documentation:

```bash
git add movement_demo docs README.md
git commit -m "test: cover cinematic camera interruptions"
```

Do not add `logs/`, `.textClipping`, or unrelated generated UID files.

---

## Self-Review

- Spec coverage:
  - Shot pose/zoom/shake: Tasks 1–2.
  - Controller hierarchy/API/busy: Task 3.
  - SceneDirector pause/dialogue/cancel: Task 3.
  - Wave and SceneFlowAction triggers: Task 4.
  - Debug panel: Task 5.
  - All documented interruption cases: Task 6.
  - Compatibility, docs and real rendering: Tasks 2, 4, 6.
- Signature consistency:
  - `play_shot(shot) -> Dictionary` is used by controller, Wave and debug tasks.
  - `start_cinematic_shot(source, snapshot, request_id) -> bool` is used by controller and camera tests.
  - `runtime_snapshot()` is the sole Shot-to-camera data contract.
- Scope remains one Shot only. No queue, timeline or multi-shot sequence is introduced.
