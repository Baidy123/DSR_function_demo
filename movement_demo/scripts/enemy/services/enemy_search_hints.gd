extends RefCounted

## 只计算提示概率和单个误差样本；不持有玩家、动作或导航状态。
enum SearchHintDecayMode {
	NONE,
	LINEAR_TIME,
	EXPONENTIAL_TIME,
	LINEAR_DISTANCE,
	TIME_AND_DISTANCE,
	CUSTOM
}

func chance(base: float, mode: int, elapsed_seconds: float, displacement: float, minimum_multiplier: float, linear_seconds: float, half_life: float, distance_falloff: float, custom: Callable) -> float:
	if base <= 0.0:
		return 0.0

	var elapsed: float = maxf(0.0, elapsed_seconds)
	var player_displacement: float = displacement

	var minimum: float = clampf(minimum_multiplier, 0.0, 1.0)
	var multiplier: float = 1.0

	match mode:
		SearchHintDecayMode.NONE:
			multiplier = 1.0

		SearchHintDecayMode.LINEAR_TIME:
			var t: float = clampf(elapsed / maxf(0.01, linear_seconds), 0.0, 1.0)
			multiplier = lerpf(1.0, minimum, t)

		SearchHintDecayMode.EXPONENTIAL_TIME:
			multiplier = pow(0.5, elapsed / maxf(0.01, half_life))

		SearchHintDecayMode.LINEAR_DISTANCE:
			var distance_ratio: float = clampf(player_displacement / maxf(0.01, distance_falloff), 0.0, 1.0)
			multiplier = lerpf(1.0, minimum, distance_ratio)

		SearchHintDecayMode.TIME_AND_DISTANCE:
			var time_multiplier: float = pow(0.5, elapsed / maxf(0.01, half_life))
			var combined_distance_ratio: float = clampf(player_displacement / maxf(0.01, distance_falloff), 0.0, 1.0)
			var distance_multiplier: float = lerpf(1.0, minimum, combined_distance_ratio)
			multiplier = time_multiplier * distance_multiplier

		SearchHintDecayMode.CUSTOM:
			multiplier = custom.call(elapsed, player_displacement)

	multiplier = clampf(multiplier, minimum, 1.0)
	return clampf(base * multiplier, 0.0, 1.0)


func sample(position: Vector3, error_radius: float) -> Vector3:
	if error_radius <= 0.0: return position
	var angle := randf_range(0.0, TAU)
	var radius := sqrt(randf()) * error_radius
	return position + Vector3(cos(angle), 0.0, sin(angle)) * radius
