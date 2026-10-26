@tool
extends CanvasLayer

const Ammo = preload("res://scripts/weapons/weapon_ammo.gd")
## 主武器槽，按数字1选择；在这里拖入 WeaponData，空槽不会被切换选中。
@export var primary_weapon: WeaponData
## 副武器槽，按数字2选择；只装备枪械，专用近战武器仅供近战兵使用。
@export var secondary_weapon: WeaponData
## 出生时使用哪个槽；该槽为空时自动选择另一个非空槽。
@export_enum("主武器:0", "副武器:1") var starting_slot: int = 0

@export_group("医疗包")
## 像武器一样在装备节点挂载医疗资源；展开可调整回血量与使用时间，留空禁用。
@export var medkit: MedkitData = preload("res://resources/player/default_medkit.tres")
## 场景保存出生数量，远程检查器显示当前余量；库存属于装备实例，不写入资源。
@export_range(0, 999, 1) var medkit_count: int = 3:
	set(value):
		medkit_count = maxi(0, value)
		if Engine.is_editor_hint(): return
		var controller := get_node_or_null("Medkit")
		if controller != null and controller.is_node_ready():
			if medkit_count == 0: controller.cancel()
			controller.state_changed.emit()

@export_group("初始共享备弹")
## 每项为 AmmoSupply：弹药资源＋数量。未列出的新弹药备弹0，弹匣仍满匣出生。
## 检查器展示已解析的旧初值；显式0覆盖旧值，重复类型保留第一项并给出诊断。
@export var initial_ammo: Array[AmmoSupply]:
	get: return _resolved_initial_ammo()
	set(value): _initial_ammo = value
# 仅用于旧场景加载／继承，不再显示第二套可编辑配置。
@export_storage var starting_rifle_ammo: int = 36
@export_storage var starting_pistol_ammo: int = 36
@export_storage var starting_smg_ammo: int = 36
@export_storage var starting_shotgun_ammo: int = 36
var _initial_ammo: Array[AmmoSupply] = []
# 保持检查器展开条目的资源身份稳定，否则修改旧类型的 Amount 会写入临时对象。
var _legacy_supplies: Dictionary = {}
var _legacy_counts: Dictionary = {}
var _slot_weapons: Array = [null, null]
var _slot_definitions: Array = [null, null]
var _definitions: Dictionary = {}
var _conflicting_ammo: Dictionary = {}
var reserve_ammo: Dictionary = {}
var _ammo_states: Array = [null, null]
var _reload_modes: Array[bool] = [false, false]

var active_slot: int = -1
# 两把枪分别保留精度；收起期间不自动恢复，防止反复切枪刷新惩罚。
var _aim_states: Array[Dictionary] = [{}, {}]

@onready var player = get_parent()
@onready var combat = get_parent().get_node_or_null("Combat")
@onready var primary_label: Label = $Panel/Content/Slots/Primary/Name
@onready var secondary_label: Label = $Panel/Content/Slots/Secondary/Name

func _ready() -> void:
	if Engine.is_editor_hint(): return
	for data in [primary_weapon, secondary_weapon]:
		if data != null and data.fire_mode == WeaponData.FireMode.MELEE:
			push_warning("玩家武器槽误配专用近战武器，该槽按空槽处理。")
	_initialize_ammo()
	# 与出生节点就绪顺序无关；此时 Player 自己的 onready 可能尚未执行。
	var initial: int = clampi(starting_slot, 0, 1)
	if _weapon_at(initial) == null:
		initial = 1 - initial
	if _weapon_at(initial) != null:
		_equip_slot(initial)
	else:
		combat.equip_weapon(null)
	_update_display()

func _resolved_initial_ammo() -> Array[AmmoSupply]:
	var result: Array[AmmoSupply] = _initial_ammo.duplicate()
	var explicit: Dictionary = {}
	for supply in result:
		if supply != null and supply.ammo != null: explicit[supply.ammo.ammo_id] = true
	var legacy_counts := [starting_rifle_ammo, starting_pistol_ammo, starting_smg_ammo, starting_shotgun_ammo]
	for kind in range(4):
		var definition := AmmoDefinition.legacy(kind)
		if explicit.has(definition.ammo_id): continue
		var count := maxi(0, legacy_counts[kind])
		if not _legacy_supplies.has(kind):
			_legacy_supplies[kind] = AmmoSupply.create(definition, count)
		elif _legacy_counts.get(kind) != count:
			# 旧场景继承的保存字段可能晚于检查器首次读取；继续尊重保存覆盖顺序。
			_legacy_supplies[kind].amount = count
		_legacy_counts[kind] = count
		result.append(_legacy_supplies[kind])
	return result

func _initialize_ammo() -> void:
	reserve_ammo.clear()
	_definitions.clear()
	_conflicting_ammo.clear()
	for supply in initial_ammo:
		if supply == null or supply.ammo == null or not supply.ammo.has_valid_id():
			push_warning("Equipment：初始弹药条目缺少有效类型，请修正后重开。")
			continue
		_remember_definition(supply.ammo)
		var key := supply.ammo.ammo_id
		if reserve_ammo.has(key):
			push_warning("Equipment：初始弹药 %s 重复，保留第一项数量。" % key)
			continue
		reserve_ammo[key] = maxi(0, supply.amount)
	for slot in range(2): _bind_slot(slot)

func _remember_definition(definition: AmmoDefinition) -> void:
	var key := definition.ammo_id
	if _definitions.has(key) and not _definitions[key].same_definition(definition):
		if not _conflicting_ammo.has(key): push_warning("Equipment：弹药 %s 的同 ID 定义冲突，暂停该类型掉落。" % key)
		_conflicting_ammo[key] = true
	elif not _definitions.has(key):
		_definitions[key] = definition.duplicate()
	if not definition.has_valid_drop_range():
		push_warning("Equipment：弹药 %s 掉落范围无效，需要 1 <= 最小量 <= 最大量。" % key)

