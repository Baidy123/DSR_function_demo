class_name PlayerCampaignState
extends RefCounted

## 跨场景只搬运可延续的玩家状态；瞄准、换弹和受击计时等临时过程不跨关。


static func capture(player: Node) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {}
	var snapshot: Dictionary = {}
	var health := player.get_node_or_null("Health")
	if health != null and health.has_method(&"campaign_snapshot"):
		snapshot["health"] = health.campaign_snapshot()
	var equipment := player.get_node_or_null("Equipment")
	if equipment != null and equipment.has_method(&"campaign_snapshot"):
		snapshot["equipment"] = equipment.campaign_snapshot()
	return snapshot


static func apply(player: Node, snapshot: Dictionary) -> void:
	if player == null or not is_instance_valid(player) or snapshot.is_empty():
		return
	var health := player.get_node_or_null("Health")
	var health_snapshot: Dictionary = snapshot.get("health", {})
	if health != null and not health_snapshot.is_empty() and health.has_method(&"apply_campaign_snapshot"):
		health.apply_campaign_snapshot(health_snapshot)
	var equipment := player.get_node_or_null("Equipment")
	var equipment_snapshot: Dictionary = snapshot.get("equipment", {})
	if equipment != null and not equipment_snapshot.is_empty() and equipment.has_method(&"apply_campaign_snapshot"):
		equipment.apply_campaign_snapshot(equipment_snapshot)
