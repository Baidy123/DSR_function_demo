extends SceneTree

const Visual = preload("res://scripts/systems/presentation/visual_presentation.gd")
const State = preload("res://scripts/systems/presentation/presentation_state.gd")
const Fixture = preload("res://tests/presentation_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var host := Node3D.new()
	var placeholder := MeshInstance3D.new()
	placeholder.name = "Body"
	placeholder.mesh = CapsuleMesh.new()
	host.add_child(placeholder)
	var view := Visual.new()
	view.placeholder_paths.assign([^"../Body"])
	view.model_scene = Fixture.model_scene()
	view.animation_profile = Fixture.profile()
	host.add_child(view)
	root.add_child(host)
	view.set_process(false)
	var state := State.new()
	state.crouch_amount = 0.4
	state.posture_transition = &"crouch_enter"
	view.apply_state(state)
	check(view._clip == &"CrouchEnter" and is_equal_approx(view.player.current_animation_position, 0.4), "crouch entry follows actual body progress")
	check(is_equal_approx(_height(view), lerpf(1.75, 1.0, 0.4)), "configured transition changes only the external model to the corresponding height")
	view._process(0.3)
	view.apply_state(state)
	check(is_equal_approx(view.player.current_animation_position, 0.4), "blocked body progress cannot be advanced by animation time")
	state.posture_transition = &"crouch_exit"
	view.apply_state(state)
	check(view._clip == &"CrouchExit" and is_equal_approx(view.player.current_animation_position, 0.6), "reversing to standing maps the remaining actual crouch amount")
	check(is_equal_approx(_height(view), lerpf(1.75, 1.0, 0.4)), "reversing posture does not jump the model to standing")
	state.posture_transition = &""
	state.crouch_amount = 1.0
	state.aiming = true
	view.apply_state(state)
	check(view._clip == &"CrouchAim" and is_equal_approx(_height(view), 1.0), "ordinary crouched aiming keeps the visible low pose")
	state.local_velocity = Vector3(0.75, 0.0, 0.0)
	view.apply_state(state)
	view._process(0.2)
	check(view._clip == &"CrouchWalk" and is_equal_approx(view.player.current_animation_position, 0.1), "crouch walking uses its own configured reference speed")
	state.local_velocity = Vector3.ZERO
	state.reloading = true
	state.reload_progress = 0.37
	view.apply_state(state)
	check(view._clip == &"CrouchReload" and is_equal_approx(view.player.current_animation_position, 0.37), "crouched reload selects its own clip at real ammo progress")
	check(view.model.visible and not placeholder.visible and is_equal_approx(_height(view), 1.0), "crouched reload cannot display the standing reload pose")
	view.play_event(&"hit")
	view._process(0.3)
	check(view.current_state == &"crouch_reload" and is_equal_approx(view.player.current_animation_position, 0.37), "hit and elapsed animation time do not interrupt or advance real reload")
	paused = true
	view._process(0.5)
	paused = false
	check(is_equal_approx(view.player.current_animation_position, 0.37), "paused reload presentation remains frozen")
	view.animation_profile.crouch_reload = &"Missing"
	view.apply_state(state)
	check(view._clip == &"Crouch" and is_equal_approx(_height(view), 1.0), "missing crouched reload keeps crouch instead of the available standing Reload")
	view.animation_profile.crouch = &""
	view.apply_state(state)
	check(not view.model.visible and placeholder.visible, "no safe crouch reload artwork returns to the body placeholder")
	view.animation_profile = Fixture.profile()
	state.reloading = false
	view.apply_state(state)
	view.play_event(&"fire")
	check(view._clip == &"CrouchShoot" and is_equal_approx(_height(view), 1.0), "a real fire event uses the crouched shot mapping")
	view._process(0.2)
	view.play_event(&"fire")
	check(is_zero_approx(view.player.current_animation_position), "each repeated fire event restarts the crouched shot")
	view.play_event(&"hit")
	check(view._clip == &"CrouchHit", "crouched damage can use a dedicated reaction")
	view._process(1.1)
	check(view.current_state == &"crouch_aim", "one-shot completion returns to the current crouched aim")
	view.animation_profile.crouch_fire = &""
	view.animation_profile.crouch_hit = &""
	view.play_event(&"fire")
	view.play_event(&"hit")
	check(view._clip == &"CrouchAim", "missing crouched events skip their available standing equivalents")
	state.crouch_amount = 0.0
	state.aiming = false
	view.apply_state(state)
	view.play_event(&"fire")
	check(view._clip == &"Shoot", "existing standing fire mapping remains compatible")
	state.crouch_amount = 1.0
	view.apply_state(state)
	check(view._clip == &"Crouch" and view._event.is_empty(), "entering crouch clears an incompatible standing shot still playing")
	view.animation_profile = Fixture.profile()
	for event in [&"fire", &"hit", &"land"]:
		state.crouch_amount = 1.0
		state.posture_transition = &""
		view.apply_state(state)
		view.play_event(event)
		check(not view._event.is_empty(), "crouched %s starts before a posture transition" % event)
		state.crouch_amount = 0.8
		state.posture_transition = &"crouch_exit"
		view.apply_state(state)
		check(view._event.is_empty() and view._clip == &"CrouchExit" and is_equal_approx(_height(view), 1.15), "actual rising immediately supersedes crouched %s" % event)
		view.play_event(event)
		check(view._clip == &"CrouchExit" and is_equal_approx(view.player.current_animation_position, 0.2), "new %s cannot override the active body transition" % event)
	state.posture_transition = &""
	state.crouch_amount = 1.0
	state.vaulting = true
	state.vault_progress = 0.42
	state.reloading = true
	view.apply_state(state)
	check(view._clip == &"Vault" and is_equal_approx(view.player.current_animation_position, 0.42), "normal vault follows body progress and takes priority over stale reload state")
	state.vault_falling = true
	view.apply_state(state)
	view._process(0.2)
	check(view._clip == &"VaultFall" and is_equal_approx(view.player.current_animation_position, 0.2), "interrupted vault plays falling artwork instead of freezing the old vault frame")
	view.animation_profile.vault_fall = &""
	view.apply_state(state)
	check(not view.model.visible and placeholder.visible and view._clip.is_empty(), "missing falling clip keeps the real capsule instead of pretending to complete the vault")
	view.animation_profile = Fixture.profile()
	state.vaulting = false
	state.vault_falling = false
	state.reloading = false
	view.apply_state(state)
	view.play_event(&"land")
	check(view._clip == &"CrouchLand", "real landing at crouch height uses the optional crouched landing")
	view._process(1.1)
	check(view.current_state == &"crouch", "landing is presentation-only and returns to the current pose")
	state.crouch_amount = 0.0
	view.apply_state(state)
	view.play_event(&"land")
	check(view._clip == &"Land", "standing landing has an independent optional mapping")
	state.melee_active = true
	state.melee_progress = 0.6
	view.apply_state(state)
	check(view._clip == &"Melee" and is_equal_approx(view.player.current_animation_position, 0.6), "new pose clips do not change the existing melee progress protocol")
	state.dead = true
	view.apply_state(state)
	check(view._clip == &"Death", "death still overrides melee and landing presentation")
	view.reset_presentation()
	check(view._event.is_empty() and view.current_state == &"idle" and is_equal_approx(_height(view), 1.75), "reset clears events and restores original model dimensions")
	state = State.new()
	state.weapon = WeaponData.new()
	state.weapon_mount_position = Vector3(0.0, 1.3, 0.0)
	view.apply_state(state)
	check(view._weapon_view != null and view._weapon_view.using_placeholder, "equipped weapon without artwork is displayed through the existing shared backend")
	var socket: Node3D = view.model.get_node("WeaponSocket")
	check(view._weapon_view.global_transform.is_equal_approx(socket.global_transform), "weapon follows the external character's configured socket")
	state.dead = true
	socket.hide()
	view.apply_state(state)
	check(view._weapon_view.model == null, "a hidden hand socket cannot leave a floating fallback weapon after death")
	state.dead = false
	socket.show()
	view.reset_presentation()
	state.crouch_amount = 1.0
	state.weapon_mount_position.y = 0.72
	view.animation_profile.crouch = &""
	view.apply_state(state)
	check(placeholder.visible and view._weapon_view.position.is_equal_approx(state.weapon_mount_position + view.weapon_mount_offset), "missing character pose detaches the weapon to the actual low body mount")
	view.show_weapon = false
	view.apply_state(state)
	check(view._weapon_view.model == null and state.weapon != null, "disabling duplicate weapon artwork does not unequip the actual weapon")
	view.show_weapon = true
	view.model_scene = null
	view.rebuild_model()
	view.apply_state(state)
	check(not view.has_model() and placeholder.visible and view._weapon_view.model != null, "capsule characters display the weapon without needing character artwork")
	state.dead = true
	view.apply_state(state)
	check(view._weapon_view.model == null and state.weapon != null, "death without a hand socket hides floating artwork without changing equipment")
	state.dead = false
	view.reset_presentation()
	view.apply_state(state)
	check(view._weapon_view.model != null, "restoring a living capsule restores its equipped weapon appearance")
	state.weapon = null
	view.apply_state(state)
	check(view._weapon_view.model == null, "the backend clears weapon artwork when equipment becomes empty")
	var profile := Fixture.profile()
	var path := "res://logs/posture_animation_profile_saved.tres"
	check(ResourceSaver.save(profile, path) == OK, "extended optional animation profile remains serializable")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PresentationAnimationProfile
	check(loaded != null and loaded.crouch_enter == profile.crouch_enter and loaded.crouch_reload == profile.crouch_reload and loaded.vault_fall == profile.vault_fall and loaded.crouch_land == profile.crouch_land, "new clips survive resource save and reload")
	host.queue_free()
	await process_frame
	await _test_default_blend_progress()
	print("POSTURE ANIMATION PROFILE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _test_default_blend_progress() -> void:
	# Fixture.profile deliberately disables blending for the older mapping checks.
	# A newly created user profile keeps its real default crossfade instead.
	var profile := PresentationAnimationProfile.new()
	profile.idle = &"Idle"
	profile.move = &"Walk"
	profile.crouch_enter = &"CrouchEnter"
	profile.crouch_exit = &"CrouchExit"
	profile.crouch_reload = &"CrouchReload"
	profile.reload = &"Reload"
	profile.melee = &"Melee"
	profile.vault = &"Vault"
	check(is_equal_approx(profile.blend_seconds, 0.1), "new user profile retains its default 0.1-second transition blend")
	var view := Visual.new()
	view.model_scene = Fixture.model_scene()
	view.animation_profile = profile
	root.add_child(view)
	view.set_process(false)
	var torso: MeshInstance3D = view.model.get_node("Torso")
	var arm: MeshInstance3D = view.model.get_node("Arm")
	var state := State.new()
	view.apply_state(state)
	view._process(0.2)
	state.crouch_amount = 0.4
	state.posture_transition = &"crouch_enter"
	view.apply_state(state)
	check(view._clip == &"CrouchEnter" and is_equal_approx(_height(view), 1.45)
		and torso.position.is_equal_approx(Vector3(0, 0.725, 0))
		and arm.position.is_equal_approx(Vector3(0.35, 0.955, -0.12)),
		"default blend cannot leave enter progress at the previous standing mesh and arm pose")
	var blocked_torso := torso.transform
	var blocked_arm := arm.transform
	view._process(0.3)
	view.apply_state(state)
	check(is_equal_approx(_height(view), 1.45) and torso.transform.is_equal_approx(blocked_torso)
		and arm.transform.is_equal_approx(blocked_arm),
		"blocked entry keeps actual geometry frozen despite elapsed animation time")
	state.posture_transition = &"crouch_exit"
	view.apply_state(state)
	check(view._clip == &"CrouchExit" and is_equal_approx(_height(view), 1.45)
		and torso.position.is_equal_approx(Vector3(0, 0.725, 0))
		and arm.position.is_equal_approx(Vector3(0.35, 0.955, -0.12)),
		"default blend preserves actual height and arm placement when enter reverses to exit")
	paused = true
	view._process(0.5)
	paused = false
	check(is_equal_approx(_height(view), 1.45) and torso.transform.is_equal_approx(blocked_torso)
		and arm.transform.is_equal_approx(blocked_arm),
		"paused reversed posture cannot advance its geometry or finish a pending blend")
	state.posture_transition = &""
	state.crouch_amount = 1.0
	state.reloading = true
	state.reload_progress = 0.37
	view.apply_state(state)
	# Fixture CrouchReload reaches (0.9, 0, 0.35) at t=0.5.
	check(view._clip == &"CrouchReload" and is_equal_approx(_height(view), 1.0)
		and torso.position.is_equal_approx(Vector3(0, 0.5, 0))
		and arm.rotation.is_equal_approx(Vector3(0.666, 0, 0.259)),
		"default blend applies crouched reload geometry at the real ammo progress immediately")
	var reload_arm := arm.transform
	view._process(0.4)
	check(is_equal_approx(_height(view), 1.0) and arm.transform.is_equal_approx(reload_arm),
		"elapsed time does not advance the actual crouched reload arm pose")
	paused = true
	view._process(0.5)
	paused = false
	check(is_equal_approx(_height(view), 1.0) and arm.transform.is_equal_approx(reload_arm),
		"paused reload retains actual crouch geometry with the default blend setting")
	state.crouch_amount = 0.0
	view.apply_state(state)
	# Standing Reload reaches rotation.x=0.32 at t=0.5.
	check(view._clip == &"Reload" and is_equal_approx(_height(view), 1.75)
		and torso.position.is_equal_approx(Vector3(0.0296, 0.9046, 0))
		and arm.rotation.is_equal_approx(Vector3(0.2368, 0, 0)),
		"standing reload seeks real torso and arm tracks without retaining its previous crouched pose")
	var standing_reload_arm := arm.transform
	view._process(0.2)
	check(is_equal_approx(_height(view), 1.75) and arm.transform.is_equal_approx(standing_reload_arm),
		"standing reload geometry remains controlled by ammo rather than elapsed blend time")
	state.reloading = false
	state.melee_active = true
	state.melee_progress = 0.162
	view.apply_state(state)
	# Halfway to the fixture's 0.324 contact key: y=-0.8 -> 0.9.
	check(view._clip == &"Melee" and is_equal_approx(_height(view), 1.75)
		and arm.rotation.is_equal_approx(Vector3(0, 0.05, -0.2)),
		"melee progress immediately evaluates the real swing track under default blending")
	var melee_arm := arm.transform
	view._process(0.2)
	check(arm.transform.is_equal_approx(melee_arm), "melee swing geometry cannot run ahead of the actual attack phase")
	state.melee_active = false
	state.vaulting = true
	state.crouch_amount = 1.0
	state.vault_progress = 0.25
	view.apply_state(state)
	check(view._clip == &"Vault" and is_equal_approx(_height(view), 1.0)
		and torso.rotation.is_equal_approx(Vector3(-0.15, 0, 0))
		and arm.rotation.is_equal_approx(Vector3(-0.4, 0, 0)),
		"vault progress immediately evaluates low body and arm tracks instead of the previous melee pose")
	var vault_torso := torso.transform
	var vault_arm := arm.transform
	view._process(0.2)
	check(is_equal_approx(_height(view), 1.0) and torso.transform.is_equal_approx(vault_torso)
		and arm.transform.is_equal_approx(vault_arm),
		"vault geometry remains frozen until the body supplies new trajectory progress")
	state.vaulting = false
	state.reloading = true
	view.apply_state(state)
	state.reloading = false
	state.crouch_amount = 0.0
	state.local_velocity = Vector3.FORWARD * profile.move_reference_speed
	view.apply_state(state)
	check(view._clip == &"Walk" and _height(view) < 1.75,
		"ordinary timed walk still starts with the configured blend from the previous low pose")
	view._process(0.025)
	view._process(0.025)
	check(_height(view) > 1.0 and _height(view) < 1.75
		and view.player.current_animation_position > 0.0,
		"ordinary timed clip both blends its real mesh and advances animation time")
	view._process(0.2)
	check(is_equal_approx(_height(view), 1.75) and view.player.current_animation_position > 0.05
		and arm.rotation.x > 0.0 and is_equal_approx(profile.blend_seconds, 0.1),
		"ordinary timed animation finishes blending and keeps moving without changing profile configuration")
	view.queue_free()
	await process_frame

func _height(view) -> float:
	return float(view.model.get_node("Torso").mesh.height)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