func _bind_slot(slot: int) -> void:
	var data := _weapon_at(slot)
	if data == _slot_weapons[slot]: return
	_slot_weapons[slot] = data
	var definition := data.get_ammo_definition() if data != null else null
	_slot_definitions[slot] = definition.duplicate() if definition != null else null
	if definition != null: _remember_definition(definition)

## 只读、按类型合并：共享备弹一次＋所有携带槽的真实匣内弹量。
## 尚未使用的槽计入出生满匣，但不创建状态、不切枪；同类型用最大弹匣判断缺弹。
func ammo_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var by_key: Dictionary = {}
	for slot in range(2):
		var data := _weapon_at(slot)
		if data == null: continue
		var definition: AmmoDefinition = _slot_definitions[slot] if data == _slot_weapons[slot] else data.get_ammo_definition()
		if definition == null or not definition.has_valid_id(): continue
		var key := definition.ammo_id
		if not by_key.has(key):
			var row := {"ammo": definition.duplicate(), "key": key, "total": maxi(0, int(reserve_ammo.get(key, 0))), "capacity": 0, "slot": slot, "conflict": _conflicting_ammo.has(key)}
			by_key[key] = row
			result.append(row)
		var row: Dictionary = by_key[key]
		if not row.ammo.same_definition(definition): row.conflict = true
		var state = _ammo_states[slot]
		row.total += maxi(0, state.magazine_rounds) if state != null and state.weapon == data else maxi(1, data.magazine_capacity)
		row.capacity = maxi(row.capacity, maxi(1, data.magazine_capacity))
	return result

## 只增加共享备弹，不补弹匣、不开始换弹、不改变已保存的换弹／瞄准状态。
## 掉落物传入生成时冻结的定义，资源热改不会把地上的包变成另一弹种。
func add_ammo(definition: AmmoDefinition, amount: int) -> int:
	if definition == null or not definition.has_valid_id() or amount <= 0: return 0
	if not is_inside_tree() or get_tree().paused or player.is_dead() or player.is_in_dialogue: return 0
	_remember_definition(definition)
	var key := definition.ammo_id
	reserve_ammo[key] = maxi(0, int(reserve_ammo.get(key, 0))) + amount
	_update_display()
	return amount

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	$Panel.visible = not player.is_in_dialogue and not player.is_dead()
	_update_display()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
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
		_bind_slot(slot)
		var definition: AmmoDefinition = _slot_definitions[slot]
		_ammo_states[slot] = Ammo.new(data, reserve_ammo, false, definition.ammo_id if definition != null else &"")
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


## 近战命中的同一已缩放损失也作用于收起的枪；不再绕过倍率强制清零。
func apply_stowed_accuracy_loss(loss: float) -> void:
	for slot in range(2):
		if slot == active_slot: continue
		var data := _weapon_at(slot)
		if data == null: continue
		var settings: Dictionary = data.get_aim_settings(combat.is_using_spread_cone())
		var saved: Dictionary = _aim_states[slot]
		var previous: float = saved.get("accuracy", settings.initial) if saved.get("weapon") == data else settings.initial
		_aim_states[slot] = {"weapon": data, "accuracy": maxf(0.0, previous - loss), "crouch_bonus_blocked": true,
			"delay": maxf(float(saved.get("delay", 0.0)), settings.delay)}

func _update_display() -> void:
	var labels: Array[Label] = [primary_label, secondary_label]
	for slot in range(2):
		var data: WeaponData = _weapon_at(slot)
		var title: String = "主武器" if slot == 0 else "副武器"
		labels[slot].text = "%s%d  %s\n%s" % ["▶ " if slot == active_slot else "", slot + 1, title, data.display_name if data != null else "空"]
		if data != null:
			var state = _ammo_states[slot]
			var rounds: int = state.magazine_rounds if state != null and state.weapon == data else data.magazine_capacity
			var definition: AmmoDefinition = _slot_definitions[slot]
			var key: StringName = definition.ammo_id if definition != null else &""
			labels[slot].text += "\n%d/%d · 备弹%d" % [rounds, data.magazine_capacity, reserve_ammo.get(key, 0)]
			if state != null and state.weapon == data and state.reload_checkpoint > 0.0 and slot != active_slot:
				labels[slot].text += "\n换弹已保留 50%"
		labels[slot].modulate = Color(1.0, 0.82, 0.35) if slot == active_slot else Color(0.7, 0.73, 0.78)
	$Panel/Content/Hint.text = "1 / 2 或滚轮切枪 · R换弹 · V近战"
	if combat.is_melee_active():
		$Panel/Content/Hint.text = "近战出手中 · 暂停射击、换弹与切枪"
	elif combat.ammo.is_reloading:
		var progress: int = floori(combat.ammo.reload_progress * 100.0)
		if combat.ammo.reloads_one_shell_at_a_time():
			$Panel/Content/Hint.text = ("慢速逐发装填 · 本发 %d%% · 可跑 · 右键中断" if combat.is_slow_reload() else "逐发装填 · 本发 %d%% · 右键或奔跑中断") % progress
		else:
			$Panel/Content/Hint.text = ("慢速换弹中 %d%% · 可跑" if combat.is_slow_reload() else "快速换弹中 %d%% · 奔跑会中断") % progress
	elif combat.ammo.reload_checkpoint > 0.0:
		$Panel/Content/Hint.text = "换弹暂停 50% · 停跑后继续"
