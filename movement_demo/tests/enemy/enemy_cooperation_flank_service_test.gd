extends SceneTree

const Board = preload("res://scripts/enemy/services/enemy_cooperation.gd")
const FlankRoute = preload("res://scripts/enemy/services/enemy_flank_route.gd")
var board
var members: Array = []
var checks := 0
var failures := 0

# These doubles exercise the service protocol without navigation, weapon timing
# or saved scene settings. Autonomous movement/fire is covered by runtime tests.
class TestAmmo extends RefCounted:
	var is_reloading := false
	var magazine_rounds := 40

class TestWeapon extends RefCounted:
	var shot_interval := 0.2

class TestFire extends RefCounted:
	var actor
	var burst_shot_count := 40
	var fire_burst_shots := 0
	var fire_while_moving := true
	func burst_window_seconds(_support_intent: bool = false) -> float:
		# Preserve this protocol fixture's original 40-shot, 0.2-second cadence.
		# Real cadence multipliers and support bursts belong to fire runtime tests.
		if actor.ammo.is_reloading: return 0.0
		return mini(actor.ammo.magazine_rounds, maxi(0, burst_shot_count - fire_burst_shots)) * actor.weapon.shot_interval

class TestActor extends Node3D:
	var move_speed := 2.0
	var faction_id: StringName = &"enemy"
	var communication_group: StringName = &""
	var is_dead := false
	var shooting_enabled := true
	var melee_active := false
	var vaulting := false
	var ammo := TestAmmo.new()
	var weapon := TestWeapon.new()
	func can_use_firearms() -> bool: return true
	func is_vaulting() -> bool: return vaulting

class TestContext extends RefCounted:
	var actor
	var cooperation
	var fire := TestFire.new()
	var utility_horizon_seconds := 4.0
	var utility_current: Dictionary = {}
	var enabled := true
	var target_id := 101
	var known := Vector3.ZERO
	var evidence_until := 1000.0
	var sees_player := true
	var last_seen_position: Vector3:
		get: return known
	var last_seen_aim_position: Vector3:
		get: return known + Vector3.UP
	var last_seen_direction := Vector3.ZERO
	var observed_velocity := Vector3.ZERO
	var observed_reload_remaining := 0.0
	var evidence_elapsed_seconds: float:
		get: return cooperation.elapsed
	func cooperation_enabled() -> bool: return enabled and not actor.is_dead
	func can_use_action(id: StringName) -> bool: return enabled or id != &"cooperate"
	func cooperation_target_id() -> int: return target_id
	func cooperation_target_evidence() -> Dictionary:
		return {"target_id": target_id, "position": known, "valid_until": evidence_until}
	func cooperation_snapshot() -> Dictionary: return cooperation.snapshot(self, target_id)
	func setting(_section: StringName, _key: StringName, fallback: Variant = null) -> Variant: return fallback

func _initialize() -> void:
	_run.call_deferred()

func _team(count: int) -> void:
	for member in members: member.actor.free()
	members.clear()
	board = Board.new()
	for index in count:
		var actor := TestActor.new()
		root.add_child(actor)
		actor.position = Vector3(-6.0, 0.0, (index - (count - 1) * 0.5) * 1.5)
		var member := TestContext.new()
		member.actor = actor
		member.fire.actor = actor
		member.cooperation = board
		members.append(member)
		board.register(member)
		_publish(member)

func _publish(member, extra: Dictionary = {}) -> void:
	var status := {"target_id": member.target_id, "position": member.actor.position, "ready": false,
		"moving": false, "reloading": false, "support_seconds": 0.0, "firearms": true, "lane_id": &"target"}
	status.merge(extra, true)
	board.publish_status(member, status)

