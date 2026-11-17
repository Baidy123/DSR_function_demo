extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")
const Pauses = preload("res://scripts/systems/scene_pause_coordinator.gd")
const UI = preload("res://scenes/ui/dialogue_ui.tscn")
const MAIN = preload("res://scenes/main.tscn")
var failures := 0
var checks := 0

class Player extends Node3D:
	var is_in_dialogue := false
	var is_facing_npc := false
	var turns := 0
	func set_dialogue_active(value: bool) -> void: is_in_dialogue = value
	func face_npc(_point: Vector3) -> void: turns += 1

class Health extends Node:
	signal died
	var is_dead := false
	func die() -> void:
		is_dead = true
		died.emit()

class SlowDialogue extends DialogueResource:
	signal release_line
	func get_next_dialogue_line(_cue: String = "", _states: Array = [], _mutation: DMConstants.MutationBehaviour = DMConstants.MutationBehaviour.Wait) -> DialogueLine:
		await release_line
		var line := DialogueLine.new()
		line.text = "late dialogue"
		return line

class EmptyDialogue extends DialogueResource:
	func get_next_dialogue_line(_cue: String = "", _states: Array = [], _mutation: DMConstants.MutationBehaviour = DMConstants.MutationBehaviour.Wait) -> DialogueLine:
		return null

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func fixture() -> Dictionary:
	var scene := Node.new()
	root.add_child(scene)
	var player := Player.new()
	scene.add_child(player)
	var health := Health.new()
	player.add_child(health)
	var ui = UI.instantiate()
	scene.add_child(ui)
	var source := Node3D.new()
	scene.add_child(source)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.make_current()
	var director = Director.new()
	director.configure(scene, {"health": health, "scene_root": scene})
	scene.add_child(director)
	director.initialize()
	return {"scene": scene, "player": player, "health": health, "ui": ui, "source": source, "director": director}

func dialogue(f: Dictionary, resource: DialogueResource):
	return f.director.request_action(&"dialogue", {"source": f.source, "target": f.ui, "player": f.player,
		"origin": &"interaction", "parameters": {"resource": resource, "start": "start"}})

func _run() -> void:
	var f := fixture()
	var slow := SlowDialogue.new()
	var request = dialogue(f, slow)
	check(request.has_started() and request.status == &"running", "director starts a valid dialogue before its first line arrives")
	if failures:
		f.scene.free()
		quit(1)
		return
	check(f.player.is_in_dialogue and f.ui.is_loading, "director holds player control during asynchronous opening")
	var camera = f.director.request_action(&"presentation", {"source": f.source, "target": f.source,
		"origin": &"rule", "parameters": {"move_seconds": 0.0, "hold_seconds": 0.0, "return_seconds": 0.0}})
	check(camera.status == &"queued", "reinforcement camera waits for dialogue to finish")
	var rejected = dialogue(f, EmptyDialogue.new())
	check(rejected.status == &"rejected" and f.player.turns == 0, "busy interaction cannot turn or relock the player")
	slow.release_line.emit()
	await process_frame
	check(f.ui.dialogue_panel.visible, "real dialogue UI displays the completed first line")
	f.ui._close_dialogue()
	check(request.status == &"completed" and not f.player.is_in_dialogue, "dialogue close returns control through its director request")
	for _frame in range(5): await process_frame
	check(camera.status == &"completed", "queued camera executes once after dialogue close")
	f.scene.free()
	await process_frame
	f = fixture()
	slow = SlowDialogue.new()
	request = dialogue(f, slow)
	f.health.die()
	check(request.status == &"cancelled" and not f.player.is_in_dialogue and paused, "death cancels an unannounced dialogue and keeps death pause")
	slow.release_line.emit()
	await process_frame
	check(not f.ui.dialogue_panel.visible, "late dialogue line cannot reopen cancelled UI")
	f.scene.free()
	await process_frame
	f = fixture()
	request = dialogue(f, EmptyDialogue.new())
	check(request.status == &"completed" and not f.player.is_in_dialogue, "empty synchronous dialogue ends without a missing completion signal")
	slow = SlowDialogue.new()
	request = dialogue(f, slow)
	f.source.queue_free()
	await process_frame
	check(request.status == &"cancelled" and not f.player.is_in_dialogue, "source exit cancels opening dialogue")
	slow.release_line.emit()
	f.scene.free()
	await process_frame
	f = fixture()
	slow = SlowDialogue.new()
	request = dialogue(f, slow)
	f.ui.queue_free()
	await process_frame
	check(request.status == &"cancelled" and not f.player.is_in_dialogue, "UI exit cancels its request and returns player control")
	slow.release_line.emit()
	f.scene.free()
	await process_frame
	await _pause_controls()
	await _shop_controls()
	print("Scene interactions: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _pause_controls() -> void:
	var owner := Node.new()
	root.add_child(owner)
	var pauses = Pauses.for_tree(self)
	var mouse: int = pauses.acquire(owner, &"mouse_only", true, false)
	check(not paused, "mouse-only lease does not freeze the world")
	var pause: int = pauses.acquire(owner, &"pause", false)
	check(paused, "pause lease freezes world alongside mouse-only lease")
	pauses.release(pause)
	check(not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "last pause releases independently of active mouse lease")
	pauses.release(mouse)
	paused = true
	pause = pauses.acquire(owner, &"external", true)
	pauses.release(pause)
	check(paused, "pre-existing external pause survives managed lease")
	paused = false
	owner.free()

func _shop_controls() -> void:
	var scene = MAIN.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var shop = scene.get_node("ShopController")
	var player = scene.get_node("Player")
	var catalog = shop.shop_catalog
	shop.shop_catalog = ShopCatalog.new()
	check(shop.open_shop_for_player(player) and not paused and scene.get_node("ShopBoard").visible, "empty shop is a foreground request without world pause")
	shop.close_shop()
	check(not scene.get_node("ShopBoard").visible and not paused, "empty shop close returns its foreground lease")
	shop.shop_catalog = catalog
	check(shop.open_shop_for_player(player) and paused, "normal shop opening acquires director pause")
	var npc = scene.get_node("NPC")
	var busy = npc.request_dialogue(player)
	check(busy.status == &"rejected" and npc.pending_player == null and not player.is_facing_npc and not player.is_in_dialogue,
		"real NPC busy rejection does not lock or turn player before approval")
	var owner := Node.new()
	scene.add_child(owner)
	var token: int = Pauses.for_tree(self).acquire(owner, &"external")
	shop.close_shop()
	check(paused and not scene.get_node("ShopBoard").visible, "shop close preserves external pause ownership")
	Pauses.for_tree(self).release(token)
	check(not paused, "last external pause can restore gameplay after shop closes")
	scene.free()
	current_scene = null
	await process_frame
