extends CanvasLayer

const Ammo = preload("res://scripts/weapons/weapon_ammo.gd")
## 主武器槽，按数字1选择；在这里拖入 WeaponData，空槽不会被切换选中。
@export var primary_weapon: WeaponData
## 副武器槽，按数字2选择；只装备枪械，专用近战武器仅供近战兵使用。
@export var secondary_weapon: WeaponData
## 出生时使用哪个槽；该槽为空时自动选择另一个非空槽。
@export_enum("主武器:0", "副武器:1") var starting_slot: int = 0

@export_group("初始共享备弹")
## 同弹药类型的主副武器共用此备弹；初始满弹匣不从备弹扣除。
@export_range(0, 9999, 1) var starting_rifle_ammo: int = 36
## 手枪备弹初值，重新开始恢复；运行余量在reserve_ammo中。
@export_range(0, 9999, 1) var starting_pistol_ammo: int = 36
## 冲锋枪备弹初值。
@export_range(0, 9999, 1) var starting_smg_ammo: int = 36
## 霰弹枪备弹初值。
@export_range(0, 9999, 1) var starting_shotgun_ammo: int = 36
var reserve_ammo: Dictionary = {}
var _ammo_states: Array = [null, null]
var _reload_modes: Array[bool] = [false, false]

var active_slot: int = -1
# 两把枪分别保留精度；收起期间不自动恢复，防止反复切枪刷新惩罚。
var _aim_states: Array[Dictionary] = [{}, {}]

@onready var player = get_parent()
@onready var combat = get_parent().get_node("Combat")
@onready var primary_label: Label = $Panel/Content/Slots/Primary/Name
@onready var secondary_label: Label = $Panel/Content/Slots/Secondary/Name

func _ready() -> void:
	for data in [primary_weapon, secondary_weapon]:
		if data != null and data.fire_mode == WeaponData.FireMode.MELEE:
			push_warning("玩家武器槽误配专用近战武器，该槽按空槽处理。")
	reserve_ammo = {
		WeaponData.AmmoType.RIFLE: starting_rifle_ammo,
		WeaponData.AmmoType.PISTOL: starting_pistol_ammo,
		WeaponData.AmmoType.SMG: starting_smg_ammo,
		WeaponData.AmmoType.SHOTGUN: starting_shotgun_ammo,
	}
	# 与出生节点就绪顺序无关；此时 Player 自己的 onready 可能尚未执行。
	var initial: int = clampi(starting_slot, 0, 1)
	if _weapon_at(initial) == null:
		initial = 1 - initial
	if _weapon_at(initial) != null:
		_equip_slot(initial)
	else:
		combat.equip_weapon(null)
	_update_display()

func _process(_delta: float) -> void:
	$Panel.visible = not player.is_in_dialogue and not player.is_dead()
	_update_display()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var slot: int = -1
	if event.is_action_pressed("weapon_primary"):
		slot = 0
	elif event.is_action_pressed("weapon_secondary"):
		slot = 1
	elif event.is_action_pressed("weapon_next") or event.is_action_pressed("weapon_previous"):
		slot = 1 - active_slot if active_slot >= 0 else 0
	else:
		return
	if player.is_dead() or player.is_in_dialogue or get_tree().paused:
		return
	select_slot(slot)
	get_viewport().set_input_as_handled()

## 只切换正在使用的槽位，不修改槽内配置。场外也可以提前选择武器。
func select_slot(slot: int) -> bool:
	if slot < 0 or slot > 1 or player.is_dead() or player.is_in_dialogue or get_tree().paused or combat.is_melee_active():
		return false
	var data: WeaponData = _weapon_at(slot)
	if data == null or (slot == active_slot and combat.weapon == data):
		return false
	_equip_slot(slot)
	_update_display()
	return true

func _equip_slot(slot: int) -> void:
	if active_slot >= 0:
		_reload_modes[active_slot] = combat.is_slow_reload()
		_aim_states[active_slot] = {
			"weapon": combat.weapon,
			"accuracy": combat.accuracy,
			"delay": combat.accuracy_recovery_timer,
			"crouch_bonus_blocked": combat.crouch_bonus_blocked_until_recovery,
		}
	active_slot = slot
	var data: WeaponData = _weapon_at(slot)
	if _ammo_states[slot] == null or _ammo_states[slot].weapon != data:
		_ammo_states[slot] = Ammo.new(data, reserve_ammo)
		_reload_modes[slot] = false
	combat.equip_weapon(data, true, _ammo_states[slot], _reload_modes[slot])
	var saved: Dictionary = _aim_states[slot]
	if saved.get("weapon") == data:
		# 拔枪至多回到初始精度；已有更差的精度和恢复等待继续保留。
		combat.accuracy = minf(combat.accuracy, saved.accuracy)
		combat.accuracy_recovery_timer = saved.delay
		combat.crouch_bonus_blocked_until_recovery = combat.crouch_bonus_blocked_until_recovery or saved.get("crouch_bonus_blocked", false)

func _weapon_at(slot: int) -> WeaponData:
	var data: WeaponData = primary_weapon if slot == 0 else secondary_weapon
	return data if data == null or data.fire_mode != WeaponData.FireMode.MELEE else null


## 受击属于玩家；尚未拔出的武器也保存最低准度，避免切槽跳过惩罚。
func apply_melee_disruption() -> void:
	for slot in range(2):
		var data := _weapon_at(slot)
		if data == null: continue
		_aim_states[slot] = {"weapon": data, "accuracy": 0.0, "crouch_bonus_blocked": true,
			"delay": maxf(float(_aim_states[slot].get("delay", 0.0)), data.get_aim_settings(combat.is_using_spread_cone()).delay)}

func _update_display() -> void:
	var labels: Array[Label] = [primary_label, secondary_label]
	for slot in range(2):
		var data: WeaponData = _weapon_at(slot)
		var title: String = "主武器" if slot == 0 else "副武器"
		labels[slot].text = "%s%d  %s\n%s" % ["▶ " if slot == active_slot else "", slot + 1, title, data.display_name if data != null else "空"]
		if data != null:
			var state = _ammo_states[slot]
			var rounds: int = state.magazine_rounds if state != null and state.weapon == data else data.magazine_capacity
			labels[slot].text += "\n%d/%d · 备弹%d" % [rounds, data.magazine_capacity, reserve_ammo.get(data.ammo_type, 0)]
			if state != null and state.weapon == data and state.reload_checkpoint > 0.0 and slot != active_slot:
				labels[slot].text += "\n换弹已保留 50%"
		labels[slot].modulate = Color(1.0, 0.82, 0.35) if slot == active_slot else Color(0.7, 0.73, 0.78)
	$Panel/Content/Hint.text = "1 / 2 或滚轮切枪 · R换弹 · V近战"
	if combat.is_melee_active():
		$Panel/Content/Hint.text = "近战出手中 · 暂停射击、换弹与切枪"
	elif combat.ammo.is_reloading:
		var progress: int = floori(combat.ammo.reload_progress * 100.0)
		$Panel/Content/Hint.text = ("慢速换弹中 %d%% · 可跑" if combat.is_slow_reload() else "快速换弹中 %d%% · 奔跑会中断") % progress
	elif combat.ammo.reload_checkpoint > 0.0:
		$Panel/Content/Hint.text = "换弹暂停 50% · 停跑后继续"
