@tool
class_name SceneEventFilter
extends Resource

## 对来源信号的单个参数过滤。索引从0开始，同一事件的多个过滤必须同时满足。
enum Operator { EQUALS, NODE_IN_GROUP }
enum ValueType { BOOL, INT, FLOAT, STRING, STRING_NAME }

## 第几个信号参数，从0开始。body_entered的body是0；flag_changed的旗标是0、值是1。
@export_range(0, 7) var parameter_index: int = 0
## EQUALS按类型和值精确匹配；NODE_IN_GROUP要求参数是属于指定组的Node，例如player。
@export var operator: Operator = Operator.EQUALS:
	set(value):
		operator = value
		notify_property_list_changed()
## 对照来源信号声明选择类型；String与StringName不同，整数1不等于布尔true。
@export var value_type: ValueType = ValueType.STRING_NAME:
	set(value):
		value_type = value
		notify_property_list_changed()
## BOOL类型要匹配的值；flag_changed的第1参数通常选true。
@export var bool_value: bool = true
## INT类型要匹配的整数。
@export var int_value: int = 0
## FLOAT类型要精确匹配的浮点数，不是范围判断。
@export var float_value: float = 0.0
## STRING类型要匹配的文字，例如物品显示名。
@export var string_value: String = ""
## STRING_NAME类型要匹配的稳定ID，例如item_gained第0参数的物品ID。
@export var string_name_value: StringName = &""
## NODE_IN_GROUP模式的组名；body_entered用player排除敌人和其他身体。
@export var group_name: StringName = &"player"

func _validate_property(property: Dictionary) -> void:
	if property.name == "group_name" and operator != Operator.NODE_IN_GROUP: property.usage &= ~PROPERTY_USAGE_EDITOR
	if property.name == "value_type" and operator != Operator.EQUALS: property.usage &= ~PROPERTY_USAGE_EDITOR
	var values := ["bool_value", "int_value", "float_value", "string_value", "string_name_value"]
	if property.name in values and (operator != Operator.EQUALS or values.find(property.name) != value_type):
		property.usage &= ~PROPERTY_USAGE_EDITOR

func expected_value() -> Variant:
	match value_type:
		ValueType.BOOL: return bool_value
		ValueType.INT: return int_value
		ValueType.FLOAT: return float_value
		ValueType.STRING: return string_value
		ValueType.STRING_NAME: return string_name_value
	return null

func validate(arguments: Array) -> String:
	if parameter_index < 0 or parameter_index >= arguments.size():
		return "Filter parameter_index %d is outside signal arity %d." % [parameter_index, arguments.size()]
	var argument: Dictionary = arguments[parameter_index]
	var declared_type: int = argument.get("type", TYPE_NIL)
	if operator == Operator.NODE_IN_GROUP:
		if group_name.is_empty(): return "NODE_IN_GROUP requires a nonempty group_name."
		if declared_type != TYPE_NIL and declared_type != TYPE_OBJECT:
			return "NODE_IN_GROUP requires a Node parameter, not %s." % type_string(declared_type)
		var declared_class: StringName = argument.get("class_name", &"")
		if ClassDB.class_exists(declared_class) and not ClassDB.is_parent_class(declared_class, &"Node") and declared_class != &"Object":
			return "NODE_IN_GROUP cannot match declared class %s." % declared_class
		return ""
	if operator != Operator.EQUALS: return "Unknown event filter operator."
	var expected: Variant = expected_value()
	if expected == null: return "Unknown equality value_type."
	if declared_type != TYPE_NIL and declared_type != typeof(expected):
		return "Equality filter expects %s but signal parameter %d declares %s." % [type_string(typeof(expected)), parameter_index, type_string(declared_type)]
	return ""

func matches(arguments: Array) -> bool:
	if parameter_index < 0 or parameter_index >= arguments.size(): return false
	var value: Variant = arguments[parameter_index]
	if operator == Operator.NODE_IN_GROUP:
		return is_instance_valid(value) and value is Node and value.is_in_group(group_name)
	if operator != Operator.EQUALS: return false
	var expected: Variant = expected_value()
	return typeof(value) == typeof(expected) and value == expected
