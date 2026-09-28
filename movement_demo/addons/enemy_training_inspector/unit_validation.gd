@tool
extends Label

var unit: EnemyUnitProfile
var signature := -1
var elapsed := 0.0

func _ready() -> void:
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.25:
		elapsed = 0.0
		_refresh()

func _refresh() -> void:
	if unit == null or unit.fingerprint() == signature: return
	signature = unit.fingerprint()
	var training := EnemyTrainingProfile.new()
	for definition in unit.tactical_actions:
		if definition != null: training.selected_tactics.append(definition.action_id)
	var result: Dictionary = preload("res://scripts/enemy/enemy_action_library.gd").resolve(unit, training)
	text = "\n".join(result.errors)
	visible = not text.is_empty()
