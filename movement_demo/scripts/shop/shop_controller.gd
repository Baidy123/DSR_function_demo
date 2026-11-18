class_name ShopController
extends Node

## Currency shop controller: owns catalog visibility, purchase validation and
## mutation. SceneDirector owns opening, closing and control leases.

const Director = preload("res://scripts/systems/scene_director.gd")
const Request = preload("res://scripts/systems/scene_request.gd")
signal scene_action_finished(id: int, result: StringName)
var _scene_request: Request

@export var shop_catalog: ShopCatalog
@export var shop_board_path: NodePath = ^"../ShopBoard"

@onready var shop_board: Node = get_node_or_null(shop_board_path)

var _state: Node
var _open := false
var _visible_items: Array[ShopItemDefinition] = []
var _watched_health: Node


func _ready() -> void:
	_state = get_node_or_null("/root/GameState")
	if shop_board != null and shop_board.has_signal(&"purchase_requested") \
			and not shop_board.purchase_requested.is_connected(_on_purchase_requested):
		shop_board.purchase_requested.connect(_on_purchase_requested)
	if shop_board != null and shop_board.has_signal(&"close_requested") \
			and not shop_board.close_requested.is_connected(close_shop):
		shop_board.close_requested.connect(close_shop)


func _exit_tree() -> void:
	_open = false
	_unwatch_player_health()
	_close_authorized(&"cancelled")


func open_shop_for_player(player: Node3D) -> bool:
	var director = Director.for_node(self)
	if director == null: return false
	var request = director.request_action(&"shop", {"source": self, "target": self, "player": player,
		"origin": &"interaction", "dedupe_key": &"shop"})
	return request.has_started() and request.status not in [&"failed", &"cancelled", &"rejected"]

func begin_scene_action(request: Request) -> void:
	if not request.is_current() or request.kind != &"shop" or request.node(&"target") != self: return
	_scene_request = request
	if not _open_authorized(request.node(&"player")):
		_scene_request = null
		request.fail("shop_open_failed")

func finish_scene_action(request: Request) -> void:
	if _scene_request == request: _close_authorized(&"completed")

func cancel_scene_action(request: Request, _reason: StringName) -> void:
	if _scene_request == request: _close_authorized(&"cancelled")

func close_shop() -> void:
	if _scene_request == null: return
	var director = Director.for_node(self)
	if director != null: director.finish_request(_scene_request.id)

func _close_authorized(result: StringName) -> void:
	var request := _scene_request
	_scene_request = null
	_open = false
	if shop_board != null and shop_board.has_method(&"hide_board"):
		shop_board.hide_board()
	_unwatch_player_health()
	if request != null: scene_action_finished.emit(request.id, result)

func _open_authorized(player: Node3D) -> bool:
	if _open:
		return true
	if player == null or not is_instance_valid(player) or not player.is_in_group(&"player"):
		return false
	if not _player_alive(player):
		return false
	var state := _resolve_state()
	if state == null or shop_catalog == null:
		if state == null:
			push_warning("ShopController: GameState is missing")
		else:
			push_warning("ShopController: shop catalog is missing")
		return false
	if shop_board == null or not shop_board.has_method(&"configure") \
			or not shop_board.has_method(&"show_board") \
			or not shop_board.has_method(&"hide_board"):
		push_warning("ShopController: shop board is missing or incomplete")
		return false
	var items := _collect_visible_items()
	_visible_items = items
	if not shop_board.configure(_view_rows(items, state, player), int(state.money)):
		push_warning("ShopController: board rejected the item configuration")
		return false
	var director = Director.for_node(self)
	if director == null or _scene_request == null: return false
	director.hold_request_controls(_scene_request, not items.is_empty())
	shop_board.show_board()
	_open = true
	_watch_player_health(player)
	return true


func purchase(item_id: StringName, slot: int) -> bool:
	if not _open:
		return false
	var state := _resolve_state()
	var player := _player()
	if state == null or player == null or not _player_alive(player):
		return false
	var item := _find_item(item_id)
	if item == null or not _is_visible(item):
		return false
	if item.price > 0 and int(state.money) < item.price:
		return false
	if not _validate_effect(state, player, item, slot):
		return false
	if item.price > 0:
		if not state.spend_money(item.price):
			push_error("ShopController: spend failed after validation")
			return false
	if not _apply_effect(state, player, item, slot):
		if item.price > 0:
			state.add_money(item.price)
		return false
	if item.one_time:
		state.mark_shop_item_purchased(item.id)
	_refresh_board()
	return true


func _is_visible(item: ShopItemDefinition) -> bool:
	if item == null:
		return false
	var state := _resolve_state()
	if state == null:
		return false
	if item.unlock_level > int(state.completed_level):
		return false
	if item.effect == ShopItemDefinition.Effect.SET_FLAG and state.get_flag(item.flag_key):
		return false
	return not item.one_time or not state.has_purchased_shop_item(item.id)


func _collect_visible_items() -> Array[ShopItemDefinition]:
	var result: Array[ShopItemDefinition] = []
	if shop_catalog == null:
		return result
	for item in shop_catalog.valid_items():
		if _is_visible(item):
			result.append(item)
	return result


