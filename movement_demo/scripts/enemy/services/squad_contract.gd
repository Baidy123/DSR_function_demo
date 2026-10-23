extends RefCounted

## Value contracts shared by the planner, coordinator and action executors.
## No scene references, mutable resources or personal Utility scores cross here.
const PERIOD := 0.2
const TASK_SECONDS := 16.0
const STATES := [&"pending", &"executing", &"waiting", &"blocked", &"occupied", &"complete", &"replaced"]
const OBSERVATION_MODES := [&"sweep", &"inspect"]
const SEARCH_STEP_FIELDS := ["coverage_key", "coverage_version", "geometry_version", "observation_samples", "observation_mode", "expected_area", "approach_look_position", "support_mode"]

static func same_task(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and [a.get("generation"), a.get("task_id"), a.get("version"), a.get("member_id"), a.get("profile_id")] == [b.get("generation"), b.get("task_id"), b.get("version"), b.get("member_id"), b.get("profile_id")]

static func task(identity: Dictionary, proposal: Dictionary, now: float) -> Dictionary:
	var value = proposal.duplicate(true)
	value.merge(identity, true)
	value.merge({"state": &"pending", "accepted": false, "issued_at": now,
		"expires_at": now + TASK_SECONDS, "check_at": now + PERIOD,
		"waiting_for": [], "reason": &"", "progress": 0.0,
		"completion": &"observed" if value.get("role") == &"search" else &"arrived",
		"failure_exit": &"coordinator_replan", "attack": &"personal_sight"}, true)
	if value.get("role") == &"search":
		value.observation_mode = value.get("observation_mode", &"inspect")
		value.observation_samples = value.get("observation_samples", PackedVector3Array([value.look_position]))
		value.future_steps = value.get("future_steps", [])
		value.resume = &"coordinator_revalidate"
	return value

static func template(profiles: Dictionary, identity: int) -> Dictionary:
	var roles = {}
	var members = {}
	var ids: Array = profiles.keys()
	ids.sort()
	for id in ids:
		var profile: Dictionary = profiles[id]
		members[id] = profile.profile_id
		for action in profile.actions:
			for role in profile.actions[action].roles:
				if not roles.has(role): roles[role] = []
				roles[role].append({"member_id": id, "action": action,
					"basis": profile.actions[action].basis, "profile_id": profile.profile_id})
	var missing: Array = []
	for role in [&"engage", &"search", &"support", &"flank", &"patrol"]:
		if not roles.has(role): missing.append(role)
	var defaults = {}
	var unassigned = ids.duplicate()
	# Complementary slots are matched over the assembled team. Scarce
	# executors are considered first; a lone survivor keeps direct engagement.
	if ids.size() > 1:
		for role in [&"support", &"flank"]:
			if unassigned.size() <= 1: break
			for option in roles.get(role, []):
				if profiles[option.member_id].actions[option.action].has("contact_motion"): continue
				if unassigned.has(option.member_id):
					defaults[option.member_id] = role
					unassigned.erase(option.member_id)
					break
	for id in unassigned: defaults[id] = &"engage" if not executor(profiles[id], &"engage").is_empty() else &"guard"
	return {"template_id": identity, "members": members, "roles": roles, "missing": missing, "contact_roles": defaults,
		"phases": {&"contact": [&"support", &"flank", &"engage"], &"search": [&"search", &"guard"], &"patrol": [&"patrol", &"guard"]}}

static func executor(profile: Dictionary, role: StringName) -> StringName:
	for id in profile.get("actions", {}):
		if profile.actions[id].has("contact_motion"): continue
		if profile.actions[id].roles.has(role): return id
	return &""

static func horizontal(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
