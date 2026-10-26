extends RefCounted

const Pickup = preload("res://scenes/world/objects/ammo_pickup.tscn")
const Placement = preload("res://scripts/world/ammo_drop_position.gd")
const MAX_UNCOLLECTED_PICKUPS := 2
var _region: WeakRef
var _members: Dictionary = {}
var _generation: int = 0
var _container: Node3D
var _rng := RandomNumberGenerator.new()
var _pending_spawns: int = 0

func bind(region: Node3D) -> void:
	_region = weakref(region)
	_rng.randomize()

func register_enemy(enemy: CharacterBody3D) -> void:
	var id := enemy.get_instance_id()
	if _members.has(id): return
	var death := _on_death.bind(id)
	var reset_life := _on_reset_life.bind(id)
	var leave := unregister_id.bind(id)
	_members[id] = {"ref": weakref(enemy), "death": death, "reset": reset_life, "leave": leave, "dead": false}
	enemy.died.connect(death)
	enemy.reset_completed.connect(reset_life)
	enemy.tree_exiting.connect(leave)

func unregister_id(id: int) -> void:
	if not _members.has(id): return
	var entry: Dictionary = _members[id]
	var enemy: Node = entry.ref.get_ref()
	if is_instance_valid(enemy):
		if enemy.died.is_connected(entry.death): enemy.died.disconnect(entry.death)
		if enemy.reset_completed.is_connected(entry.reset): enemy.reset_completed.disconnect(entry.reset)
		if enemy.tree_exiting.is_connected(entry.leave): enemy.tree_exiting.disconnect(entry.leave)
	_members.erase(id)

func _on_reset_life(id: int) -> void:
	if _members.has(id): _members[id].dead = false

## 拾取成功即释放名额，不等待 queue_free；延迟生成另占名额，防止同枪多人死亡超量。
func uncollected_count() -> int:
	var count := 0
	if is_instance_valid(_container):
		for pickup in _container.get_children():
			if pickup.is_available(): count += 1
	return count

## 不掷“是否掉落”的第二次概率；数量独立 RNG，比例相同时保留主槽先出现者。
static func choose(snapshot: Array[Dictionary]) -> Dictionary:
	var selected: Dictionary = {}
	for row in snapshot:
		var definition: AmmoDefinition = row.ammo
		if row.conflict or not definition.allow_random_drop or not definition.has_valid_drop_range(): continue
		if row.total * 2 >= row.capacity: continue
		if selected.is_empty() or row.total * selected.capacity < selected.total * row.capacity:
			selected = row
	return selected

func _on_death(id: int) -> void:
	if not _members.has(id) or _members[id].dead: return
	var enemy: CharacterBody3D = _members[id].ref.get_ref()
	if not is_instance_valid(enemy) or not enemy.is_inside_tree() or not enemy.is_dead: return
	_members[id].dead = true
	var region: Node3D = _region.get_ref()
	if not is_instance_valid(region) or not region.is_inside_tree() or region.get_tree().paused: return
	if uncollected_count() + _pending_spawns >= MAX_UNCOLLECTED_PICKUPS: return
	for player in region.players_inside:
		if not is_instance_valid(player) or not player.is_inside_tree() or player.is_dead() or player.is_in_dialogue: continue
		var equipment: Node = player.get_node_or_null("Equipment")
		if equipment == null or not equipment.has_method("ammo_snapshot"): continue
		var selected := choose(equipment.ammo_snapshot())
		if selected.is_empty(): return
		var definition: AmmoDefinition = selected.ammo.duplicate()
		var amount := _rng.randi_range(definition.drop_min_count, definition.drop_max_count)
		# 死亡同步冻结所有数据，下一帧不再读敌人、装备或资源的可变字段。
		_pending_spawns += 1
		_spawn.call_deferred(definition, amount, enemy.global_position, _generation)
		return

func _spawn(definition: AmmoDefinition, amount: int, origin: Vector3, generation: int) -> void:
	if generation != _generation: return
	_pending_spawns -= 1
	var region: Node3D = _region.get_ref() if _region != null else null
	if not is_instance_valid(region) or not region.is_inside_tree(): return
	var point := Placement.find_ground(region, origin)
	if not point.is_finite():
		push_warning("弹药掉落：死亡点附近无合法地面，已跳过本次生成。")
		return
	if not is_instance_valid(_container):
		_container = Node3D.new()
		_container.name = "AmmoDrops"
		region.add_child(_container, false, Node.INTERNAL_MODE_BACK)
	var pickup = Pickup.instantiate()
	pickup.configure(definition, amount)
	_container.add_child(pickup)
	pickup.global_position = point

## 区域复位取消尚未生成的包；波次清尸不调用这里，最后一名敌人的包仍能生成。
func reset() -> void:
	_generation += 1
	_pending_spawns = 0
	for entry in _members.values(): entry.dead = false
	if is_instance_valid(_container):
		# 先禁用，防止延迟释放前已排队的 area 信号领取旧包。
		for pickup in _container.get_children(): pickup.invalidate()
		_container.queue_free()
	_container = null

func release() -> void:
	reset()
	for id in _members.keys(): unregister_id(id)
	_region = null