func _task(member, point: Vector3, duration: float = 12.0) -> Dictionary:
	var opportunity: Dictionary = board.flank_opportunity(member)
	return {"kind": &"flank", "owner_action": &"cooperate", "target_id": member.target_id,
		"position": point, "lane_id": "flank:%s" % str(point), "duration": duration,
		"flank_round_id": opportunity.round_id, "flank_anchor": opportunity.anchor,
		"flank_axis": opportunity.front_axis, "flank_destination": point}

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	for count in [1, 2, 3, 4, 6]:
		_team(count)
		var before: int = board.revision
		var serial: int = board._serial
		var opportunity: Dictionary = board.flank_opportunity(members[0])
		for repeat in 20: board.flank_opportunity(members[0])
		_check(board.revision == before and board._serial == serial and board._flank_rounds.is_empty(), "%d members: repeated previews never create or renew a round" % count)
		var expected := floori(count / 2.0)
		_check(opportunity.capacity == expected and opportunity.remaining_slots == expected, "%d members: capacity is floor(N/2)" % count)
		var proposals: Array[Dictionary] = []
		for index in count: proposals.append(_task(members[index], Vector3(6, 0, index * 2.0)))
		var accepted := 0
		for index in count:
			var token: Dictionary = board.claim(members[index], proposals[index])
			if not token.is_empty(): accepted += 1
		_check(accepted == expected, "%d members: concurrent proposals cannot overbook the opposite side" % count)

	_team(4)
	var first: Dictionary = board.claim(members[0], _task(members[0], Vector3(6, 0, -2)))
	var second: Dictionary = board.claim(members[1], _task(members[1], Vector3(6, 0, 2)))
	var anchor: Vector3 = first.flank_anchor
	var axis: Vector3 = first.flank_axis
	var deadline: float = first.expires_at
	var before_phase: int = board.revision
	board.update_claim(members[0], first, {"phase": &"WAIT", "position": Vector3(5, 0, 0), "flank_anchor": Vector3.ONE,
		"flank_axis": Vector3.RIGHT, "flank_round_id": -1, "flank_destination": Vector3.ONE, "expires_at": 9999.0, "ready": true})
	var copy: Dictionary = board._claims[first.id]
	_check(copy.flank_anchor == anchor and copy.flank_axis == axis and copy.flank_round_id == first.flank_round_id and copy.flank_destination == first.flank_destination and copy.expires_at == deadline, "updates cannot replace immutable side, destination, identity or deadline")
	_check(copy.position == Vector3(5, 0, 0) and board.revision > before_phase and board.snapshot(members[2], 101).supports.is_empty(), "phase changes invalidate role previews while progress cannot fabricate support")
	board.update_claim(members[1], second, {"phase": &"MOVE"})
	_check(board.flank_opportunity(members[2]).remaining_slots == 0, "waiting and moving both consume capacity")
	members[0].actor.position = first.flank_destination
	_publish(members[0])
	board.update_claim(members[0], first, {"phase": &"HOLD"})
	var holding: Dictionary = board.flank_opportunity(members[2])
	_check(holding.front_axis == axis and holding.anchor == anchor and holding.remaining_slots == 0, "arrival keeps the frozen axis and does not release a hold slot")
	board.release(members[0], first)
	_check(board.flank_opportunity(members[2]).remaining_slots == 0, "a completed member physically on the opposite side still consumes capacity")
	members[1].actor.position = second.flank_destination
	_publish(members[1])
	board.release(members[1], second)
	_check(board.claim(members[2], _task(members[2], Vector3(6, 0, 5))).is_empty(), "finishing both claims cannot dispatch the entire remaining front line")
	var frozen: Dictionary = board.flank_opportunity(members[2])
	_check(frozen.round_id == first.flank_round_id and frozen.expires_at == deadline, "a round remains finite and does not rotate after its last claim ends")

	_team(6)
	var task: Dictionary = _task(members[0], Vector3(6, 0, -3))
	var wrong := task.duplicate(true)
	wrong.flank_axis = -wrong.flank_axis
	_check(board.claim(members[0], wrong).is_empty() and board._flank_rounds.is_empty(), "a forged axis cannot create a round")
	wrong = task.duplicate(true)
	wrong.flank_destination = Vector3(-2, 0, 0)
	_check(board.claim(members[0], wrong).is_empty(), "a same-side destination is not an opposite flank")
	first = board.claim(members[0], task)
	_check(board.claim(members[1], _task(members[1], Vector3(6, 0, -2.5))).is_empty(), "nearby destinations conflict even when their position keys differ")
	second = board.claim(members[1], _task(members[1], Vector3(6, 0, 0)))
	_check(not second.is_empty() and second.flank_round_id == first.flank_round_id, "separated destinations share the same frozen round")
	var observed: Dictionary = board.snapshot(members[2], 101)
	_check(observed.requests.size() == 2 and observed.requests.all(func(request): return request.lane_id == &"target" and request.kind == &"flank") and observed.claims[0].lane_id != &"target", "flank claims expose target support demand without overwriting their exclusive lane")
	task.duration = 999.0
	var duplicate: Dictionary = board.claim(members[0], task)
	_check(duplicate.id == first.id and duplicate.expires_at == first.expires_at, "repeating a committed proposal returns the same token without renewal")

	_team(2)
	first = board.claim(members[0], _task(members[0], Vector3(6, 0, 0)))
	board.update_claim(members[0], first, {"position": Vector3(6, 0, 0), "phase": &"HOLD"})
	board.release(members[0], first)
	_check(board.flank_opportunity(members[1]).remaining_slots == 1, "self-reported progress cannot impersonate a body's actual arrival")
	var target_revision: int = board.revision
	members[1].target_id = 202
	_publish(members[1])
	_check(board.flank_opportunity(members[0]).capacity == 0 and board.revision > target_revision, "a different target neither supplies quota nor leaves the old preview revision unchanged")

	_team(4)
	first = board.claim(members[0], _task(members[0], Vector3(6, 0, -2)))
	second = board.claim(members[1], _task(members[1], Vector3(6, 0, 2)))
	members[1].actor.position = second.flank_destination
	_publish(members[1])
	members[2].actor.is_dead = true
	board.advance(0.0)
	_check(not board.update_claim(members[0], first, {}) and board.update_claim(members[1], second, {}), "population loss releases an unstarted departure before an already crossed member")
	_check(board.flank_opportunity(members[3]).capacity == 1 and board.flank_opportunity(members[3]).remaining_slots == 0, "three surviving members keep at most one dispatched slot")
	members[0].actor.is_dead = true
	members[3].actor.is_dead = true
	board.advance(0.0)
	_check(not board.update_claim(members[1], second, {}) and board._flank_rounds.is_empty(), "a sole survivor cannot retain a cooperation round")

	for change in [&"training", &"group", &"target", &"unregister", &"relation", &"reset", &"evidence", &"expiry"]:
		_team(4)
		first = board.claim(members[0], _task(members[0], Vector3(6, 0, -2), 1.0))
		match change:
			&"training": members[0].enabled = false
			&"group":
				members[0].actor.communication_group = &"elsewhere"
				board.register(members[0])
			&"target":
				members[0].target_id = 202
				_publish(members[0])
			&"unregister": board.unregister(members[0].actor.get_instance_id())
			&"relation": board.set_relation(&"enemy", &"outsider", &"neutral")
			&"reset": board.reset()
			&"evidence":
				for member in members: member.known = Vector3(0, 0, 3)
			&"expiry": board.advance(1.1)
		board.advance(0.0)
		_check(not board.update_claim(members[0], first, {}), "%s invalidates old ownership without extending its deadline" % change)
		if change == &"evidence":
			_check(board._flank_rounds.is_empty() and board.flank_opportunity(members[1]).anchor == Vector3(0, 0, 3), "material target displacement allows a new proposal instead of drifting the old axis")

	_team(2)
	board.release_member(members[0].actor.get_instance_id())
	first = board.claim(members[0], _task(members[0], Vector3(6, 0, 0)))
	_check(not first.is_empty() and board.flank_opportunity(members[1]).capacity == 1, "two living members can claim immediately after an ordinary execution switch clears firing status")
	_check(board.snapshot(members[1], 101).members.all(func(member): return member.id != members[0].actor.get_instance_id()), "roster continuity does not keep a cleared execution visible as fire support")
	board.release_member(members[1].actor.get_instance_id())
	_check(board.update_claim(members[0], first, {}), "the front member switching ordinary actions does not revoke the flanker's slot")
	board.advance(0.36)
	_check(not board.update_claim(members[0], first, {}) and board.flank_opportunity(members[1]).capacity == 0, "activity still expires when neither participant publishes execution again")

	_team(2)
	members[1].actor.communication_group = &"other"
	board.register(members[1])
	_publish(members[1])
	_check(board.flank_opportunity(members[0]).capacity == 0, "another communication group does not provide a flank slot")
	members[1].actor.communication_group = &""
	members[1].actor.faction_id = &"outsider"
	board.register(members[1])
	_publish(members[1])
	_check(board.flank_opportunity(members[0]).capacity == 0, "neutral units cannot inflate the quota")
	board.set_relation(&"enemy", &"outsider", &"allied")
	_check(board.flank_opportunity(members[0]).capacity == 1, "explicit allies use the existing sharing qualification")
	first = board.claim(members[0], _task(members[0], Vector3(6, 0, 0)))
	board.set_relation(&"enemy", &"outsider", &"hostile")
	_check(not board.update_claim(members[0], first, {}) and board.flank_opportunity(members[0]).capacity == 0, "relation revocation clears the round and its shared capacity")
	_team(2)
	members[1].actor.position = Vector3(6, 0, 0)
	_publish(members[1])
	_check(board.flank_opportunity(members[0]).capacity == 0, "units already on both sides do not start an opposite-side dispatch round")

	_test_completed_formation()
	_test_geometry_revision()
	_test_support_credit()
	_test_support_cycle()
	for member in members: member.actor.free()
	members.clear()
	print("COOPERATION FLANK SERVICE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _test_completed_formation() -> void:
	_team(2)
	members[0].actor.position = Vector3(5, 0, 0)
	members[1].actor.position = Vector3(6.5, 0, 0)
	for member in members: _publish(member)
	var opportunity: Dictionary = board.flank_opportunity(members[0])
	# Use the real route proposal's 140-degree endpoint, not an ideal 180-degree
	# antipode: both endpoints still fit in a centroid-derived half-plane.
	var proposals: Array = FlankRoute.proposals(members[0], opportunity)
	_check(not proposals.is_empty(), "the real route helper supplies a finite opposite-flank endpoint")
	if proposals.is_empty(): return
	var first: Dictionary = board.claim(members[0], _task(members[0], proposals[0].position, 1.0))
	_check(not first.is_empty(), "the initially concentrated pair can commit the real flank proposal")
	if first.is_empty(): return
	members[0].actor.position = first.flank_destination
	_publish(members[0])
	board.release(members[0], first)
	board.advance(1.1)
	for member in members: _publish(member)
	_check(board._flank_rounds.is_empty() and board._claims.is_empty(), "completed formation protection never renews an expired round or claim")
	var revision: int = board.revision
	var serial: int = board._serial
	var after: Dictionary = board.flank_opportunity(members[1])
	_check(after.capacity == 0 and after.remaining_slots == 0, "a completed 140-degree flank cannot rotate the front axis into a second dispatch after expiry")
	_check(board.claim(members[1], _task(members[1], Vector3(-6, 0, 0))).is_empty(), "the remaining front member cannot claim a follow-up behind the completed flanker")
	_check(board.revision == revision and board._serial == serial and board._flank_rounds.is_empty(), "rejecting an already separated formation remains a read-only geometry decision")
	for member in members:
		member.known = Vector3(0, 0, 10)
		_publish(member)
	var relocated: Dictionary = board.flank_opportunity(members[1])
	_check(relocated.capacity == 1 and relocated.anchor == Vector3(0, 0, 10), "a materially relocated known target permits a new round when both bodies are on its same side again")
	for index in members.size():
		members[index].known = Vector3.ZERO
		members[index].actor.position = Vector3(5, 0, (index - 0.5) * 1.5)
		_publish(members[index])
	var regrouped: Dictionary = board.flank_opportunity(members[0])
	var next: Dictionary = board.claim(members[0], _task(members[0], Vector3(-5, 0, 0)))
	_check(regrouped.capacity == 1 and not next.is_empty() and next.flank_round_id != first.flank_round_id, "physically regrouping can create a distinct finite round without reviving old ownership")
	for angle in [119.0, 121.0]:
		_team(2)
		members[0].actor.position = Vector3(5, 0, 0)
		members[1].actor.position = Vector3(5, 0, 0).rotated(Vector3.UP, deg_to_rad(angle))
		for member in members: _publish(member)
		var expected := 1 if angle < 120.0 else 0
		_check(board.flank_opportunity(members[0]).capacity == expected, "the default separation guard distinguishes %.0f-degree same-half formations" % angle)

func _test_geometry_revision() -> void:
	_team(1)
	_check(board.flank_geometry_revision(members[0]) == 0, "a lone registered member has no flank geometry revision")
	_team(3)
	var fingerprint: int = board.flank_geometry_revision(members[0])
	var serial: int = board._serial
	var revision: int = board.revision
	for repeat in 8: board.flank_geometry_revision(members[0])
	_check(board._serial == serial and board.revision == revision and board._flank_rounds.is_empty(), "geometry revision queries never register, claim or refresh a report")
	for repeat in 9: board.publish_visual(members[repeat % members.size()])
	_check(board.revision > revision and board.flank_geometry_revision(members[0]) == fingerprint, "alternating observers can update reports without clearing unchanged spatial geometry")
	_publish(members[1], {"ready": true, "support_seconds": 2.0})
	_publish(members[2], {"support_cycle_valid": true, "support_resume_seconds": 0.8})
	_check(board.flank_geometry_revision(members[0]) == fingerprint, "ready fire and legal burst pauses reprice candidates without rebuilding their geometry")
	board.advance(0.1)
	for member in members: _publish(member)
	_check(board.flank_geometry_revision(members[0]) == fingerprint, "fresh activity timestamps do not act as geometric invalidations")
	members[1].actor.position.x += 0.1
	_publish(members[1])
	_check(board.flank_geometry_revision(members[0]) == fingerprint, "sub-cell ally motion preserves the queue while execution still reads exact positions")
	members[1].actor.position.x += 0.5
	_publish(members[1])
	_check(board.flank_geometry_revision(members[0]) != fingerprint, "a half-metre formation change rebuilds the affected spatial queue")
	fingerprint = board.flank_geometry_revision(members[0])
	for member in members: member.known.x += 0.05
	_check(board.flank_geometry_revision(members[0]) == fingerprint, "sub-cell report motion does not turn every visual update into a rebuild")
	for member in members: member.known.x += 0.5
	_check(board.flank_geometry_revision(members[0]) != fingerprint, "a changed known target cell invalidates geometry without reading the live hidden target")
	_team(2)
	fingerprint = board.flank_geometry_revision(members[0])
	board.release_member(members[1].actor.get_instance_id())
	_check(board.flank_geometry_revision(members[0]) == fingerprint, "ordinary action switching preserves fresh participant geometry")
	var token: Dictionary = board.claim(members[0], _task(members[0], Vector3(6, 0, 0)))
	_check(not token.is_empty() and board.flank_geometry_revision(members[0]) != fingerprint, "a committed round and occupied slot invalidate the prior free-slot geometry")
	fingerprint = board.flank_geometry_revision(members[0])
	board.update_claim(members[0], token, {"phase": &"WAIT", "progress": 0.2})
	board.update_claim(members[0], token, {"phase": &"MOVE", "progress": 0.3})
	_check(board.flank_geometry_revision(members[0]) == fingerprint, "WAIT-to-MOVE text and progress keep an unchanged destination and quota stable")
	board.release(members[0], token)
	_check(board.flank_geometry_revision(members[0]) != fingerprint, "releasing a slot invalidates geometry even when no body has moved")
	members[1].actor.position.x = 0.49
	_publish(members[1])
	fingerprint = board.flank_geometry_revision(members[0])
	members[1].actor.position.x = 0.51
	_publish(members[1])
	_check(board.flank_geometry_revision(members[0]) != fingerprint and board.flank_opportunity(members[0]).remaining_slots == 0, "actual opposite-plane crossing invalidates quota inside the same quantized position cell")
	fingerprint = board.flank_geometry_revision(members[0])
	board.advance(12.1)
	for member in members: _publish(member)
	_check(board._flank_rounds.is_empty() and board.flank_geometry_revision(members[0]) != fingerprint, "expired finite rounds are not retained by the geometric fingerprint")
	for invalidation in [&"dead", &"group", &"target", &"stale", &"evidence"]:
		_team(2)
		match invalidation:
			&"dead": members[1].actor.is_dead = true
			&"group": members[1].actor.communication_group = &"other"
			&"target": members[1].target_id = 202
			&"stale": board.advance(0.36)
			&"evidence": members[0].evidence_until = 0.0
		_check(board.flank_geometry_revision(members[0]) == 0, "%s eligibility changes invalidate geometry using live full qualifications" % invalidation)

func _test_support_credit() -> void:
	_team(2)
	var provider = members[0]
	var recipient = members[1]
	_publish(provider, {"ready": true, "support_seconds": 4.0})
	var advance: Dictionary = board.claim(recipient, {"kind": &"advance", "owner_action": &"cooperate", "position": Vector3(2, 0, 3), "lane_id": &"position", "duration": 3.0})
	var stationary := {"outcome": {"unavailable_seconds": 0.0}, "destination": {}}
	var moving := {"outcome": {"unavailable_seconds": 0.0}, "destination": {"position": provider.actor.position + Vector3.RIGHT * 2.0}}
	var moving_hide := {"outcome": {"unavailable_seconds": 0.0}, "destination": {"hide": provider.actor.position + Vector3.RIGHT * 2.0}}
	var stationary_hide := {"outcome": {"unavailable_seconds": 0.0}, "destination": {"hide": provider.actor.position}}
	_check(board.candidate_seconds(provider, stationary) > 0.0 and is_zero_approx(board.candidate_seconds(provider, moving)), "only the stationary ordinary option can claim stationary advance-cover credit")
	_check(is_zero_approx(board.candidate_seconds(provider, moving_hide)), "a hide-only cover transfer cannot impersonate stationary advance support")
	_check(board.candidate_seconds(provider, stationary_hide) > 0.0, "a hide-only destination at the actual current body position preserves stationary support")
	board.release(recipient, advance)
	recipient.actor.ammo.is_reloading = true
	_publish(recipient, {"reloading": true, "reload_seconds": 3.0})
	_check(board.candidate_seconds(provider, moving) > 0.0, "permitted moving fire can still cover a real reload request")
	_check(board.candidate_seconds(provider, moving_hide) > 0.0, "a real hide-only transfer retains permitted moving reload-cover credit")
	provider.fire.fire_while_moving = false
	_check(is_zero_approx(board.candidate_seconds(provider, moving)), "disallowed moving fire cannot inherit the current stationary firing window")
	_check(is_zero_approx(board.candidate_seconds(provider, moving_hide)), "a hide-only transfer cannot inherit stationary fire when moving fire is disabled")
	provider.fire.fire_while_moving = true
	recipient.actor.ammo.is_reloading = false
	_publish(recipient, {"support_request": {"kind": &"retreat", "duration": 3.0}})
	_check(board.candidate_seconds(provider, moving) > 0.0, "permitted moving fire retains retreat-cover value")
	_publish(recipient, {"support_request": {"kind": &"flank", "duration": 3.0}})
	_check(is_zero_approx(board.candidate_seconds(provider, moving)), "opposite-flank requests require stationary cover too")
	provider.actor.ammo.magazine_rounds = 0
	_check(is_zero_approx(board.candidate_seconds(provider, stationary)), "an empty magazine never promises stationary support")

func _test_support_cycle() -> void:
	_team(2)
	var provider = members[0]
	var observer = members[1]
	_publish(provider, {"support_cycle_valid": true, "support_resume_seconds": 0.8})
	board.advance(0.2)
	var snapshot: Dictionary = board.snapshot(observer, 101)
	var member: Dictionary = snapshot.members.filter(func(value): return value.id == provider.actor.get_instance_id())[0]
	_check(member.support_cycle_valid and is_equal_approx(member.support_resume_seconds, 0.6) and not member.ready and snapshot.supports.is_empty(), "a burst-pause estimate ages without becoming present firing support")
	for blocker in [&"reload", &"empty", &"shooting", &"vault", &"melee"]:
		provider.actor.ammo.is_reloading = blocker == &"reload"
		provider.actor.ammo.magazine_rounds = 0 if blocker == &"empty" else 40
		provider.actor.shooting_enabled = blocker != &"shooting"
		provider.actor.vaulting = blocker == &"vault"
		provider.actor.melee_active = blocker == &"melee"
		snapshot = board.snapshot(observer, 101)
		member = snapshot.members.filter(func(value): return value.id == provider.actor.get_instance_id())[0]
		_check(not member.support_cycle_valid and member.support_resume_seconds < 0.0 and not member.ready and snapshot.supports.is_empty(), "%s immediately revokes an old pause-recovery estimate" % blocker)
