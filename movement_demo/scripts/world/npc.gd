extends StaticBody3D

const Director = preload("res://scripts/systems/scene_director.gd")

signal interaction_requested(player: Node3D)

## 状态控制器使用的稳定 id；留空时回退到节点名，场景里换名字不会打断配置表。
@export var npc_id: StringName = &""
## 该 NPC 使用的 Dialogue Manager 对话资源；留空时按 E 不启动对话。
@export var dialogue_resource: DialogueResource
## 对话资源中的起始标题，例如 start；应与该资源中的标题一致。
@export var dialogue_start: String = "start"
## Fixed seating can follow a furniture node when stage rules update the NPC.
@export_node_path("Node3D") var seat_path: NodePath
@export var seat_offset := Vector3.ZERO

var pending_player = null
## 最近一次由状态控制器下发的状态；只用于查询与记录，不参与对话逻辑。
var stage_state: Dictionary = {}

@onready var interaction_area: Area3D = $InteractionArea


func _ready() -> void:
	# 阶段状态控制器按组枚举 NPC，不需要知道场景节点路径。
	add_to_group(&"npc")
	if npc_id == &"":
		npc_id = StringName(name)
	global_position = resolve_stage_position(global_position)


## 状态控制器通过该方法下发“这个阶段我该是什么样”；未接入控制器时不会被调用。
func apply_stage_state(state: Dictionary) -> void:
	visible = bool(state.get("present", true))
	var spot = state.get("position", null)
	if spot is Vector3:
		global_position = resolve_stage_position(spot)
	var facing = state.get("facing", null)
	if facing is Vector3 and is_inside_tree() and not (facing as Vector3).is_equal_approx(global_position):
		look_at(facing, Vector3.UP)
	var dialogue = state.get("dialogue", null)
	if dialogue is String and not (dialogue as String).is_empty():
		dialogue_resource = load(dialogue)
	stage_state = state.duplicate()


func resolve_stage_position(fallback: Vector3) -> Vector3:
	var seat := get_node_or_null(seat_path) as Node3D if not seat_path.is_empty() else null
	return seat.to_global(seat_offset) if seat != null else fallback


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if is_instance_valid(pending_player):
		get_viewport().set_input_as_handled()
		return

	# 未指定对话文件时，不锁住玩家。
	if dialogue_resource == null:
		return

	for body in interaction_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			interaction_requested.emit(body)
			# 专用 NPC 可以在对话前接管这次交互；普通 NPC 继续原有对话流程。
			if get_viewport().is_input_handled():
				return
			request_dialogue(body)
			get_viewport().set_input_as_handled()
			return


func request_dialogue(player: Node3D):
	var director = Director.for_node(self)
	if director == null: return null
	return director.request_action(&"dialogue", {"source": self, "target": get_node_or_null("../DialogueUI"),
		"player": player, "origin": &"interaction", "dedupe_key": &"npc_dialogue",
		"parameters": {"resource": dialogue_resource, "start": dialogue_start, "face_source": true}})
