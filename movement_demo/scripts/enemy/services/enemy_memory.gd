extends RefCounted

enum State { IDLE, APPROACH, INVESTIGATE, SEARCH, DEAD, PATROL, REPOSITION, HOLD_POSITION, TRACK }
enum CombatType { MELEE, RANGED }
var state: State = State.IDLE
var last_known_position: Vector3 = Vector3.INF
var last_seen_position: Vector3 = Vector3.INF
var last_seen_direction := Vector3.ZERO
var observed_velocity := Vector3.ZERO
var has_visual_memory := false
var is_alerted := false
var was_seeing_player := false
var sees_player := false
var noise_search_origin := Vector3.INF
var recent_damage_pressure := 0.0
var nearby_shot_pressure := 0.0
var utility_unseen_seconds := 0.0
var utility_threat_age_seconds := 0.0
var utility_suppression_pending := false
var utility_rejected_attack_points: Array[Vector3] = []
var blocked_destinations: Array[Dictionary] = []
var patrol_pause_timer := 0.0
var investigation_hint_allowed := false
