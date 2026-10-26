@tool
extends Node3D

## 一波的部署容器。把 squad.tscn 拖到下面，再在小队里摆敌人；复制本节点即可增加一波。
const Squad = preload("res://scripts/world/squad_controller.gd")

## 开启：上一波全灭后开始等待；关闭：上一波实际出场后开始等待，允许多波同时作战。
## 第一波没有上一波，始终从本轮战斗开始计时。
@export var wait_for_previous_clear: bool = true
## 按上面的条件开始计时，经过这些秒数后本波加入。0表示条件满足后尽快加入。
## 暂停、对话或玩家死亡时不扣时间；刷新点被占用时仍需等待原位置空出。
@export_range(0.0, 120.0, 0.1, "or_greater", "suffix:s") var start_delay_seconds: float = 0.0
@export_group("出生搜索")
## 仅后续波生效：实际生成时获得一次玩家大概位置，先快速追查提示区域，再持续警戒搜索。
## 场景树最前的初始波（第0波）始终忽略；真实视野、声音和接敌仍按原规则运行。
@export var search_on_spawn: bool = true
## 出生位置提示的最大水平误差，单位米；默认3米，0为精确的单次位置提示。
## 控制情报误差，不改变原搜索范围，不构成目击或开火许可；隐蔽移动不会自动刷新它。
@export_range(0.0, 30.0, 0.25, "or_greater", "suffix:m") var spawn_search_error_radius: float = 3.0
@export_group("兼容已有场景")
## 可选：相对此波节点的已有小队路径。仅用于保留原地图路径；普通新波次直接放子小队即可。
## 一个小队只能属于一波；留空不额外引用任何小队，不需要逐个登记敌人。
@export var existing_squads: Array[NodePath] = []:
	set(value):
		existing_squads = value
		update_configuration_warnings()

func deployment_configuration() -> Dictionary:
	var squads: Array[Node3D] = []
	var errors: PackedStringArray = []
	for child in get_children():
		if child is Squad: squads.append(child)
		else: errors.append("%s：波次下面请放 Squad 小队，敌人放到小队下面。" % child.name)
	for path in existing_squads:
		var squad = get_node_or_null(path) if not path.is_empty() else null
		if not squad is Squad:
			errors.append("已有小队路径无效：%s" % path)
		elif squads.has(squad):
			errors.append("重复引用小队：%s" % path)
		else:
			squads.append(squad)
	if squads.is_empty(): errors.append("本波还没有小队：拖入 squad.tscn，再把敌人放到小队下。")
	if not is_finite(start_delay_seconds) or start_delay_seconds < 0.0:
		errors.append("波前等待必须是大于或等于0的秒数。")
	if not is_finite(spawn_search_error_radius) or spawn_search_error_radius < 0.0:
		errors.append("出生搜索的位置误差必须是有限且大于或等于0的米数。")
	return {"squads": squads, "errors": errors}

func _get_configuration_warnings() -> PackedStringArray:
	var errors: PackedStringArray = deployment_configuration().errors
	if get_parent() == null or not get_parent().has_method("capture_templates"):
		errors.append("请把本波放在 EnemyWaves 控制器下面；按场景树顺序出场。")
	return errors
