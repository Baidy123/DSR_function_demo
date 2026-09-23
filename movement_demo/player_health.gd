extends CanvasLayer

## 出生和重新开始时的最大生命；100 是当前试玩初值。
@export_range(1.0, 10000.0, 1.0) var max_health: float = 100.0
## 调试版无敌：阻止扣血，不回血或复活；release 导出中不生效。
@export var debug_invincible: bool = false:
	set(value):
		debug_invincible = value
		if is_node_ready():
			_update_display()

var health: float = 0.0
var is_dead: bool = false
var restart_pending: bool = false

@onready var player = get_parent()
@onready var health_label: Label = $Status/Content/HealthLabel
@onready var health_bar: ProgressBar = $Status/Content/HealthBar
@onready var stamina_bar: ProgressBar = $Status/Content/Stamina/Bar
@onready var stamina_label: Label = $Status/Content/Stamina/Label
@onready var invincible_toggle: CheckBox = $Debug/Controls/Invincible
@onready var damage_button: Button = $Debug/Controls/Damage
@onready var death_screen: ColorRect = $DeathScreen
@onready var restart_button: Button = $DeathScreen/Center/Panel/Content/Restart


func _ready() -> void:
	health = maxf(1.0, max_health)
	death_screen.hide()
	$Debug.visible = OS.is_debug_build()
	invincible_toggle.toggled.connect(_set_debug_invincible)
	$Debug/Controls/NoiseRanges.toggled.connect($NoiseRanges.set_enabled)
	damage_button.pressed.connect(_debug_damage)
	restart_button.pressed.connect(_request_restart)
	_update_display()
	_update_stamina_display()


func _process(_delta: float) -> void:
	# 对话框位于屏幕下方，对话时隐藏状态条以免挡住正文和选项。
	$Status.visible = not player.is_in_dialogue
	_update_stamina_display()


func _update_stamina_display() -> void:
	stamina_bar.max_value = player.MAX_STAMINA
	stamina_bar.value = player.stamina
	stamina_label.text = "体力 %d / %d" % [ceili(player.stamina), ceili(player.MAX_STAMINA)]
	if player.stamina_exhausted:
		stamina_label.text += "  恢复中"


func receive_hit(damage: float) -> void:
	if is_dead or not is_finite(damage) or damage <= 0.0:
		return
	if is_invincible():
		print("[玩家][无敌] 受到伤害：%.2f；无敌，未扣血；生命：%.2f / %.2f" % [damage, health, max_health])
		return
	var previous_health: float = health
	health = maxf(0.0, health - damage)
	print("[玩家][受击] 受到伤害：%.2f；实际扣血：%.2f；生命：%.2f → %.2f / %.2f" % [damage, previous_health - health, previous_health, health, max_health])
	if health <= 0.0:
		is_dead = true
		player.velocity = Vector3.ZERO
		player.current_speed = 0.0
		player.is_sprinting = false
		player.is_facing_npc = false
		if player.combat != null:
			player.combat.cancel_aim()
		# 暂停敌人和对话输入；本节点及重开按钮使用 Always，暂停时仍可点击。
		get_tree().paused = true
		death_screen.show()
		restart_button.grab_focus()
	_update_display()


func is_invincible() -> bool:
	return OS.is_debug_build() and debug_invincible


func _set_debug_invincible(enabled: bool) -> void:
	debug_invincible = enabled


func _debug_damage() -> void:
	if OS.is_debug_build():
		player.receive_hit(25.0)


func _update_display() -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	health_label.text = "生命 %d / %d" % [ceili(health), ceili(max_health)]
	if is_invincible():
		health_label.text += "  [无敌]"
	invincible_toggle.set_pressed_no_signal(is_invincible())
	damage_button.disabled = is_dead


func _request_restart() -> void:
	if not is_dead or restart_pending:
		return
	restart_pending = true
	restart_button.disabled = true
	# 避免在按钮信号或物理回调中释放当前场景。
	_restart.call_deferred()


func _restart() -> void:
	var tree: SceneTree = get_tree()
	# 仅重载场景；不清空 GameState 中的对话选择。
	var result: Error = tree.reload_current_scene()
	if result == OK:
		tree.paused = false
	else:
		restart_pending = false
		restart_button.disabled = false
		$DeathScreen/Center/Panel/Content/Message.text = "重新开始失败，请重试"
		push_error("无法重新加载当前场景：%s" % error_string(result))
