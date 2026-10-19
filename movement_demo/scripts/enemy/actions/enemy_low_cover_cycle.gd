extends RefCounted

## One finite crouch/stand/burst/crouch sequence owned by the existing cover action.
## Fire timing and actual shots remain owned by the common fire controller.
enum Phase { NONE, APPROACH, HIDE, RISE, FIRE, DUCK }
var context
var phase := Phase.NONE
var remaining := 0.0
var shots_left := 0
var _hide_seconds := 0.0

func reset() -> void:
	phase = Phase.NONE
	remaining = 0.0
	shots_left = 0

func begin(shared_context, hide_seconds: float) -> void:
	context = shared_context
	_hide_seconds = maxf(0.0, hide_seconds)
	shots_left = maxi(1, context.fire.burst_shots_remaining())
	phase = Phase.APPROACH

func active() -> bool:
	return phase != Phase.NONE

func tick(delta: float, arrived: bool, visible: bool, watch_seconds: float) -> void:
	var actor = context.actor
	# Equipment may be removed between a selected plan and its next body tick.
	# Never dereference the old weapon or keep a stale attack request alive.
	if not actor.can_use_firearms(): phase = Phase.DUCK
	if phase == Phase.DUCK:
		if actor.is_crouching(): phase = Phase.NONE
		return
	if phase == Phase.APPROACH:
		if arrived:
			phase = Phase.HIDE
			remaining = _hide_seconds
		return
	if phase == Phase.HIDE:
		if actor.is_crouching(): remaining = maxf(0.0, remaining - delta)
		if remaining <= 0.0 and actor.is_crouching():
			phase = Phase.RISE
			remaining = maxf(watch_seconds, actor.posture_seconds * 2.0)
	elif phase == Phase.RISE:
		remaining -= delta
		if actor.body_motion.amount <= 0.0001:
			phase = Phase.FIRE
			remaining = maxf(0.1, watch_seconds) + context.fire.fire_reaction_seconds + maxf(context.fire.fire_pause_remaining, context.fire.shot_wait_seconds())
			remaining += maxf(0.0, shots_left - 1) * context.fire.shot_interval_seconds() + actor.weapon.stabilize_seconds
		elif remaining <= 0.0: phase = Phase.DUCK
	elif phase == Phase.FIRE:
		remaining -= delta
		if shots_left <= 0 or remaining <= 0.0 or not visible or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading:
			phase = Phase.DUCK

func crouch_requested() -> bool:
	return phase in [Phase.HIDE, Phase.DUCK, Phase.NONE]

func fire_requested() -> bool:
	return phase == Phase.FIRE

func on_shot_fired() -> void:
	if phase == Phase.FIRE: shots_left = maxi(0, shots_left - 1)

func committed() -> bool:
	return phase in [Phase.HIDE, Phase.RISE, Phase.FIRE, Phase.DUCK]

func label() -> String:
	return ["", "前往半身掩体", "半身掩体后蹲藏", "掩体后起身", "掩体后射击", "蹲回半身掩体"][phase]
