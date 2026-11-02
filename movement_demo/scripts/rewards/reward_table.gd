class_name RewardTable
extends Resource

## 五关奖励总表；每关保存独立的三项配置，可分别修改而互不影响。
@export var levels: Array[RewardLevel] = []


func for_level(level_number: int) -> RewardLevel:
	for level in levels:
		if level != null and level.level == level_number:
			return level
	return null
