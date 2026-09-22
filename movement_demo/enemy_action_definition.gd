@tool
extends Resource
class_name EnemyActionDefinition

## 动作资源只描述动作；计时器与执行进度由每个敌人的动作对象保存。
## 同一动作的不同实现保持相同ID，Training按ID检查权限。
@export var action_id: StringName
## 检查器中阅读用的中文名称。
@export var display_name: String
## 执行动作的脚本，须继承公共库中对应动作。Training只读取ID，不使用此脚本。
## covering_retreat是掩体动作内部能力，没有独立脚本，因此留空。
@export var implementation: Script
