extends Node3D

signal presentation_reset(region: Node)

const EnemyWaves = preload("res://scripts/world/enemy_wave_controller.gd")
var _enemy_waves: Node
var _standalone_director: Node

## Match members by faction and communication group; only team awareness is shared.
@export var team_cooperation_bindings: Array[EnemyTeamCooperationBinding] = []

var players_inside: Array[Node3D] = []
var enemies: Array[CharacterBody3D] = []
var _combat_zone: Area3D
var tactical_map = preload("res://scripts/enemy/services/enemy_tactical_map.gd").new()
var cooperation = preload("res://scripts/enemy/services/enemy_cooperation.gd").new()
var vault_navigation = preload("res://scripts/world/vault_navigation.gd").new()
var ammo_drops = preload("res://scripts/world/ammo_drop_controller.gd").new()


func enemy_environment() -> Dictionary:
	cooperation.configure_team_bindings(team_cooperation_bindings)
	cooperation.refresh_squads()
	var navigation := get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	tactical_map.bind_region(navigation)
	vault_navigation.bind_region(navigation)
	return {"zone": get_node_or_null("CombatZone"), "navigation": navigation, "cooperation": cooperation, "tactical_map": tactical_map, "vault_navigation": vault_navigation}


func register_enemy(enemy: CharacterBody3D) -> void:
	if not enemies.has(enemy):
		enemies.append(enemy)
		ammo_drops.register_enemy(enemy)


func unregister_enemy(enemy: CharacterBody3D) -> void:
	ammo_drops.unregister_id(enemy.get_instance_id())
	enemies.erase(enemy)
	cooperation.unregister(enemy.get_instance_id())


func _enter_tree() -> void:
	ammo_drops.bind(self)
	# 父节点先入树：部署模板不能先执行敌人/小队的注册、碰撞或 AI 就绪。
	var controllers: Array[Node] = []
	for child in get_children():
		if child is EnemyWaves: controllers.append(child)
	if not controllers.is_empty(): _enemy_waves = controllers[0]
	for controller in controllers: controller.capture_templates(self)


func _ready() -> void:
	_bind_combat_zone()
	if not is_instance_valid(_enemy_waves): _bind_standalone_director.call_deferred()


func _bind_standalone_director() -> void:
	# Legacy Main has no EnemyWaves. Bind the same core once to the scene's player.
	var scope: Node = self
	var health: Node
	while scope != null:
		health = scope.get_node_or_null("Player/Health")
		if health != null: break
		scope = scope.get_parent()
	if health == null: return
	if health.has_meta(&"scene_director"):
		var existing = health.get_meta(&"scene_director").get_ref()
		if is_instance_valid(existing): return
	_standalone_director = preload("res://scripts/systems/scene_director.gd").new()
	_standalone_director.name = "SceneDirector"
	_standalone_director.configure(scope, {"health": health})
	health.set_meta(&"scene_director", weakref(_standalone_director))
	scope.add_child(_standalone_director, false, Node.INTERNAL_MODE_BACK)
	_standalone_director.initialize()


func _physics_process(delta: float) -> void:
	vault_navigation.advance()
	cooperation.configure_team_bindings(team_cooperation_bindings)
	_bind_combat_zone()
	if has_active_player():
		if is_instance_valid(_enemy_waves): _enemy_waves.advance_from_region(delta)
		# A committed reinforcement can freeze the scene before cooperation advances.
		if get_tree().paused: return
		cooperation.advance(delta)


func has_active_player() -> bool:
	for player in players_inside:
		if is_instance_valid(player) and player.is_inside_tree() and not player.is_dead() and not player.is_in_dialogue:
			return true
	return false


func _bind_combat_zone() -> void:
	var zone := get_node_or_null("CombatZone") as Area3D
	if _combat_zone == zone: return
	if is_instance_valid(_combat_zone):
		_combat_zone.body_entered.disconnect(_on_player_entered)
		_combat_zone.body_exited.disconnect(_on_player_exited)
	var had_players := not players_inside.is_empty()
	players_inside.clear()
	_combat_zone = zone
	if had_players: _reset_targets()
	if zone == null: return
	zone.body_entered.connect(_on_player_entered)
	zone.body_exited.connect(_on_player_exited)
	for body in zone.get_overlapping_bodies(): _on_player_entered(body)


func _on_player_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not players_inside.has(body):
		players_inside.append(body)
		if is_instance_valid(_enemy_waves) and _enemy_waves.auto_start_on_enter:
			_enemy_waves.start_encounter()


func _on_player_exited(body: Node3D) -> void:
	if not players_inside.has(body):
		return
	players_inside.erase(body)
	if players_inside.is_empty():
		_reset_targets()


func _reset_targets() -> void:
	ammo_drops.reset()
	# 先取消波次；queue_free 尚未退树的成员也必须排除，不能复活旧波。
	if is_instance_valid(_enemy_waves): _enemy_waves.reset_encounter()
	cooperation.reset()
	tactical_map.reset()
	presentation_reset.emit(self)
	# 直接子靶与注册的嵌套敌人去重，只刷新本区域。
	var targets: Array[Node] = []
	targets.assign(get_children())
	for enemy in enemies:
		if is_instance_valid(enemy) and not targets.has(enemy):
			targets.append(enemy)
	for target in targets:
		if is_instance_valid(_enemy_waves) and _enemy_waves.owns_runtime_enemy(target): continue
		# 重开卸载场景也会发出离场信号；已出树的目标无需刷新。
		if target.is_inside_tree() and target.has_method("reset_target"):
			target.reset_target()


func _exit_tree() -> void:
	ammo_drops.release()
	tactical_map.release()
	vault_navigation.release()
