extends SceneTree

## Currency, task awards, one-time purchases, and checkpoint participation.
## Run: godot --headless --path movement_demo --script res://tests/shop_state_test.gd

const GameStateScript := preload("res://scripts/systems/game_state.gd")

const EXPECTED_CHECKS := 42

var failures := 0
var checks_run := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label_text: String) -> void:
	checks_run += 1
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func _run() -> void:
	var state: Node = GameStateScript.new()
	root.add_child(state)

	check(state.has_method(&"add_money"), "GameState exposes add_money")
	check(state.has_method(&"spend_money"), "GameState exposes spend_money")
	check(state.has_method(&"claim_task_reward"), "GameState exposes claim_task_reward")
	check(state.has_method(&"has_task_reward"), "GameState exposes has_task_reward")
	check(state.has_method(&"mark_shop_item_purchased"), "GameState exposes mark_shop_item_purchased")
	check(state.has_method(&"has_purchased_shop_item"), "GameState exposes has_purchased_shop_item")
	check(state.has_method(&"set_level_entry_player_state"), "GameState exposes set_level_entry_player_state")
	check(state.has_method(&"prepare_level_retry_state"), "GameState exposes prepare_level_retry_state")
	check(state.has_signal(&"money_changed"), "GameState emits money_changed")
	if not state.has_method(&"add_money") \
			or not state.has_method(&"spend_money") \
			or not state.has_method(&"claim_task_reward") \
			or not state.has_method(&"has_task_reward") \
			or not state.has_method(&"mark_shop_item_purchased") \
			or not state.has_method(&"has_purchased_shop_item") \
			or not state.has_method(&"set_level_entry_player_state") \
			or not state.has_method(&"prepare_level_retry_state") \
			or not state.has_signal(&"money_changed"):
		_finish(state)
		return

	var money_events: Array = []
	state.money_changed.connect(func(previous: int, current: int) -> void:
		money_events.append([previous, current]))

	check(state.add_money(100) == 100 and state.money == 100, "add_money adds and returns the new total")
	check(money_events.size() == 1 and money_events[0] == [0, 100],
		"add_money emits previous and current totals")
	check(state.add_money(0) == 100 and state.money == 100 and money_events.size() == 1,
		"add_money ignores a zero amount")
	check(state.spend_money(30) and state.money == 70, "spend_money deducts and succeeds")
	check(money_events.size() == 2 and money_events[1] == [100, 70],
		"spend_money emits only after a successful deduction")
	check(not state.spend_money(1000) and state.money == 70 and money_events.size() == 2,
		"insufficient funds leave money unchanged")
	check(state.add_money(-5) == 70 and state.money == 70 and money_events.size() == 2,
		"add_money ignores a negative amount")

	state.completed_level = 1
	state.available_level = 1
	state.record_campaign_checkpoint(1, {"health": {"health": 50.0}})
	check(state.campaign_checkpoint.has("money"), "checkpoint records money")
	check(state.campaign_checkpoint.has("rewarded_task_ids"), "checkpoint records rewarded task IDs")
	check(state.campaign_checkpoint.has("purchased_shop_item_ids"), "checkpoint records purchased shop items")
	check(int(state.campaign_checkpoint["money"]) == 70, "checkpoint captures current money")

	check(state.claim_task_reward(&"task_a", 100, 1) and state.money == 170,
		"task reward is claimed once and credited")
	check(state.has_task_reward(&"task_a"), "claimed task reward is tracked")
	check(bool(state.campaign_checkpoint["rewarded_task_ids"].get(&"task_a", false)),
		"task reward is mirrored into the matching completion checkpoint")
	check(int(state.campaign_checkpoint["money"]) == 170,
		"checkpoint money is synchronized when the task reward is claimed")
	check(not state.claim_task_reward(&"task_a", 100, 1) and state.money == 170,
		"repeated task reward is rejected")
	check(int(state.campaign_checkpoint["money"]) == 170,
		"checkpoint task reward synchronization happens exactly once")

	state.mark_shop_item_purchased(&"shop_rifle")
	check(state.has_purchased_shop_item(&"shop_rifle"), "one-time purchase is tracked")
	check(state.spend_money(50) and state.money == 120, "post-completion spending succeeds")
	state.money = 20
	check(state.restore_campaign_checkpoint(), "checkpoint can be restored after spending")
	check(state.money == 170, "checkpoint refunds post-completion spending")
	check(not state.has_purchased_shop_item(&"shop_rifle"), "checkpoint restore clears post-completion purchases")
	check(state.has_task_reward(&"task_a"), "checkpoint restore retains synchronized task rewards")

	var source := {"health": {"health": 80.0}}
	state.set_level_entry_player_state(source)
	source["health"]["health"] = 12.0
	check(state.level_entry_player_state == {"health": {"health": 80.0}},
		"level entry player state is deep-copied")
	check(state.prepare_level_retry_state()
			and state.pending_player_state == {"health": {"health": 80.0}},
		"prepare_level_retry_state stages the level-entry snapshot")
	state.level_entry_player_state = {}
	state.pending_player_state = {}
	check(not state.prepare_level_retry_state() and state.pending_player_state.is_empty(),
		"prepare_level_retry_state fails when no level-entry snapshot exists")

	var legacy: Node = GameStateScript.new()
	root.add_child(legacy)
	legacy.campaign_checkpoint = {
		"level": 1,
		"completed_level": 1,
		"available_level": 1,
		"claimed_reward_levels": {},
		"system_progress": 0,
		"task_a_returned": "returned",
		"player_state": {"health": {"health": 50.0}},
	}
	check(legacy.restore_campaign_checkpoint(), "old checkpoint without new fields restores")
	check(legacy.money == 0, "old checkpoint defaults money to zero")
	check(legacy.rewarded_task_ids.is_empty() and legacy.purchased_shop_item_ids.is_empty(),
		"old checkpoint defaults reward and purchase maps to empty")
	check(legacy.claim_task_reward(&"task_legacy", 100, 1) and legacy.money == 100,
		"task reward claims safely on an old checkpoint")
	check(legacy.campaign_checkpoint.has("rewarded_task_ids"),
		"old checkpoint gains a reward map after the matching claim")
	check(int(legacy.campaign_checkpoint.get("money", -1)) == 100,
		"old checkpoint money is synchronized after the matching claim")
	check(not legacy.claim_task_reward(&"task_legacy", 100, 1) and legacy.money == 100,
		"old-checkpoint task reward remains non-repeatable")
	legacy.free()

	_finish(state)


func _finish(state: Node) -> void:
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("check count: expected %d, got %d" % [EXPECTED_CHECKS, checks_run])
	if failures == 0:
		print("shop state checks: all passed")
	else:
		print("shop state checks: %d failed" % failures)
	if is_instance_valid(state):
		state.free()
	quit(1 if failures > 0 else 0)
