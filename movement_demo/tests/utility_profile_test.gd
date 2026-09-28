extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = scene.get_node("Arena").to_global(Vector3(0, 0, 2.5))
	await physics_frame
	await physics_frame
	ai.is_alerted = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	ai.has_visual_memory = true
	var started := Time.get_ticks_usec()
	var candidates: Array = ai.cover_selection.get_reload_cover_candidates(player.global_position + Vector3.UP * 0.8)
	print("PROFILE cover count=", candidates.size(), " ms=", (Time.get_ticks_usec() - started) / 1000.0)
	started = Time.get_ticks_usec()
	var attacks: Array = ai.cover_selection.get_attack_assessments(player.global_position + Vector3.UP * 0.8, player.global_position + Vector3.UP * 0.8)
	print("PROFILE attack count=", attacks.size(), " ms=", (Time.get_ticks_usec() - started) / 1000.0)
	for run in range(3):
		started = Time.get_ticks_usec()
		var options: Array = ai.action_selector.assess_options(ai, true)
		print("PROFILE assessment options=", options.size(), " ms=", (Time.get_ticks_usec() - started) / 1000.0)
	quit()
