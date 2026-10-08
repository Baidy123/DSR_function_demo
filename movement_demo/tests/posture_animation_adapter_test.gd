extends SceneTree

const STEP := 1.0 / 60.0
const LowCover = preload("res://scripts/world/low_cover_geometry.gd")
var checks := 0
var failures := 0
var scene: Node3D
var actor
var adapter
var spy: PresentationSpy
var player_case := false

class PresentationSpy extends Node3D:
	var backend: Node3D
	var latest: Dictionary = {}
	var events: Array[Dictionary] = []
	var resets := 0
	func apply_state(value) -> void:
		latest = {"amount": value.crouch_amount, "transition": value.posture_transition,
			"vaulting": value.vaulting, "progress": value.vault_progress,
			"falling": value.vault_falling, "dead": value.dead,
			"mount": value.weapon_mount_position}
		backend.apply_state(value)
	func play_event(event: StringName) -> void:
		var sample := latest.duplicate()
		sample["event"] = event
		events.append(sample)
		backend.play_event(event)
	func reset_presentation() -> void:
		resets += 1
		backend.reset_presentation()
	func land_count() -> int:
		var count := 0
		for event in events:
			if event.event == &"land": count += 1
		return count

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for use_player in [true, false]:
		player_case = use_player
		await _build_fixture()
		await _posture_changes()
		await _vault_lifecycle()
		await _death_and_reset()
		paused = false
		scene.queue_free()
		await process_frame
		await process_frame
	print("POSTURE ANIMATION ADAPTER: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _posture_changes() -> void:
	var standing: Dictionary = actor.get_posture_presentation_state()
	_check("real body starts standing on the floor", actor.is_on_floor() and standing.amount == 0.0 and standing.transition == &"")
	standing.amount = 0.7
	standing.vaulting = true
	_check("public snapshot is independent of body execution", actor.get_posture_presentation_state().amount == 0.0 and not actor.is_vaulting())
	actor.request_crouch(true)
	await _step(3)
	var entering: Dictionary = actor.get_posture_presentation_state()
	_check("actual crouch motion reaches the adapter as an enter transition", entering.amount > 0.0 and entering.amount < 1.0 and entering.transition == &"crouch_enter" and spy.latest.transition == &"crouch_enter" and is_equal_approx(spy.latest.amount, entering.amount))
	actor.request_crouch(false)
	await _step()
	var exiting: Dictionary = actor.get_posture_presentation_state()
	_check("reversal follows actual body motion", exiting.amount < entering.amount and exiting.transition == &"crouch_exit")
	var height: float = actor.get_body_height()
	var roof := _box(Vector3(2, 0.04, 2), actor.global_position + Vector3.UP * (height + 0.03))
	scene.add_child(roof)
	await _settle(2)
	await _step(3)
	var blocked: Dictionary = actor.get_posture_presentation_state()
	_check("blocked stand freezes transition direction and physical amount", is_equal_approx(blocked.amount, exiting.amount) and blocked.transition == &"crouch_exit" and is_equal_approx(spy.latest.amount, blocked.amount))
	actor.request_crouch(true)
	await _step()
	_check("shrinking away from the ceiling reverses only after real movement", actor.get_posture_presentation_state().amount > blocked.amount and spy.latest.transition == &"crouch_enter")
	roof.queue_free()
	await _settle(2)
	await _step(20)
	_check("finished crouch clears transition without changing its physical height", actor.is_crouching() and spy.latest.transition == &"" and is_equal_approx(actor.get_body_height(), 1.0))
	var visible_body: MeshInstance3D = actor.get_node("Visual/Body" if player_case else "Body")
	_check("empty animation assets keep the real crouched capsule visible", visible_body.visible and is_equal_approx(visible_body.mesh.height, actor.get_body_height()))
	_check("weapon fallback follows the actual crouched muzzle", spy.to_global(spy.latest.mount).is_equal_approx(actor.get_muzzle_position()))
	actor.request_crouch(false)
	await _step(20)
	_check("finished stand restores the neutral transition and muzzle", spy.latest.transition == &"" and is_zero_approx(spy.latest.amount) and spy.to_global(spy.latest.mount).is_equal_approx(actor.get_muzzle_position()))

func _vault_lifecycle() -> void:
	await _place_at_entry()
	var landed_before := spy.land_count()
	_check("real low wall accepts a collision-checked vault", _begin_vault())
	adapter._physics_process(STEP)
	_check("vault entry publishes active progress without a posture transition", spy.latest.vaulting and not spy.latest.falling and spy.latest.progress == 0.0 and spy.latest.transition == &"")
	await _step(7)
	var airborne: Dictionary = actor.get_posture_presentation_state()
	_check("airborne trajectory exposes actual progress and muzzle", airborne.vault_progress > 0.0 and airborne.vault_progress < 1.0 and actor.global_position.y > 0.1 and spy.to_global(spy.latest.mount).is_equal_approx(actor.get_muzzle_position()))
	paused = true
	await _settle(3)
	_check("world pause leaves body snapshot unchanged", actor.get_posture_presentation_state() == airborne and spy.land_count() == landed_before)
	paused = false
	actor.receive_melee_hit(0.0, actor.global_position + Vector3.LEFT, 0.0, 0.2)
	adapter._physics_process(STEP)
	_check("real hit interruption publishes falling without a false landing", spy.latest.vaulting and spy.latest.falling and is_equal_approx(spy.latest.progress, airborne.vault_progress) and spy.land_count() == landed_before)
	await _wait_for_landing()
	_check("interrupted vault emits one landing after the body really reaches ground", not actor.is_vaulting() and actor.is_on_floor() and actor.global_position.y < 0.02 and spy.land_count() == landed_before + 1)
	var landing: Dictionary = _last_land()
	_check("landing adapter synchronizes the released body before emitting the event", not landing.get("vaulting", true) and not landing.get("falling", true) and landing.get("progress", -1.0) == 0.0)
	await _step(8)
	_check("ordinary grounded frames do not repeat the landing", spy.land_count() == landed_before + 1)
	await _place_at_entry()
	landed_before = spy.land_count()
	_check("normal vault remains available after interruption", _begin_vault())
	await _wait_for_landing()
	_check("normal trajectory also emits exactly one real landing", not actor.is_vaulting() and actor.is_on_floor() and spy.land_count() == landed_before + 1)

func _death_and_reset() -> void:
	if not player_case:
		await _place_at_entry()
		_check("reset fixture starts a real vault", _begin_vault())
		await _step(7)
		var before := spy.land_count()
		actor.reset_target()
		adapter._physics_process(STEP)
		_check("direct reset clears state without manufacturing a landing", not actor.is_vaulting() and spy.latest.amount == 0.0 and spy.latest.transition == &"" and not spy.latest.falling and spy.land_count() == before and spy.resets > 0)
	await _place_at_entry()
	_check("death fixture starts a real vault", _begin_vault())
	await _step(7)
	var before_death := spy.land_count()
	actor.receive_hit(10000.0)
	adapter._physics_process(STEP)
	_check("death takes effect without emitting landing", spy.latest.dead and spy.land_count() == before_death)
	if player_case:
		_check("player death cancellation exposes no stale vault or transition", not actor.get_posture_presentation_state().vaulting and not actor.get_posture_presentation_state().vault_falling and actor.get_posture_presentation_state().transition == &"")
		paused = false
	else:
		await _wait_for_landing()
		_check("enemy death may physically settle but never plays a living landing", not actor.is_vaulting() and actor.global_position.y < 0.02 and spy.land_count() == before_death and spy.latest.dead)
		actor.reset_target()
		adapter._physics_process(STEP)
		_check("post-death reset restores an independent standing snapshot", not spy.latest.dead and not spy.latest.vaulting and spy.latest.amount == 0.0 and spy.latest.transition == &"" and spy.land_count() == before_death)

func _build_fixture() -> void:
	scene = Node3D.new()
	scene.name = "PostureAnimationFixture"
	if player_case:
		var donor = load("res://scenes/main.tscn").instantiate()
		actor = donor.get_node("Player")
		donor.remove_child(actor)
		donor.free()
		actor.posture_transition_seconds = 0.2
		actor.vault_duration = 0.8
		actor.crouch_height = 1.0
	else:
		actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		# This tests the real body/adapter boundary, without starting a tactical AI.
		actor.get_node("AI").free()
		actor.posture_seconds = 0.2
		actor.crouching_height = 1.0
	actor.position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	scene.add_child(_box(Vector3(20, 0.2, 20), Vector3(0, -0.1, 0)))
	var wall = load("res://scenes/world/low_cover.tscn").instantiate()
	wall.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.55, -1))
	wall.low_cover = true
	wall.vault_enabled = true
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 1.1, 0.6)
	wall.get_node("CollisionShape3D").shape = shape
	wall.get_node("CollisionShape3D").transform = Transform3D.IDENTITY
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	wall.get_node("Mesh").mesh = mesh
	wall.get_node("Mesh").transform = Transform3D.IDENTITY
	scene.add_child(wall)
	scene.add_child(actor)
	root.add_child(scene)
	current_scene = scene
	actor.set_physics_process(false)
	adapter = actor.get_node("PlayerPresentation" if player_case else "EnemyPresentation")
	adapter.set_physics_process(false)
	spy = PresentationSpy.new()
	spy.backend = adapter.presentation
	spy.backend.get_parent().add_child(spy)
	spy.transform = spy.backend.transform
	adapter.presentation = spy
	if player_case: actor.health.debug_invincible = false
	await _step(6)

func _begin_vault() -> bool:
	if player_case: return actor.request_vault(Vector3.FORWARD)
	return actor.begin_vault(LowCover.query_vault(actor, Vector3.FORWARD))

func _place_at_entry() -> void:
	actor.global_position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	actor.velocity = Vector3.ZERO
	actor.request_crouch(false)
	await _step(20)

func _wait_for_landing() -> void:
	for frame in 180:
		await _step()
		if not actor.is_vaulting(): break

func _step(count := 1) -> void:
	for frame in count:
		await physics_frame
		actor._physics_process(STEP)
		if not player_case and not actor.is_vaulting() and not actor.is_dead:
			actor.move_character(Vector3.ZERO, STEP)
		adapter._physics_process(STEP)

func _settle(count: int) -> void:
	for frame in count: await physics_frame

func _last_land() -> Dictionary:
	for index in range(spy.events.size() - 1, -1, -1):
		if spy.events[index].event == &"land": return spy.events[index]
	return {}

func _box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition: failures += 1
	print("PASS " if condition else "FAIL ", "player: " if player_case else "enemy: ", label)