func _find_item(item_id: StringName) -> ShopItemDefinition:
	if shop_catalog == null or item_id == &"":
		return null
	return shop_catalog.item_by_id(item_id)


func _view_rows(items: Array[ShopItemDefinition], state: Node, player: Node3D) -> Array:
	var rows: Array = []
	for item in items:
		var row := {
			"id": item.id,
			"name": item.display_name,
			"description": item.description,
			"price": item.price,
			"weapon": item.effect == ShopItemDefinition.Effect.WEAPON,
		}
		if item.effect == ShopItemDefinition.Effect.WEAPON:
			row["slots"] = [
				{"slot": 0, "label": "覆盖主武器", "enabled": _can_purchase(item, 0, state, player)},
				{"slot": 1, "label": "覆盖副武器", "enabled": _can_purchase(item, 1, state, player)},
			]
		else:
			row["enabled"] = _can_purchase(item, -1, state, player)
		rows.append(row)
	return rows


func _can_purchase(item: ShopItemDefinition, slot: int, state: Node, player: Node3D) -> bool:
	if item == null or item.price > int(state.money):
		return false
	return _validate_effect(state, player, item, slot)


func _validate_effect(state: Node, player: Node3D, item: ShopItemDefinition, slot: int) -> bool:
	match item.effect:
		ShopItemDefinition.Effect.ADD_MEDKIT:
			var equipment := _equipment(player)
			return equipment != null and equipment.has_method(&"can_add_medkits") \
				and equipment.can_add_medkits(item.medkit_data, item.amount)
		ShopItemDefinition.Effect.REFILL_AMMO:
			var equipment := _equipment(player)
			return equipment != null and equipment.has_method(&"refill_all_ammo") \
				and equipment.has_method(&"can_refill_all_ammo") \
				and not bool(equipment.can_refill_all_ammo())
		ShopItemDefinition.Effect.SET_FLAG:
			return state.has_method(&"grant_shop_flag") and not state.get_flag(item.flag_key)
		ShopItemDefinition.Effect.WEAPON:
			if slot not in [0, 1] or item.weapon_data == null \
					or item.weapon_data.fire_mode == WeaponData.FireMode.MELEE:
				return false
			var equipment := _equipment(player)
			return equipment != null and equipment.has_method(&"replace_weapon_slot")
		_:
			return false
	return false


func _apply_effect(state: Node, player: Node3D, item: ShopItemDefinition, slot: int) -> bool:
	match item.effect:
		ShopItemDefinition.Effect.ADD_MEDKIT:
			var equipment := _equipment(player)
			if equipment == null or not equipment.has_method(&"add_medkits"):
				return false
			return equipment.add_medkits(item.medkit_data, item.amount)
		ShopItemDefinition.Effect.REFILL_AMMO:
			var equipment := _equipment(player)
			if equipment == null:
				return false
			equipment.refill_all_ammo()
			return true
		ShopItemDefinition.Effect.SET_FLAG:
			return state.grant_shop_flag(item.flag_key)
		ShopItemDefinition.Effect.WEAPON:
			var equipment := _equipment(player)
			if equipment == null:
				return false
			return equipment.replace_weapon_slot(slot, item.weapon_data)
		_:
			return false


func _refresh_board() -> void:
	if shop_board == null or not shop_board.has_method(&"configure"):
		return
	_visible_items = _collect_visible_items()
	var state := _resolve_state()
	if state == null:
		return
	shop_board.configure(_view_rows(_visible_items, state, _player()), int(state.money))


func _on_purchase_requested(item_id: StringName, slot: int) -> void:
	purchase(item_id, slot)


func _resolve_state() -> Node:
	if _state == null or not is_instance_valid(_state):
		_state = get_node_or_null("/root/GameState")
	return _state


func _player() -> Node3D:
	return _scene_request.node(&"player") as Node3D if _scene_request != null else null


func _health(player: Node3D) -> Node:
	return player.get_node_or_null("Health") if player != null else null


func _equipment(player: Node3D) -> Node:
	return player.get_node_or_null("Equipment") if player != null else null


func _player_alive(player: Node3D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method(&"is_dead") and player.is_dead():
		return false
	var health := _health(player)
	return health == null or not bool(health.get("is_dead"))


func _watch_player_health(player: Node3D) -> void:
	_unwatch_player_health()
	var health := _health(player)
	if health == null or not health.has_signal(&"died"):
		return
	_watched_health = health
	if not health.died.is_connected(_on_player_died):
		health.died.connect(_on_player_died)


func _unwatch_player_health() -> void:
	if _watched_health != null and is_instance_valid(_watched_health) \
			and _watched_health.has_signal(&"died") \
			and _watched_health.died.is_connected(_on_player_died):
		_watched_health.died.disconnect(_on_player_died)
	_watched_health = null


func _on_player_died() -> void:
	var director = Director.for_node(self)
	if director != null and _scene_request != null:
		director.cancel_request(_scene_request.id, &"player_died")
