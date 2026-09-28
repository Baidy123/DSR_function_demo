@tool
extends Resource
class_name EnemyActionDefinition

enum Category { DEFAULT, TACTICAL }
@export var action_id: StringName
@export var display_name: String
@export var category: Category = Category.TACTICAL
## 实现统一动作协议；不要求继承某一种具体战术。
@export var implementation: Script
@export var required_capabilities: Array[StringName] = []
## 训练选中此项时自动获得的基础动作 ID，与脚本继承无关。
@export var includes: Array[StringName] = []
@export var config_section: StringName
@export var parameters: Dictionary = {}
