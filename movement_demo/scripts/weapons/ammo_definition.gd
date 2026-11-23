@tool
class_name AmmoDefinition
extends Resource

## 稳定类型键；共享该 ID 的枪共用备弹。修改后重开生效，名称不参与匹配。
@export var ammo_id: StringName = &""
@export var display_name: String = "弹药"
@export_group("缺弹掉落")
## 仅当玩家携带该类型且总量少于半匣时参与；高级弹药建议保持关闭。
@export var allow_random_drop: bool = false
## 每包数量独立于武器弹匣；两值相同表示固定数量。
@export_range(1, 9999, 1, "or_greater") var drop_min_count: int = 1
@export_range(1, 9999, 1, "or_greater") var drop_max_count: int = 1
@export_group("掉落外观")
## Node3D 纯外观场景，底面中心为原点；不要包含碰撞或拾取逻辑。空值使用通用盒子。
@export var drop_model: PackedScene

func has_valid_id() -> bool:
	return not String(ammo_id).strip_edges().is_empty() and String(ammo_id) == String(ammo_id).strip_edges()

func has_valid_drop_range() -> bool:
	return drop_min_count >= 1 and drop_max_count >= drop_min_count

func same_definition(other: AmmoDefinition) -> bool:
	if other == null: return false
	var same_model := drop_model == other.drop_model
	if drop_model != null and other.drop_model != null and not drop_model.resource_path.is_empty():
		same_model = drop_model.resource_path == other.drop_model.resource_path
	return ammo_id == other.ammo_id and allow_random_drop == other.allow_random_drop and drop_min_count == other.drop_min_count and drop_max_count == other.drop_max_count and same_model

## 旧编号仅在加载边界解析；运行库存不保留第二份整数键余额。
static func legacy(kind: int) -> AmmoDefinition:
	var names := ["rifle", "pistol", "smg", "shotgun"]
	if kind < 0 or kind >= names.size(): return null
	return load("res://resources/ammo/types/%s.tres" % names[kind]) as AmmoDefinition
