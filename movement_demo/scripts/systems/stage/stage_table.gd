class_name StageTable
extends Resource

## 阶段／任务／NPC 状态规则配置表；一份表对应一套任务循环，可以按阶段拆成多份。

## 阶段定义，按 index 升序解释。
@export var stages: Array[StageDefinition] = []
## 任务定义；阶段通过 quest_id 找到自己的任务。
@export var quests: Array[QuestDefinition] = []
## NPC 状态规则，按数组顺序匹配并覆盖。
@export var rules: Array[StateRule] = []


## 按序号升序返回阶段定义，不改动原数组。
func sorted_stages() -> Array[StageDefinition]:
	var result: Array[StageDefinition] = stages.duplicate()
	result.sort_custom(func(a: StageDefinition, b: StageDefinition) -> bool: return a.index < b.index)
	return result


func stage_for_index(index: int) -> StageDefinition:
	for stage in stages:
		if stage.index == index:
			return stage
	return null


func quest_by_id(id: StringName) -> QuestDefinition:
	if id == &"":
		return null
	for quest in quests:
		if quest.id == id:
			return quest
	return null


func quest_for_stage(index: int) -> QuestDefinition:
	var stage := stage_for_index(index)
	if stage == null:
		return null
	return quest_by_id(stage.quest_id)
