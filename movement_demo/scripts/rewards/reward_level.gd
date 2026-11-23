class_name RewardLevel
extends Resource

## 一关的三选一奖励配置。
@export_range(1, 5) var level: int = 1
@export var options: Array[RewardOption] = []


func option_by_id(option_id: StringName) -> RewardOption:
	for option in options:
		if option != null and option.id == option_id:
			return option
	return null
