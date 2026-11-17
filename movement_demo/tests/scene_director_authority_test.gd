extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")
const Region = preload("res://scripts/world/shooting_range.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const MAIN := "res://scenes/main.tscn"
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
const CAPTURE_DIR := "res://logs/director-authority-capture/"

class Guide extends Node:
	signal finished
	var cancelled := false
	func begin() -> void: pass
	func cancel() -> void: cancelled = true

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _settle(frames: int = 4) -> void:
	for _frame in range(frames): await process_frame

func _count_cores(node: Node) -> int:
	var count := 1 if node.get_script() == Director else 0
	for child in node.get_children(true): count += _count_cores(child)
	return count

func _run() -> void:
	await _missing_director()
	await _two_regions()
	for path in [MAIN, "res://scenes/world/levels/lvl_1.tscn", "res://scenes/world/levels/lvl_2.tscn",
			"res://scenes/world/levels/lvl_3.tscn", "res://scenes/world/levels/lvl_4.tscn", "res://scenes/world/levels/lvl_5.tscn"]:
		var scene = load(path).instantiate()
		root.add_child(scene)
		current_scene = scene
		await _settle()
		var director = Director.for_node(scene)
		check(director != null and _count_cores(scene) == 1, "authored scene has exactly one explicit director: " + path)
		check(director != null and Director.for_node(scene.get_node("Player/Health")) == director,
			"player resolves its own scene director: " + path)
		if path == MAIN: check(director.state == &"running", "tavern without waves or guide runs directly")
		else: check(director.state == &"guide" or director.state == &"running", "saved level guide binding is valid: " + path)
		scene.free()
		current_scene = null
		await _settle(2)
		check(not paused, "authored scene cleanup releases pause: " + path)
	if OS.get_cmdline_user_args().has("--capture"): await _run_capture()
	print("Scene director authority: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _missing_director() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var player = PlayerScene.instantiate()
	player.name = "Player"
	scene.add_child(player)
	player.set_physics_process(false)
	var region := Region.new()
	scene.add_child(region)
	await _settle()
	check(_count_cores(scene) == 0 and Director.for_node(region) == null,
		"missing explicit director must not cause a region to create a hidden authority")
	scene.free()
	await _settle(2)

func _two_regions() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var director = Director.new()
	director.configure(scene, {"scene_root": scene})
	scene.add_child(director)
	director.initialize()
	var a := Region.new()
	var b := Region.new()
	scene.add_child(a)
	scene.add_child(b)
	var guide := Guide.new()
	b.add_child(guide)
	await _settle()
	check(Director.for_node(a) == director and Director.for_node(b) == director and _count_cores(scene) == 1,
		"multiple regions share the explicit scene director")
	var request = director.request_action(&"guide", {"source": guide, "target": guide,
		"scope": 1, "scope_owner": b, "parameters": {"pause_world": false}})
	director.reset_region(a)
	check(request.is_current() and not guide.cancelled, "reset of region A preserves region B execution")
	director.reset_region(b)
	check(request.status == &"cancelled" and guide.cancelled, "reset of owning region cancels real execution")
	scene.free()
	await _settle(2)

func _run_capture() -> void:
	check(DisplayServer.get_name() != "headless", "capture requires a real rendering backend")
	if DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1280, 800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	var state := root.get_node("GameState")
	state.clear_interaction_state()
	state.completed_level = 0
	state.available_level = 1
	state.money = 700
	state.pending_player_state = {}
	state.level_entry_player_state = {}
	state.campaign_checkpoint = {}
	var scene = load(MAIN).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _settle(6)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var health = player.get_node("Health")
	health.debug_mode = false
	var ui = scene.get_node("DialogueUI")
	await ui.open_dialogue(player, load("res://resources/dialogue/wine_glass.dialogue"), "start")
	var director = Director.for_node(scene)
	var marker := Marker3D.new()
	scene.add_child(marker)
	marker.global_position = player.global_position + Vector3(4, 0, 0)
	var camera = director.request_action(&"presentation", {"source": ui, "target": marker, "origin": &"rule",
		"parameters": {"move_seconds": 0.25, "hold_seconds": 0.4, "return_seconds": 0.25}})
	check(ui.dialogue_panel.visible and camera.status == &"queued", "rendered dialogue queues the requested camera")
	await _capture_image("01-dialogue.png", director)
	ui._close_dialogue()
	for _frame in range(30):
		if camera.has_started(): break
		await process_frame
	check(camera.has_started() and not ui.dialogue_panel.visible and paused, "rendered camera starts after dialogue releases control")
	await _capture_image("02-camera.png", director)
	var camera_deadline := Time.get_ticks_msec() + 5000
	while not camera.is_terminal() and Time.get_ticks_msec() < camera_deadline:
		await process_frame
	check(camera.status == &"completed" and not paused, "rendered camera returns to the player and restores pause ownership")
	var shop = scene.get_node("ShopController")
	check(shop.open_shop_for_player(player), "rendered shop opens through director")
	await _capture_image("03-shop.png", director)
	await _click(scene.get_node("ShopBoard").close_button)
	check(not scene.get_node("ShopBoard").visible and not paused, "real GUI close button releases shop control")
	check(shop.open_shop_for_player(player), "rendered shop can reopen after close")
	health.receive_hit(health.max_health * 10.0)
	await _settle(2)
	check(health.is_dead and not scene.get_node("ShopBoard").visible and paused,
		"rendered death interrupts shop and retains only death control")
	await _capture_image("04-death.png", director)
	scene.free()
	current_scene = null
	await _settle(3)
	state.pending_player_state = {}
	scene = load("res://scenes/world/levels/lvl_1.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _settle(4)
	await _click(scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close"))
	check(not paused, "real guide close button enables level play")
	check(scene.get_node("SceneDirector").debug_complete_encounter(), "rendered level completion requests director approval")
	var portal = scene.get_node("TavernReturnPortal")
	for _frame in range(30):
		if portal.enabled: break
		await process_frame
	check(portal.enabled and portal.interact(scene.get_node("Player")), "rendered return portal starts approved transition")
	for _frame in range(90):
		if is_instance_valid(current_scene) and current_scene.scene_file_path == MAIN: break
		await process_frame
	check(is_instance_valid(current_scene) and current_scene.scene_file_path == MAIN and state.completed_level == 1,
		"rendered successful return commits completion and loads tavern")
	if is_instance_valid(current_scene):
		await _capture_image("05-returned-tavern.png", Director.for_node(current_scene))
		current_scene.free()
	current_scene = null
	await _settle(3)
	var report := FileAccess.open(CAPTURE_DIR + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"backend": DisplayServer.get_name(), "checks": checks, "failures": failures, "captures": captures}, "\t"))

func _capture_image(name: String, director: Node) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and image.save_png(CAPTURE_DIR + name) == OK, "render capture saved: " + name)
	captures.append({"file": name, "scene": director.debug_snapshot() if director != null else {}})

func _click(button: BaseButton) -> void:
	var count := [0]
	button.pressed.connect(func(): count[0] += 1, CONNECT_ONE_SHOT)
	var point := button.get_global_rect().get_center()
	Input.warp_mouse(point)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		root.push_input(event, true)
		await process_frame
	check(count[0] == 1, "real GUI click reached " + button.name)
