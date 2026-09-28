extends RefCounted

# 每把枪独立的运行状态；共享资源只提供配置，同类玩家武器引用同一备弹池。
var weapon: WeaponData
var magazine_rounds: int = 0
var is_reloading: bool = false
var reload_progress: float = 0.0
var infinite_reserve: bool = false
var _reserve_pool: Dictionary


func _init(data: WeaponData = null, reserve_pool: Dictionary = {}, unlimited: bool = false) -> void:
	weapon = data
	_reserve_pool = reserve_pool
	infinite_reserve = unlimited
	magazine_rounds = maxi(1, weapon.magazine_capacity) if weapon != null else 0


func reserve_count() -> int:
	return maxi(0, int(_reserve_pool.get(weapon.ammo_type, 0))) if weapon != null else 0


func can_fire() -> bool:
	return weapon != null and not is_reloading and magazine_rounds > 0


func consume_round() -> bool:
	if not can_fire():
		return false
	magazine_rounds -= 1
	return true


func can_reload() -> bool:
	if weapon == null or is_reloading or magazine_rounds >= maxi(1, weapon.magazine_capacity):
		return false
	return infinite_reserve or reserve_count() > 0


func start_reload() -> bool:
	if not can_reload():
		return false
	is_reloading = true
	reload_progress = 0.0
	return true


# 只累计进度；何时开始/中断由玩家输入或AI决定。
func advance_reload(delta: float, speed_multiplier: float = 1.0) -> void:
	if not is_reloading:
		return
	reload_progress = minf(1.0, reload_progress + maxf(0.0, delta) * maxf(0.0, speed_multiplier) / maxf(0.1, weapon.reload_seconds))
	if reload_progress < 1.0 and not is_equal_approx(reload_progress, 1.0):
		return
	var needed: int = maxi(0, weapon.magazine_capacity - magazine_rounds)
	var loaded: int = needed if infinite_reserve else mini(needed, reserve_count())
	magazine_rounds += loaded
	if not infinite_reserve:
		_reserve_pool[weapon.ammo_type] = reserve_count() - loaded
	cancel_reload()


func cancel_reload() -> void:
	is_reloading = false
	reload_progress = 0.0
