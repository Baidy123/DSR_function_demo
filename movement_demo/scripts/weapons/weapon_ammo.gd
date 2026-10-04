extends RefCounted

# 每把枪独立的运行状态；共享资源只提供配置，同类玩家武器引用同一备弹池。
var weapon: WeaponData
var magazine_rounds: int = 0
var is_reloading: bool = false
var reload_progress: float = 0.0
## 可选的已完成阶段；暂停后仍禁止开火。具体保留门槛由调用者决定。
var reload_checkpoint: float = 0.0
var infinite_reserve: bool = false
var _reserve_pool: Dictionary


func _init(data: WeaponData = null, reserve_pool: Dictionary = {}, unlimited: bool = false) -> void:
	weapon = data
	_reserve_pool = reserve_pool
	infinite_reserve = unlimited
	magazine_rounds = maxi(1, weapon.magazine_capacity) if _uses_ammo() else 0


func _uses_ammo() -> bool:
	return weapon != null and weapon.fire_mode != WeaponData.FireMode.MELEE


func reserve_count() -> int:
	return maxi(0, int(_reserve_pool.get(weapon.ammo_type, 0))) if _uses_ammo() else 0


func can_fire() -> bool:
	return _uses_ammo() and not is_reloading and reload_checkpoint <= 0.0 and magazine_rounds > 0


func consume_round() -> bool:
	if not can_fire():
		return false
	magazine_rounds -= 1
	return true


func can_reload() -> bool:
	if not _uses_ammo() or is_reloading:
		return false
	# 收起期间共享备弹可能被另一把枪用完，仍须允许完成已经保留的阶段并解除禁射。
	return reload_checkpoint > 0.0 or (magazine_rounds < maxi(1, weapon.magazine_capacity) and (infinite_reserve or reserve_count() > 0))


func start_reload() -> bool:
	if not can_reload():
		return false
	is_reloading = true
	reload_progress = reload_checkpoint
	return true

## 暂停只保留调用者指定的已完成阶段，不补弹、不扣备弹、不后台计时。
func suspend_reload(checkpoint: float) -> void:
	if not is_reloading: return
	reload_checkpoint = clampf(checkpoint, 0.0, reload_progress)
	if is_equal_approx(checkpoint, reload_progress): reload_checkpoint = checkpoint
	reload_progress = reload_checkpoint
	is_reloading = false


# 只累计进度；何时开始/中断由玩家输入或AI决定。
func advance_reload(delta: float, speed_multiplier: float = 1.0) -> void:
	if not _uses_ammo():
		cancel_reload()
		return
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
	reload_checkpoint = 0.0
