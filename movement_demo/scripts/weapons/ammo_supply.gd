@tool
class_name AmmoSupply
extends Resource

## 出生配置，不是运行库存；同一类型只填一项。
@export var ammo: AmmoDefinition
## 显式0覆盖旧初值；出生满弹匣不从这里扣除。
@export_range(0, 99999, 1, "or_greater") var amount: int = 0

static func create(definition: AmmoDefinition, count: int) -> AmmoSupply:
	var supply := AmmoSupply.new()
	supply.ammo = definition
	supply.amount = count
	return supply
