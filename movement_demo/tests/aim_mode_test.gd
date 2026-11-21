extends RefCounted

func run(scene: Node) -> Dictionary:
	var player = scene.get_node("Player")
	var combat = player.get_node("Combat")
	var profile := PlayerMouseAimAccuracy.new()
	return {
		"player_ballistic_selector_removed": not "aim_mode" in player and not "aim_mode" in combat,
		"player_probability_sampler_removed": not combat.has_method("_random_direction_in_miss_cone"),
		"mouse_profile_has_no_center_probability": not "initial_accuracy" in profile and not "accuracy_recovery_delay" in profile,
		"player_can_still_select_aim_control": "aim_control" in combat,
	}
