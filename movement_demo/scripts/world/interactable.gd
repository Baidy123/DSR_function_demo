extends Area3D
class_name Interactable

## 场景交互物基类：玩家靠近显示提示，按 E 执行装配好的效果资源。
## 本脚本只负责范围、提示、输入守卫与条件判定，不引用任何具体系统：
## 条件读取 state_path 指向的状态节点（鸭子类型），结果由 InteractionEffect 实现。

signal interacted(interactable: Interactable, player: Node3D)
signal blocked(interactable: Interactable, player: Node3D)

## 提示文本与调试日志使用的名字；留空时回退到节点名。
@export var display_name: String = ""
## 提示动词，例如 查看 / 拾取 / 使用。
@export var verb: String = "查看"
## 关闭时不显示提示，也不响应按键。
@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_node_ready():
			_refresh_prompt()

@export_group("触发限制")
## 只能触发一次；之后提示改为 used_hint。
@export var one_shot: bool = false
## 需要持有的物品，留空表示不限制；由状态节点解释。
@export var required_items: Array[StringName] = []
## 需要已置位的旗标，留空表示不限制。
@export var required_flags: Array[StringName] = []
## 条件不满足时的提示文本。
@export var blocked_hint: String = "条件不足"
## 条件与效果共用的状态节点；默认取 GameState，可换成任意实现
## has_item/item_display_name/is_flag_set 的节点，留空表示不使用状态。
@export var state_path: NodePath = ^"/root/GameState"

@export_group("交互表现")
## 成功后隐藏自身，用于拾取。
@export var hide_on_interact: bool = false
## 已触发且未隐藏时的提示文本。
@export var used_hint: String = "已经查看过"
## 按数组顺序执行的效果资源。
@export var effects: Array[InteractionEffect] = []

var has_interacted: bool = false
var _player_inside: Node3D = null

@onready var name_label: Label3D = $Name
@onready var prompt: Label3D = $Prompt


func _ready() -> void:
	add_to_group(&"interactable")
	_refresh_prompt()


func _physics_process(_delta: float) -> void:
	var player := _find_player()
	if player == _player_inside:
		return
	_player_inside = player
	_refresh_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not event.is_action_pressed("interact"):
		return
	var player := _find_player()
	# 对话中由 DialogueUI 接管推进，交互物不抢同一次按键。
	if player == null or player.is_in_dialogue:
		return
	get_viewport().set_input_as_handled()
	interact(player)


## 外部（例如对话结果）也可以直接调用；返回是否真正执行了效果。
func interact(player: Node3D) -> bool:
	if not can_interact(player):
		blocked.emit(self, player)
		_refresh_prompt()
		return false
	has_interacted = true
	var context := InteractionContext.new(self, player, state())
	for effect in effects:
		if effect != null:
			effect.apply(context)
	interacted.emit(self, player)
	if hide_on_interact:
		_player_inside = null
		monitoring = false
		hide()
	_refresh_prompt()
	return true


func can_interact(_player: Node3D) -> bool:
	if not enabled or not is_inside_tree():
		return false
	if has_interacted and (one_shot or hide_on_interact):
		return false
	return conditions_met()


## 供提示文本与外部检查共用；缺条件时不执行任何效果。
func conditions_met() -> bool:
	var state_node := state()
	for item_id in required_items:
		if state_node == null or not state_node.has_method(&"has_item") or not state_node.has_item(item_id):
			return false
	for flag in required_flags:
		if state_node == null or not state_node.has_method(&"is_flag_set") or not state_node.is_flag_set(flag):
			return false
	return true


## 状态节点可以为空；缺失时条件视为不满足，效果自行跳过。
func state() -> Node:
	if state_path.is_empty():
		return null
	return get_node_or_null(state_path)


func title() -> String:
	return display_name if not display_name.is_empty() else name


func _find_player() -> Node3D:
	if not monitoring:
		return null
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			return body as Node3D
	return null


func _refresh_prompt() -> void:
	if name_label != null:
		name_label.text = title()
	if prompt == null:
		return
	prompt.visible = enabled and _player_inside != null
	if not prompt.visible:
		return
	if not conditions_met():
		prompt.text = blocked_hint
	elif has_interacted and one_shot:
		prompt.text = used_hint
	else:
		prompt.text = "E %s %s" % [verb, title()]
