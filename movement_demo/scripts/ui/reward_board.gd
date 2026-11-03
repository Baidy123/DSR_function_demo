extends CanvasLayer

## 战斗奖励三选一面板：默认隐藏，暂停时也能处理输入；每次显示只能选择并发出一个奖励。

signal reward_selected(reward_id: StringName)

const REWARD_IDS: Array[StringName] = [&"first_aid", &"ammo", &"system_progress"]

@onready var _buttons: Array[Button] = [
	$Panel/Margin/Content/Buttons/FirstAid/Button,
	$Panel/Margin/Content/Buttons/Ammo/Button,
	$Panel/Margin/Content/Buttons/SystemProgress/Button,
]
@onready var _descriptions: Array[Label] = [
	$Panel/Margin/Content/Buttons/FirstAid/Description,
	$Panel/Margin/Content/Buttons/Ammo/Description,
	$Panel/Margin/Content/Buttons/SystemProgress/Description,
]

var _selected: StringName = &""
var _reward_ids: Array[StringName] = REWARD_IDS.duplicate()
var options: Array[RewardOption] = []


func _ready() -> void:
	for index in REWARD_IDS.size():
		_buttons[index].pressed.connect(_select_index.bind(index))


func configure(reward_options: Array[RewardOption]) -> bool:
	if reward_options.size() != _buttons.size():
		push_error("RewardBoard: exactly three reward options are required")
		return false
	for option in reward_options:
		if option == null or option.id == &"":
			push_error("RewardBoard: reward option is missing or has an empty id")
			return false
	options = reward_options.duplicate()
	_reward_ids.clear()
	for index in options.size():
		_reward_ids.append(options[index].id)
		_buttons[index].text = options[index].display_name
		_descriptions[index].text = options[index].description
	return true


func show_board() -> void:
	_selected = &""
	visible = true
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _select_index(index: int) -> void:
	if index >= 0 and index < _reward_ids.size():
		select_reward(_reward_ids[index])


func select_reward(reward_id: StringName) -> bool:
	if not _selected.is_empty() or _reward_ids.find(reward_id) == -1:
		return false
	_selected = reward_id
	visible = false
	reward_selected.emit(reward_id)
	return true
