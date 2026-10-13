extends "res://tests/enemy/enemy_geometry_batch_test.gd"

## Exercise the production AI and Context protocol with deterministic action and
## board inputs. Geometry/body truth belongs to the separate real-scene suites.
class ActorProbe extends CharacterBody3D:
	var move_speed := 4.0
	func is_vaulting() -> bool: return false

class FireProbe extends RefCounted:
	var request: Dictionary = {}

class MeleeProbe extends RefCounted:
	func cancel() -> void: pass

class ContextProbe extends "res://scripts/enemy/services/enemy_context.gd":
	var advanced := true
	func cooperation_enabled() -> bool: return advanced
	func _publish_coordination_versions() -> bool: return true

class SelectorProbe extends "res://scripts/enemy/enemy_action_selector.gd":
	var supplied: Array[Dictionary] = []
	func assess_options(_ai, _visible: bool) -> Array[Dictionary]:
		return supplied.duplicate(true)

class ActionProbe extends "res://scripts/enemy/actions/enemy_action.gd":
	var events: Array = []
	var executable := true
	var begin_ok := true
	var interruptible := true
	var escape_allowed := false
	var starts := 0
	var cancels := 0
	var contract := {"valid": true, "segment_boundary": false, "remaining_seconds": 1.0,
		"progress": 0.25, "ready_for_phase": false}
	func is_enabled() -> bool: return true
	func validate(_candidate: Dictionary, _visible: bool) -> bool: return executable
	func begin(candidate: Dictionary, _visible: bool) -> bool:
		events.append("begin:" + String(action_id))
		starts += 1
		plan = candidate
		_running = begin_ok
		return begin_ok
	func valid(_visible: bool) -> bool: return _running and executable
	func cancel(_reason: StringName = &"switch") -> void:
		events.append("cancel:" + String(action_id))
		cancels += 1
		_running = false
		plan = {}
	func can_interrupt(_next: Dictionary, _visible: bool) -> bool: return interruptible
	func assignment_escape(_candidate: Dictionary, _visible: bool) -> bool:
		return escape_allowed and executable
	func execution_contract(_visible: bool) -> Dictionary: return contract.duplicate(true)

class BoardProbe extends RefCounted:
	var elapsed := 10.0
	var member_count := 2
	var events: Array = []
	var task: Dictionary = {}
	var reports: Array = []
	var pending: Dictionary = {}
	var accepted_lease := false
	var prepare_ok := true
	var commit_ok := true
	var available := true
	var submitted: Array = []
	func has_team_binding(_context) -> bool: return false
	func team_level(context, _legacy_level: int = 0) -> int: return 2 if context.cooperation_enabled() else 0
	func registered_member_count() -> int: return member_count
	func coordination_identity(context) -> Dictionary:
		return {"actor_id": context.actor.get_instance_id(), "generation": 1, "member_generation": 1,
			"team_id": 3, "config_revision": 1, "environment_revision": 1,
			"navigation_revision": 1, "relation_revision": 1}
	func assignment(_context) -> Dictionary:
		if task.is_empty() or task.expires_at <= elapsed: return {}
		return task.duplicate(true)
	func submit_offers(_context, offers: Array) -> bool:
		submitted = offers.duplicate(true)
		return true
	func reservation_offer_available(_context, _offer: Dictionary) -> bool: return available
	func clear_execution(_owner: int) -> void:
		events.append("clear")
		accepted_lease = false
	func prepare_assignment(_context, identity: Dictionary, key: String) -> Dictionary:
		events.append("prepare")
		if not prepare_ok or task.is_empty() or identity.assignment_id != task.assignment_id: return {}
		if task.accepted and not task.segment_boundary: return {}
		if not task.allowed_offer_keys.has(key): return {}
		pending = {"reservation_id": 70, "offer_key": key, "expires_at": task.expires_at}
		return pending.duplicate(true)
	func commit_assignment(_context, identity: Dictionary, token: Dictionary) -> bool:
		events.append("commit")
		if not commit_ok or task.is_empty() or pending.is_empty() or token != pending or identity.assignment_id != task.assignment_id: return false
		task.accepted = true
		task.selected_offer_key = token.offer_key
		task.segment_boundary = false
		accepted_lease = true
		pending = {}
		return true
	func rollback_assignment(_context, _identity: Dictionary, _token: Dictionary) -> void:
		events.append("rollback")
		pending = {}
		task = {}
		accepted_lease = false
	func report_assignment(_context, report: Dictionary) -> bool:
		reports.append(report.duplicate(true))
		events.append("report:" + String(report.state))
		if task.is_empty() or report.assignment_id != task.assignment_id: return false
		if report.state in [&"unavailable", &"self_preservation"]:
			task = {}
			accepted_lease = false
			return true
		if not report.get("execution_valid", false): return false
		task.segment_boundary = report.segment_boundary
		return true
	func prepare_reservation(_context, offer: Dictionary, _duration: float) -> Dictionary:
		return {"reservation_id": 80, "offer_key": offer.offer_key}
	func commit_reservation(_context, _token: Dictionary) -> bool: return true
	func rollback_reservation(_context, _token: Dictionary) -> void: pass
	func release_reservation(_context, _token: Dictionary) -> void: pass
	func validate_reservation(_context, _token: Dictionary) -> bool: return true

