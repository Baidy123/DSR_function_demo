class_name ShopCatalog
extends Resource

@export var items: Array[ShopItemDefinition] = []


func valid_items() -> Array[ShopItemDefinition]:
	var result: Array[ShopItemDefinition] = []
	var seen_ids: Dictionary = {}
	for index in items.size():
		var item := items[index]
		if _accept_item(item, index, seen_ids, true):
			result.append(item)
	return result


func item_by_id(item_id: StringName) -> ShopItemDefinition:
	if item_id == &"":
		return null
	var seen_ids: Dictionary = {}
	for index in items.size():
		var item := items[index]
		if not _accept_item(item, index, seen_ids, false):
			continue
		if item.id == item_id:
			return item
	return null


func _accept_item(item: ShopItemDefinition, index: int, seen_ids: Dictionary,
		emit_diagnostics: bool) -> bool:
	if item == null:
		if emit_diagnostics:
			push_warning("ShopCatalog: item at index %d is null." % index)
		return false
	if not item.is_valid():
		if emit_diagnostics:
			push_warning("ShopCatalog: item at index %d (ID %s) is invalid." % [index, item.id])
		return false
	if seen_ids.has(item.id):
		if emit_diagnostics:
			push_warning("ShopCatalog: duplicate item ID %s at index %d; the first item wins." % [item.id, index])
		return false
	seen_ids[item.id] = true
	return true
