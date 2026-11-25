extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const GrantPath := "res://scenes/world/opening_equipment_grant.tscn"
const Pistol = preload("res://resources/weapons/test_pistol.tres")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	check(ResourceLoader.exists(GrantPath), "开场装备是可编辑场景资源")
	if not ResourceLoader.exists(GrantPath):
		quit(1)
		return

	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var player := PlayerScene.instantiate()
	scene.add_child(player)
	var equipment := player.get_node("Equipment")
	equipment.replace_weapon_slot(1, Pistol)
	var grant: Node = load(GrantPath).instantiate()
	scene.add_child(grant)
	var action := GiveEquipmentAction.new()
	action.grant_path = scene.get_path_to(grant)
	action.player_path = scene.get_path_to(player)
	var event := SceneEventDefinition.new()
	event.event_id = &"typed_equipment_grant"
	event.start_mode = SceneEventDefinition.StartMode.AUTO
	event.actions = [action]
	var director := Director.new()
	director.configure(scene, {"scene_root": scene, "events": [event]})
	scene.add_child(director)
	director.initialize()

	var before: Dictionary = equipment.campaign_snapshot()
	grant.begin_scene_action(SceneRequest.new())
	check(equipment.campaign_snapshot() == before, "无导演批准时发放节点不改库存")
	director.advance(0.016)
	var after: Dictionary = equipment.campaign_snapshot()
	check(after.primary_weapon == grant.weapon and after.secondary_weapon == Pistol,
		"类型化装备动作可发到指定槽，保留原副武器")
	var ammo_id: StringName = grant.ammo_supplies[0].ammo.ammo_id
	check(after.reserve_ammo.get(ammo_id, 0) == before.reserve_ammo.get(ammo_id, 0) + 60
		and after.magazines[0] == grant.weapon.magazine_capacity
		and after.medkit_count == before.medkit_count + 1,
		"满弹匣、备弹与医疗包按资源配置发放")

	var invalid_supplies: Array[AmmoSupply] = [AmmoSupply.create(grant.ammo_supplies[0].ammo, 0)]
	grant.ammo_supplies = invalid_supplies
	var invalid := director.request_action(&"script", {"source": scene, "target": grant})
	check(invalid.status == &"failed" and equipment.campaign_snapshot() == after,
		"混合发放配置无效时保留整个库存")
	grant.weapon = null
	grant.medkit_amount = 0
	var extra_supplies: Array[AmmoSupply] = [AmmoSupply.create(after.primary_weapon.get_ammo_definition(), 5)]
	grant.ammo_supplies = extra_supplies
	var magazine = equipment._ammo_states[0]
	var supply := director.request_action(&"script", {"source": scene, "target": grant})
	check(supply.status == &"completed" and equipment._ammo_states[0] == magazine
		and equipment.reserve_ammo.get(ammo_id) == after.reserve_ammo.get(ammo_id) + 5,
		"纯补备弹保留原武器运行状态")

	var held := HeldAction.new()
	scene.add_child(held)
	var occupying := director.request_action(&"script", {"source": scene, "target": held})
	var queued := director.request_action(&"script", {"source": scene, "target": grant})
	var before_cancel: Dictionary = equipment.campaign_snapshot()
	var was_queued := queued.status == &"queued"
	director.cancel_request(queued.id)
	director.cancel_request(occupying.id)
	director.advance(0.016)
	check(was_queued and queued.status == &"cancelled"
		and equipment.campaign_snapshot() == before_cancel, "导演取消队列中的发放时库存无变化")

	scene.free()
	current_scene = null
	print("EQUIPMENT GRANT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


class HeldAction extends Node:
	func begin_scene_action(_request: SceneRequest) -> void: pass
	func cancel_scene_action(_request: SceneRequest, _reason: StringName) -> void: pass