func _run() -> void:
	_test_unassigned_and_permissions()
	_test_accept_and_boundary()
	_test_real_escape_and_invalid()
	_test_transaction_failures()
	_test_expiry_and_completion()
	print("ASSIGNMENT EXECUTION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _fixture() -> Dictionary:
	var actor := ActorProbe.new()
	root.add_child(actor)
	var context := ContextProbe.new()
	context.actor = actor
	context.fire = FireProbe.new()
	context.melee = MeleeProbe.new()
	context.agent = NavigationAgent3D.new()
	actor.add_child(context.agent)
	var board := BoardProbe.new()
	context.cooperation = board
	var ai := preload("res://scripts/enemy/enemy_ai.gd").new()
	# Do not attach the controller: production _ready loads the full arena. The
	# tested methods below are unmodified production methods, not mirrored logic.
	ai.actor = actor
	ai.context = context
	ai.action_selector = SelectorProbe.new()
	ai.utility_hold_seconds = 0.0
	ai.utility_switch_advantage = 0.0
	for key in [&"test_post", &"test_personal", &"test_escape"]:
		var action := ActionProbe.new()
		action.setup(context)
		action.action_id = key
		action.events = board.events
		ai.actions[key] = action
	return {"ai": ai, "context": context, "board": board, "actor": actor}

func _dispose(f: Dictionary) -> void:
	f.ai.free()
	f.actor.free()

func _candidate(id: StringName, cost: float, key: String = "") -> Dictionary:
	var value := {"id": id, "cost": cost, "destination": {}, "outcome": {"unavailable_seconds": cost, "exposed_seconds": 0.0}}
	if not key.is_empty():
		value.coordination_offer_key = key
		value.coordination_role = &"search_sector"
	return value

func _assign(f: Dictionary) -> void:
	f.board.task = {"generation": 1, "team_id": 3, "plan_id": 4, "plan_version": 1,
		"phase_id": 1, "assignment_id": 5, "assignment_revision": 1, "owner_action": &"test_post",
		"allowed_offer_keys": ["left_a", "left_b"], "accepted": false,
		"segment_boundary": true, "expires_at": 14.0, "selected_offer_key": ""}

func _step(f: Dictionary, candidates: Array[Dictionary]) -> void:
	f.ai.action_selector.supplied = candidates
	f.ai._utility_timer = 0.0
	f.ai._update_utility_decision(0.01, true)

func _accepted(f: Dictionary) -> void:
	_assign(f)
	_step(f, [_candidate(&"test_post", 2.0, "left_a")])

func _test_unassigned_and_permissions() -> void:
	var f := _fixture()
	var personal := _candidate(&"test_personal", 4.0)
	var offer := _candidate(&"test_post", 0.0, "left_a")
	_step(f, [offer, personal])
	check(f.ai.current_action == f.ai.actions[&"test_personal"], "Unassigned role offers cannot execute just because they are cheap")
	check(f.ai.utility_current.cost == 4.0, "Qualification does not alter the original selected utility cost")
	f.context.advanced = false
	_assign(f)
	_step(f, [offer, personal])
	check(f.ai.current_action == f.ai.actions[&"test_personal"] and f.context.coordination_assignment().is_empty(), "Advanced OFF does not accept a tactical role")
	f.board.member_count = 1
	f.context.advanced = true
	var personal_options: Array[Dictionary] = [personal]
	check(f.context.coordination_choices(personal_options).size() == 1 and f.context.coordination_assignment().is_empty(), "A single actor retains its ordinary candidate without assignment restrictions")
	f.board.member_count = 2
	f.context.advanced = false
	f.board.available = false
	var move := _candidate(&"test_personal", 1.0)
	move.destination = {"position": Vector3(2, 0, 0)}
	var moving_options: Array[Dictionary] = [move]
	check(f.context.coordination_choices(moving_options).is_empty() and f.context.coordination_choices(personal_options).size() == 1, "Advanced OFF still filters conflicting destinations and preserves stationary defense")
	_dispose(f)

func _test_accept_and_boundary() -> void:
	var f := _fixture()
	_assign(f)
	_step(f, [_candidate(&"test_personal", 0.0), _candidate(&"test_post", 7.0, "left_a")])
	var post = f.ai.actions[&"test_post"]
	check(f.ai.current_action == post and f.ai.utility_current.cost == 7.0, "A real assignment restricts eligibility without adding an artificial score bonus")
	check(f.board.events == ["prepare", "clear", "begin:test_post", "commit"], "Initial acceptance follows prepare then clear then actual begin then commit")
	check(f.board.accepted_lease and f.context._coordination_execution.assignment_id == 5, "Only successful begin and commit record the executing assignment")
	var original_deadline: float = f.board.task.expires_at
	_step(f, [])
	check(f.ai.current_action == post and post.starts == 1 and post.cancels == 0, "An accepted valid short segment survives missing asynchronous candidates")
	_step(f, [_candidate(&"test_post", 0.0, "left_b"), _candidate(&"test_personal", -10.0)])
	check(post.starts == 1 and f.context._coordination_execution.selected_offer_key == "left_a", "Cheaper alternatives and unrelated actions cannot replace a non-boundary segment")
	post.contract.segment_boundary = true
	f.board.events.clear()
	_step(f, [_candidate(&"test_post", 0.0, "left_b"), _candidate(&"test_post", 4.0, "left_a")])
	check(post.starts == 2 and f.context._coordination_execution.selected_offer_key == "left_b", "At a real segment boundary Utility may select the same role's cheaper allowed alternative")
	check(f.board.events == ["report:moving", "prepare", "cancel:test_post", "clear", "begin:test_post", "commit"], "Switching allowed segments preserves pending acceptance through old execution cleanup")
	check(f.board.task.assignment_id == 5 and f.board.task.expires_at == original_deadline, "Changing the selected point retains assignment identity and its original deadline")
	_dispose(f)

func _test_real_escape_and_invalid() -> void:
	var f := _fixture()
	_accepted(f)
	var urgent := _candidate(&"test_escape", -9.0)
	urgent.urgent = true
	urgent.assignment_escape_verified = true
	_step(f, [urgent])
	check(f.ai.current_action == f.ai.actions[&"test_post"], "Caller urgent and forged verified labels cannot invent a self-preservation exception")
	# A retained action/route candidate may still carry a previous execution's
	# metadata. The verified personal escape must not prepare that old assignment.
	urgent.coordination_assignment = f.context._coordination_execution.duplicate(true)
	f.ai.actions[&"test_escape"].escape_allowed = true
	_step(f, [urgent])
	check(f.ai.current_action == f.ai.actions[&"test_escape"] and f.board.task.is_empty(), "An action-confirmed executable escape exits a valid assignment")
	check(f.board.reports.any(func(report): return report.state == &"self_preservation"), "Exiting for self-preservation explicitly releases the old team commitment")
	_dispose(f)
	f = _fixture()
	_accepted(f)
	var post = f.ai.actions[&"test_post"]
	post.contract.valid = false
	post.executable = false
	_step(f, [_candidate(&"test_personal", 3.0)])
	check(f.board.reports.any(func(report): return report.state == &"unavailable"), "A truly invalid execution contract reports unavailable instead of rejected moving feedback")
	check(f.ai.current_action == f.ai.actions[&"test_personal"] and f.board.task.is_empty(), "Real execution failure removes the old role restriction and permits individual recovery")
	_dispose(f)
	f = _fixture()
	_accepted(f)
	post = f.ai.actions[&"test_post"]
	post.contract.valid = false
	post.executable = false
	post.interruptible = false
	_step(f, [_candidate(&"test_personal", 0.0)])
	check(f.ai.current_action == post and post.cancels == 0, "Body interruption protection survives invalid contracts and missing assigned candidates")
	post.interruptible = true
	_step(f, [_candidate(&"test_personal", 0.0)])
	check(f.ai.current_action == f.ai.actions[&"test_personal"], "Once the actual protected body segment ends individual recovery may begin")
	_dispose(f)

func _test_transaction_failures() -> void:
	var f := _fixture()
	_step(f, [_candidate(&"test_personal", 0.0)])
	_assign(f)
	f.board.prepare_ok = false
	f.board.events.clear()
	_step(f, [_candidate(&"test_post", 1.0, "left_a")])
	check(f.ai.current_action == f.ai.actions[&"test_personal"] and f.board.events == ["prepare"], "A failed prepare does not cancel a still-running personal action")
	_dispose(f)
	for fail_commit in [false, true]:
		f = _fixture()
		_assign(f)
		f.ai.actions[&"test_post"].begin_ok = fail_commit
		f.board.commit_ok = not fail_commit
		_step(f, [_candidate(&"test_post", 1.0, "left_a")])
		check(f.ai.current_action == null and f.board.pending.is_empty() and f.board.task.is_empty(), "Failed %s releases pending task and local execution" % ("commit" if fail_commit else "begin"))
		check(f.board.events.has("rollback") and not f.board.accepted_lease and f.context._coordination_execution.is_empty(), "Failed %s publishes no accepted lease or fake executing role" % ("commit" if fail_commit else "begin"))
		_dispose(f)

func _test_expiry_and_completion() -> void:
	var f := _fixture()
	_accepted(f)
	f.board.elapsed = 14.1
	_step(f, [_candidate(&"test_personal", 0.0)])
	check(f.ai.current_action == f.ai.actions[&"test_personal"] and f.context._coordination_execution.is_empty(), "A fixed expired assignment does not silently renew or keep restricting the actor")
	_dispose(f)
	f = _fixture()
	_accepted(f)
	var complete := {"valid": true, "complete": true, "segment_boundary": true,
		"remaining_seconds": 0.0, "progress": 1.0, "ready_for_phase": false,
		"checked_points": PackedVector3Array([Vector3(1, 0, 2)])}
	f.board.events.clear()
	check(f.context.report_coordination_execution(complete), "Valid completion evidence is reported before action cancellation")
	f.ai._cancel_utility_execution(&"finished")
	check(f.board.events == ["report:complete", "cancel:test_post", "clear"], "Completion cleanup does not overwrite a real completed report with unavailable")
	check(f.board.reports.back().checked_points == complete.checked_points, "Observed completion samples pass through the generic value protocol unchanged")
	_dispose(f)
