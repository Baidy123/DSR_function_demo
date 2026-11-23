extends SceneTree

const State = preload("res://scripts/systems/presentation/presentation_state.gd")
const Backend = preload("res://scripts/systems/presentation/visual_presentation.gd")
var failed := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var state = State.new()
	state.crouch_amount = 1.0
	check(state.base_state() == &"crouch", "蹲姿单独表现")
	state.local_velocity = Vector3.RIGHT
	check(state.base_state() == &"crouch_move", "蹲行保留低姿态")
	state.vaulting = true
	state.reloading = true
	check(state.base_state() == &"vault", "翻越表现优先于未清理换弹快照")
	state.dead = true
	check(state.base_state() == &"dead", "死亡表现优先")
	var actor := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = load("res://resources/models/crouch_capsule.tres")
	actor.add_child(body)
	var presentation := Node3D.new()
	presentation.set_script(Backend)
	var placeholders: Array[NodePath] = [NodePath("../Body")]
	presentation.placeholder_paths = placeholders
	actor.add_child(presentation)
	root.add_child(actor)
	presentation.model_scene = load("res://scenes/presentation/example_model.tscn")
	presentation.animation_profile = load("res://resources/animations/example_animation_profile.tres") if ResourceLoader.exists("res://resources/animations/example_animation_profile.tres") else null
	presentation.rebuild_model()
	check(not body.visible and presentation.has_model(), "站姿正常使用外部模型")
	state = State.new()
	state.crouch_amount = 1.0
	presentation.apply_state(state)
	check(body.visible and not presentation.model.visible, "缺少蹲姿clip时显示胶囊并隐藏站立外部模型")
	state.crouch_amount = 0.0
	presentation.apply_state(state)
	check(not body.visible and presentation.model.visible, "站起恢复外部模型")
	state.vaulting = true
	presentation.apply_state(state)
	check(body.visible and not presentation.model.visible, "缺少翻越clip时显示真实身体胶囊")
	presentation.reset_presentation()
	check(not body.visible and presentation.model.visible, "复位恢复站姿模型")
	actor.free()
	print("HALF COVER PRESENTATION: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)
