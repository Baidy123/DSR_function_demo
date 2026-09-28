@tool
extends Resource
class_name NoiseData

## 听觉事件配置；不保存单次声源位置或播放进度，可供多个发声者共用。
@export var display_name: String = "声音"
## 声源与敌人之间有墙或其他实体遮挡时，听觉半径乘此倍率。
## 第一版只区分有无遮挡，不累计墙层数或模拟绕射。
@export_range(0.0, 1.0, 0.05) var occluded_range_multiplier: float = 0.4
## 预留实际音效资源；本阶段不播放音频，留空不影响听觉逻辑。
@export var audio_stream: AudioStream


func emit_from(source: Node3D, radius: float) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree() or not is_finite(radius) or radius <= 0.0:
		return
	# 记录此刻位置；延后通知以避免命中/移动处理中立即重入AI。
	source.get_tree().call_group_flags(SceneTree.GROUP_CALL_DEFERRED, &"hearing_listener", &"receive_noise",
		source, source.global_position, radius, occluded_range_multiplier)
