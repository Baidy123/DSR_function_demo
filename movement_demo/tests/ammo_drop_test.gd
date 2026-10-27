extends SceneTree

const Drops = preload("res://scripts/world/ammo_drop_controller.gd")
const Placement = preload("res://scripts/world/ammo_drop_position.gd")
const Region = preload("res://scripts/world/shooting_range.gd")
const Ammo = preload("res://scripts/weapons/weapon_ammo.gd")
const Player = preload("res://scenes/player/player.tscn")
const Enemy = preload("res://scenes/enemy/levels/lvl_1/melee.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	if "--render-proof" in OS.get_cmdline_user_args():
		await _render_foreground()
		print("AMMO FOREGROUND RENDER: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	if Engine.is_editor_hint():
		# 先让编辑器完成启动／扫描；初始化前退出会泄漏编辑器本身的控件与资源。
		for frame in range(120): await process_frame
		while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
		_configuration_roundtrip()
		for frame in range(5): await process_frame
		print("AMMO CONFIG EDITOR: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	root.get_node("DebugSettings").enabled = false
	_resources()
	_configuration_roundtrip()
	await _inventory()
	await _runtime()
	await _drop_limit()
	await _shooting_and_models()
	await _waves()
	print("AMMO DROPS: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _type(key: StringName = &"energy") -> AmmoDefinition:
	var definition := AmmoDefinition.new()
	definition.ammo_id = key
	definition.display_name = "Energy"
	definition.allow_random_drop = true
	definition.drop_min_count = 3
	definition.drop_max_count = 5
	return definition

func _gun(definition: AmmoDefinition, capacity: int = 12) -> WeaponData:
	var gun := WeaponData.new()
	gun.ammo_definition = definition
	gun.magazine_capacity = capacity
	return gun

func _resources() -> void:
	var gun := WeaponData.new()
	for kind in range(4):
		gun.ammo_type = kind
		var definition := gun.get_ammo_definition()
		check(definition == AmmoDefinition.legacy(kind) and definition.has_valid_id() and definition.allow_random_drop and definition.has_valid_drop_range(), "Legacy enum %d resolves a normal ammo resource" % kind)
		var model := definition.drop_model.instantiate()
		check(model is Node3D and model.get_node("Box").mesh is BoxMesh, "Legacy type has a colored box model")
		model.free()
	var fifth := _type()
	gun.ammo_definition = fifth
	check(gun.get_ammo_key() == &"energy", "Explicit fifth ammo type overrides legacy integer")
	var fresh := AmmoDefinition.new()
	check(not fresh.allow_random_drop and fresh.drop_min_count == 1 and fresh.drop_max_count == 1, "New advanced ammo opts out by default")
	gun.ammo_definition = fresh
	check(gun.get_ammo_definition() == null, "Invalid explicit resource never becomes legacy pistol")
	gun.ammo_definition = fifth
	var pool := {&"energy": 9}
	var state := Ammo.new(gun, pool)
	fifth.ammo_id = &"changed"
	state.magazine_rounds = 0
	state.start_reload()
	state.advance_reload(2)
	check(state.ammo_key == &"energy" and state.magazine_rounds == 9 and pool.energy == 0 and pool.size() == 1, "Hot edited ID cannot transform equipped ammo")
	fifth.ammo_id = &"energy"
	fifth.drop_model = AmmoDefinition.legacy(3).drop_model
	DirAccess.make_dir_recursive_absolute("res://logs/ammo_drop_test")
	var path := "res://logs/ammo_drop_test/fifth.tres"
	check(ResourceSaver.save(fifth, path) == OK, "Fifth type saves without enum or registry edits")
	var saved: AmmoDefinition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved.ammo_id == &"energy" and saved.drop_min_count == 3 and saved.drop_max_count == 5 and saved.drop_model.resource_path == fifth.drop_model.resource_path, "ID, range and model survive reload")
	check(fifth.same_definition(fifth.duplicate(true)), "Deep copied definitions with same model remain one ammo type")

func _configuration_roundtrip() -> void:
	DirAccess.make_dir_recursive_absolute("res://logs/ammo_drop_test")
	var header := '[gd_scene load_steps=4 format=3]\n[ext_resource type="PackedScene" path="res://scenes/player/player.tscn" id="1"]\n[ext_resource type="Script" path="res://scripts/weapons/ammo_supply.gd" id="2"]\n[ext_resource type="Resource" path="res://resources/ammo/types/pistol.tres" id="3"]\n[sub_resource type="Resource" id="zero"]\nscript = ExtResource("2")\nammo = ExtResource("3")\namount = 0\n[node name="Player" instance=ExtResource("1")]\n[node name="Equipment" parent="."]\n'
	for order in range(3):
		var legacy := 'starting_pistol_ammo = 23\nstarting_rifle_ammo = 11\n'
		var modern := 'initial_ammo = Array[ExtResource("2")]([SubResource("zero")])\n' if order < 2 else ''
		var path := "res://logs/ammo_drop_test/inherited%d.tscn" % order
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(header + (legacy + modern if order != 1 else modern + legacy))
		file.close()
		var packed: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var player = packed.instantiate()
		var equipment = player.get_node("Equipment")
		var values := {}
		for supply in equipment.initial_ammo: values[supply.ammo.ammo_id] = supply.amount
		check(values.rifle == 11 and values.pistol == (0 if order < 2 else 23), "Inherited legacy values and explicit zero respect both property load orders %d" % order)
		var properties: Array[Dictionary] = equipment.get_property_list()
		check(properties.filter(func(p): return p.name == "initial_ammo" and (p.usage & PROPERTY_USAGE_EDITOR) != 0).size() == 1 and properties.filter(func(p): return p.name == "starting_pistol_ammo" and (p.usage & PROPERTY_USAGE_EDITOR) != 0).is_empty(), "Inspector presents one editable supply list and hides legacy fields")
		player.free()
	var weapon := _gun(_type())
	check(weapon.get_property_list().filter(func(p): return p.name == "ammo_type" and (p.usage & PROPERTY_USAGE_EDITOR) != 0).is_empty(), "Explicit resource hides redundant legacy ammo selector")

func _inventory() -> void:
	var player = Player.instantiate()
	var equipment = player.get_node("Equipment")
	var inspector_values: Array[AmmoSupply] = equipment.initial_ammo
	inspector_values[0].amount = 17
	check(equipment.initial_ammo[0] == inspector_values[0] and equipment.initial_ammo[0].amount == 17, "Inspector edits stable supply resources instead of temporary objects")
	var undo := UndoRedo.new()
	undo.create_action("Initial ammo")
	undo.add_do_property(inspector_values[0], "amount", 21)
	undo.add_undo_property(inspector_values[0], "amount", 17)
	undo.commit_action()
	undo.undo()
	check(equipment.initial_ammo[0].amount == 17, "Native resource undo restores initial supply")
	undo.redo()
	check(equipment.initial_ammo[0].amount == 21, "Native resource redo preserves stable entry")
	undo.clear_history()
	undo.free()
	var first := _type()
	var second := _type(&"plasma")
	var gun := _gun(first)
	equipment.primary_weapon = gun
	equipment.secondary_weapon = gun
	equipment.starting_pistol_ammo = 7
	equipment.starting_rifle_ammo = 19
	var supplies: Array[AmmoSupply] = [AmmoSupply.create(AmmoDefinition.legacy(1), 0), AmmoSupply.create(first, 0)]
	equipment.initial_ammo = supplies
	var scene := PackedScene.new()
	check(scene.pack(player) == OK and ResourceSaver.save(scene, "res://logs/ammo_drop_test/player.tscn") == OK, "Equipment supply list saves in player scene")
	player.free()
	var reloaded: PackedScene = ResourceLoader.load("res://logs/ammo_drop_test/player.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
	player = reloaded.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	equipment = player.get_node("Equipment")
	var combat = player.get_node("Combat")
	check(equipment.reserve_ammo.pistol == 0 and equipment.reserve_ammo.rifle == 19 and equipment.reserve_ammo.energy == 0, "Explicit zero and unspecified legacy values survive reload")
	check(equipment.reserve_ammo.keys().all(func(key): return key is StringName), "Runtime pool uses StringName keys only")
	var snapshot: Array[Dictionary] = equipment.ammo_snapshot()
	check(snapshot.size() == 1 and snapshot[0].total == 24 and equipment._ammo_states[1] == null and equipment.active_slot == 0, "Pure query counts lazy stowed full magazine without equipping")
	combat.ammo.magazine_rounds = 0
	check(Drops.choose(equipment.ammo_snapshot()).is_empty(), "Stowed magazine prevents false low-ammo drop")
	equipment.select_slot(1)
	combat.ammo.magazine_rounds = 5
	check(equipment._ammo_states[0] != combat.ammo and Drops.choose(equipment.ammo_snapshot()).total == 5, "Same WeaponData has independent slot magazines")
	combat.ammo.magazine_rounds = 6
	check(Drops.choose(equipment.ammo_snapshot()).is_empty(), "Exactly half a magazine does not qualify")
	var rules: Array[Dictionary] = equipment.ammo_snapshot()
	rules[0].total = 0
	rules[0].capacity = 1
	rules[0].ammo.allow_random_drop = false
	check(Drops.choose(rules).is_empty(), "Disabled ammo never drops even at zero stock")
	rules[0].ammo.allow_random_drop = true
	rules[0].ammo.drop_min_count = 9
	rules[0].ammo.drop_max_count = 8
	check(Drops.choose(rules).is_empty(), "Invalid count range excludes type rather than swapping limits")
	rules[0].ammo.drop_max_count = 9
	check(Drops.choose(rules).ammo.drop_min_count == 9, "One-round gun can drop a fixed nine-round pack independent of magazine size")
	rules[0].total = 1
	check(Drops.choose(rules).is_empty(), "One-round gun needs exactly zero total ammo to qualify")
	rules[0].capacity = 5
	rules[0].total = 2
	check(not Drops.choose(rules).is_empty(), "Odd capacity uses a true half-magazine threshold")
	rules[0].total = 3
	check(Drops.choose(rules).is_empty(), "Odd capacity rounds above half do not qualify")
	combat.ammo.magazine_rounds = 0
	equipment.secondary_weapon = _gun(second, 2)
	equipment._equip_slot(1)
	combat.ammo.magazine_rounds = 0
	check(Drops.choose(equipment.ammo_snapshot()).key == &"energy", "Equal ratios prefer primary slot")
	equipment._ammo_states[0].magazine_rounds = 1
	check(Drops.choose(equipment.ammo_snapshot()).key == &"plasma", "Only most depleted type is selected")
	second.allow_random_drop = false
	check(Drops.choose(equipment.ammo_snapshot()).key == &"plasma", "Runtime definition stays frozen after resource edit")
	combat.shot_cooldown = 0.7
	combat.accuracy = 0.3
	check(equipment.add_ammo(equipment.ammo_snapshot()[1].ammo, 4) == 4 and combat.ammo.magazine_rounds == 0 and not combat.ammo.is_reloading and is_equal_approx(combat.shot_cooldown, 0.7) and is_equal_approx(combat.accuracy, 0.3), "Add ammo changes reserve only")
	var total_before: int = equipment.ammo_snapshot()[1].total
	combat.ammo.start_reload()
	combat.ammo.advance_reload(2)
	check(equipment.ammo_snapshot()[1].total == total_before and combat.ammo.magazine_rounds == 2, "Reload conserves total ammo")
	check(equipment.add_ammo(first, 0) == 0 and equipment.add_ammo(first, -1) == 0, "Invalid counts cannot create stock")
	player.free()
	await process_frame
	var invalid_player = Player.instantiate()
	var invalid_equipment = invalid_player.get_node("Equipment")
	var duplicate := _type()
	duplicate.drop_max_count = 9
	invalid_equipment.primary_weapon = _gun(first)
	invalid_equipment.secondary_weapon = null
	var duplicates: Array[AmmoSupply] = [AmmoSupply.create(first, 2), AmmoSupply.create(duplicate, 100)]
	invalid_equipment.initial_ammo = duplicates
	root.add_child(invalid_player)
	invalid_player.set_physics_process(false)
	invalid_equipment._ammo_states[0].magazine_rounds = 0
	check(invalid_equipment.reserve_ammo.energy == 2 and Drops.choose(invalid_equipment.ammo_snapshot()).is_empty(), "Duplicate keeps first count; same-ID conflict suspends drops")
	invalid_player.free()
	await process_frame

func _fixture(waves: bool = false) -> Node3D:
	var region := Node3D.new()
	region.name = "AmmoRegion"
	region.set_script(Region)
	region.add_child(_box(Vector3(24, 0.2, 24), Vector3(0, -0.1, 0)))
	var navigation := NavigationRegion3D.new()
	navigation.name = "NavigationRegion3D"
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-11, 0, -11), Vector3(11, 0, -11), Vector3(11, 0, 11), Vector3(-11, 0, 11)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	region.add_child(navigation)
	var zone := Area3D.new()
	zone.name = "CombatZone"
	zone.add_to_group("combat_zone")
	zone.collision_layer = 0
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(22, 4, 22)
	collision.position.y = 1
	zone.add_child(collision)
	region.add_child(zone)
	var player = Player.instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0, 5)
	var equipment = player.get_node("Equipment")
	equipment.primary_weapon = _gun(_type())
	equipment.secondary_weapon = null
	region.add_child(player)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 15, 10)
	camera.rotation.x = -0.9
	region.add_child(camera)
	if waves:
		var controller = load("res://scripts/world/enemy_wave_controller.gd").new()
		controller.name = "EnemyWaves"
		region.add_child(controller)
		for index in range(2):
			var wave = load("res://scripts/world/enemy_wave_definition.gd").new()
			wave.name = "Wave%d" % index
			controller.add_child(wave)
			var squad = load("res://scenes/world/squad.tscn").instantiate()
			wave.add_child(squad)
			var enemy = Enemy.instantiate()
			enemy.position = Vector3(index * 3, 0, -3)
			enemy.get_node("NavigationAgent3D").path_height_offset = 0
			squad.add_child(enemy)
	return region

func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = size
	body.add_child(collision)
	return body

func _frames(count: int = 6) -> void:
	for frame in range(count): await physics_frame
	await process_frame

func _packages(region: Node) -> Array[Node]:
	var container := region.get_node_or_null("AmmoDrops")
	var result: Array[Node] = []
	if container != null: result.assign(container.get_children())
	return result

func _enemy(region: Node3D, at: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var enemy = Enemy.instantiate()
	enemy.position = at
	enemy.get_node("AI").process_mode = Node.PROCESS_MODE_DISABLED
	region.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func _runtime() -> void:
	var region = _fixture()
	root.add_child(region)
	var player = region.get_node("Player")
	player.set_physics_process(false)
	var equipment = player.get_node("Equipment")
	equipment._ammo_states[0].magazine_rounds = 0
	await _frames()
	check(region.players_inside.has(player), "Actual zone overlap activates region")
	var enemy = _enemy(region)
	enemy.receive_hit(10000)
	enemy.died.emit()
	var definition: AmmoDefinition = equipment.primary_weapon.ammo_definition
	definition.ammo_id = &"edited_after_death"
	definition.drop_min_count = 99
	definition.drop_max_count = 99
	await _frames()
	var packages := _packages(region)
	check(packages.size() == 1, "Actual death creates one package despite repeated callback")
	if packages.is_empty():
		region.free()
		return
	var pickup = packages[0]
	var count: int = pickup._amount
	check(count >= 3 and count <= 5 and pickup._ammo.ammo_id == &"energy" and pickup.global_position.y < 0.05, "Death freezes type/count and places box on floor")
	check(pickup.get_parent().get_parent() == region and pickup.get_node("Visual").get_child_count() == 1, "Region owns visible fallback pickup")
	enemy.free()
	await _frames()
	check(_packages(region).size() == 1, "Deleting corpse preserves ammo")
	player.is_in_dialogue = true
	player.global_position = Vector3(0.5, 0, 0)
	await _frames(14)
	check(_packages(region).size() == 1 and equipment.reserve_ammo.get(&"energy", 0) == 0, "Dialogue blocks pickup while overlapping")
	player.is_in_dialogue = false
	var wall := _box(Vector3(0.12, 1, 2), Vector3(0.25, 0.5, 0))
	region.add_child(wall)
	await _frames(14)
	check(_packages(region).size() == 1, "Wall blocks pickup despite proximity")
	wall.free()
	paused = true
	check(not pickup._try_pickup(player) and equipment.reserve_ammo.get(&"energy", 0) == 0, "Paused world rejects pickup")
	paused = false
	player.global_position.y = 1
	check(not pickup._try_pickup(player), "Different floor rejects pickup")
	player.global_position.y = 0
	await _frames(14)
	check(_packages(region).is_empty() and equipment.reserve_ammo.energy == count and equipment._ammo_states[0].magazine_rounds == 0, "Pickup retries without reentry; credits reserve once")
	equipment.reserve_ammo.energy = 0
	player.global_position = Vector3(0, 0, 5)
	enemy = _enemy(region)
	enemy.receive_headshot_hit(1, player.global_position, {}, {"execution": true})
	await _frames()
	check(_packages(region).size() == 1 and enemy.is_dead, "Actual headshot execution also produces one drop")
	enemy.reset_target()
	enemy.receive_hit(10000)
	await _frames()
	check(_packages(region).size() == 2, "Fresh life can drop again; ground ammo is not owned inventory")
	region._reset_targets()
	await _frames()
	check(_packages(region).is_empty() and not enemy.is_dead, "Region reset clears drops and restores static enemy")
	enemy.receive_hit(10000)
	region._reset_targets()
	await _frames()
	check(_packages(region).is_empty(), "Reset cancels deferred package from old generation")
	var blocker := _box(Vector3(1, 1, 1), Vector3(0, 0.5, 0))
	region.add_child(blocker)
	await _frames()
	var point := Placement.find_ground(region, Vector3(0, 1, 0))
	check(point.is_finite() and point.y < 0.05 and Vector2(point.x, point.z).length() <= 1.6, "Vault death uses nearby ground, never cover top")
	check(not Placement.find_ground(region, Vector3(40, 0, 0)).is_finite(), "No nearby floor does not teleport drop to player")
	blocker.free()
	enemy.receive_hit(10000)
	await _frames()
	player.global_position = Vector3(0, 0, 40)
	await _frames()
	check(region.players_inside.is_empty() and _packages(region).is_empty(), "Last-player exit clears drops")
	region.free()
	await _frames()

func _shooting_and_models() -> void:
	var region = _fixture()
	var player = region.get_node("Player")
	var equipment = player.get_node("Equipment")
	var definition := _type()
	definition.drop_min_count = 9
	definition.drop_max_count = 9
	definition.drop_model = AmmoDefinition.legacy(0).drop_model
	var gun := _gun(definition)
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	gun.shot_noise = null
	gun.headshot_enabled = true
	gun.shotgun.pattern = ShotgunPattern.new()
	gun.shotgun.pattern.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2(-1, 0), Vector2(1, 0)])
	gun.shotgun.pattern_angle_degrees = 8
	gun.shotgun.stable_jitter_degrees = 0
	gun.shotgun.unstable_jitter_degrees = 0
	equipment.primary_weapon = gun
	root.add_child(region)
	current_scene = region
	player.set_physics_process(false)
	var combat = player.get_node("Combat")
	combat.ammo.magazine_rounds = 1
	var muzzle: Vector3 = player.get_muzzle_position()
	var targets: Array[CharacterBody3D] = []
	for offset in [-0.7, 0.0, 0.7]: targets.append(_enemy(region, Vector3(muzzle.x + offset, 0, muzzle.z - 5)))
	await _frames()
	combat.aim_mode = 1
	combat.is_aiming = true
	combat.accuracy = 1
	combat.shot_cooldown = 0
	combat.clear_target_lock()
	combat.shoot()
	await _frames()
	check(targets.all(func(target): return target.is_dead) and combat.ammo.magazine_rounds == 0, "One actual player shotgun shell kills three real enemies with aggregated headshots: %s" % str(targets.map(func(target): return [target.health, target.is_dead])))
	var packages := _packages(region)
	check(packages.size() == 2 and packages.all(func(package): return package._amount == 9), "Three deaths in one shell reserve at most two packages; fixed count ignores gun capacity")
	if not packages.is_empty():
		check(packages[0].get_node("Visual").get_child(0).scene_file_path == definition.drop_model.resource_path, "Death instantiates the chosen per-type model")
	var red := AmmoDefinition.legacy(3).duplicate() as AmmoDefinition
	var another = load("res://scenes/world/objects/ammo_pickup.tscn").instantiate()
	another.configure(red, 2)
	region.add_child(another)
	another.position = Vector3(3, 0, 0)
	if not packages.is_empty():
		var green_mesh: MeshInstance3D = packages[0].get_node("Visual").get_child(0).get_node("Box")
		var red_mesh: MeshInstance3D = another.get_node("Visual").get_child(0).get_node("Box")
		check(green_mesh.mesh.material != red_mesh.mesh.material and green_mesh.mesh.material.albedo_color != red_mesh.mesh.material.albedo_color, "Concurrent ammo models retain separate colors and materials")
		var foreground: BaseMaterial3D = green_mesh.get_active_material(0)
		check(foreground != green_mesh.mesh.material and foreground.no_depth_test and foreground.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and foreground.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and foreground.render_priority == 126, "Pickup uses its own foreground material above opaque corpses")
		check(foreground.albedo_color == green_mesh.mesh.material.albedo_color and not green_mesh.mesh.material.no_depth_test and green_mesh.mesh.material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Foreground conversion preserves color without changing source material")
		check(packages[0].get_node("Label").no_depth_test and packages[0].get_node("Label").render_priority > foreground.render_priority, "Name and count render above pickup models and corpses")
		var band := packages[0].get_node("Visual").get_child(0).get_node("Band") as MeshInstance3D
		check(band.get_active_material(0).no_depth_test, "Unassigned model surfaces also receive foreground material")
		another.get_node("Visual").scale = Vector3.ONE * 3
		check(is_equal_approx(another.get_node("CollisionShape3D").shape.radius, 0.8) and another._amount == 2, "Visual scale does not change pickup radius or count")
	var bad_root := Node.new()
	var bad_model := PackedScene.new()
	bad_model.pack(bad_root)
	bad_root.free()
	red.drop_model = bad_model
	var fallback = load("res://scenes/world/objects/ammo_pickup.tscn").instantiate()
	fallback.configure(red, 3)
	region.add_child(fallback)
	check(fallback.get_node("Visual").get_child(0) is Node3D and fallback._amount == 3, "Invalid model root uses visible fallback without losing ammo")
	region.free()
	await _frames()

func _drop_limit() -> void:
	var region = _fixture()
	var definition: AmmoDefinition = region.get_node("Player/Equipment").primary_weapon.ammo_definition
	definition.drop_min_count = 1
	definition.drop_max_count = 1
	root.add_child(region)
	var player = region.get_node("Player")
	player.set_physics_process(false)
	var equipment = player.get_node("Equipment")
	equipment._ammo_states[0].magazine_rounds = 0
	await _frames()
	var first := _enemy(region, Vector3(-3, 0, 0))
	var second := _enemy(region, Vector3(3, 0, 0))
	var third := _enemy(region, Vector3(0, 0, -3))
	first.receive_hit(10000)
	second.receive_hit(10000)
	third.receive_hit(10000)
	check(region.ammo_drops._pending_spawns == 2, "Same-frame deaths reserve at most two pending slots")
	await _frames()
	check(region.ammo_drops.uncollected_count() == 2 and _packages(region).size() == 2, "Two uncollected packages stop the third death")
	player.global_position = _packages(region)[0].global_position
	await _frames(14)
	check(region.ammo_drops.uncollected_count() == 1 and equipment.reserve_ammo.energy == 1, "Real proximity pickup releases one drop slot")
	player.global_position = Vector3(0, 0, 5)
	await _frames()
	third.died.emit()
	await _frames()
	check(region.ammo_drops.uncollected_count() == 1, "Suppressed old deaths do not queue a later replacement")
	third.reset_target()
	third.receive_hit(10000)
	await _frames()
	check(region.ammo_drops.uncollected_count() == 2, "A new eligible death fills the released slot")
	region._reset_targets()
	await _frames()
	check(region.ammo_drops.uncollected_count() == 0 and region.ammo_drops._pending_spawns == 0, "Reset clears both ground and reserved capacity")
	first.global_position = Vector3(40, 0, 0)
	first.receive_hit(10000)
	await _frames()
	check(region.ammo_drops.uncollected_count() == 0 and region.ammo_drops._pending_spawns == 0, "Failed ground placement returns its reserved slot")
	second.receive_hit(10000)
	region._reset_targets()
	third.receive_hit(10000)
	await _frames()
	check(region.ammo_drops.uncollected_count() == 1 and region.ammo_drops._pending_spawns == 0, "Old-generation callback cannot consume a new generation reservation")
	region.free()
	await _frames()

func _waves() -> void:
	var region = _fixture(true)
	root.add_child(region)
	var player = region.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Equipment")._ammo_states[0].magazine_rounds = 0
	await _frames(20)
	check(region.enemies.size() == 1, "First wave spawns a registered enemy")
	if region.enemies.size() == 1:
		region.enemies[0].receive_hit(10000)
		await _frames(30)
		check(_packages(region).size() == 1, "Last wave-member death retains pending drop through cleanup")
		var alive: Array = region.enemies.filter(func(member): return not member.is_dead)
		check(alive.size() == 1, "Next wave continues alongside previous drop")
		if alive.size() == 1:
			alive[0].receive_hit(10000)
			await _frames(30)
			check(_packages(region).size() == 2, "Final wave retains all drops after runtime enemies retire")
	region.free()
	await _frames()

## 使用实际渲染器运行；普通模型被实体遮挡作为对照，再检查掉落盒子和标签的像素。
func _render_foreground() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	world.add_child(camera)
	camera.position = Vector3(0, 1, 4)
	camera.look_at(Vector3(0, 0.3, 0))
	var blocker := MeshInstance3D.new()
	blocker.mesh = BoxMesh.new()
	blocker.mesh.size = Vector3(3, 3, 0.15)
	blocker.position = Vector3(0, 1, 1)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.8, 0.05, 0.8)
	blocker.material_override = material
	world.add_child(blocker)
	var definition := AmmoDefinition.legacy(0)
	var ordinary := definition.drop_model.instantiate()
	world.add_child(ordinary)
	var pickup = load("res://scenes/world/objects/ammo_pickup.tscn").instantiate()
	pickup.configure(definition, 7)
	world.add_child(pickup)
	pickup.hide()
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	check(before != null and not before.is_empty(), "Actual renderer provides a viewport image")
	if before == null or before.is_empty():
		world.free()
		return
	var image_scale := Vector2(before.get_size()) / camera.get_viewport().get_visible_rect().size
	var point := Vector2i(camera.unproject_position(Vector3(0.12, 0.11, 0)) * image_scale)
	var blocked_color := before.get_pixelv(point)
	check(blocked_color.r > 0.5 and blocked_color.b > 0.5 and blocked_color.g < 0.3, "Opaque foreground geometry actually hides the ordinary model")
	ordinary.hide()
	pickup.show()
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	var visible_color := after.get_pixelv(point)
	check(visible_color.g > visible_color.r and visible_color.g > visible_color.b, "Pickup model renders above the same opaque occluder")
	var label_point := Vector2i(camera.unproject_position(Vector3(0, 0.55, 0)) * image_scale)
	var white_pixels := 0
	for y in range(maxi(0, label_point.y - 12), mini(after.get_height(), label_point.y + 12)):
		for x in range(maxi(0, label_point.x - 65), mini(after.get_width(), label_point.x + 65)):
			var color := after.get_pixel(x, y)
			if color.r > 0.8 and color.g > 0.8 and color.b > 0.8: white_pixels += 1
	check(white_pixels > 8, "Pickup name and count remain visible above opaque geometry")
	DirAccess.make_dir_recursive_absolute("res://logs/ammo_visibility_limit_20261027")
	before.save_png("res://logs/ammo_visibility_limit_20261027/occluded_control.png")
	after.save_png("res://logs/ammo_visibility_limit_20261027/foreground_pickup.png")
	world.free()
	await process_frame
