@tool
class_name PlayAudioAction
extends SceneAction

enum Command { PLAY, STOP }

@export_node_path("Node") var target_path: NodePath
@export var command: Command = Command.PLAY
@export var stream: AudioStream
@export var wait_for_finished := false


func begin(context: SceneActionContext) -> void:
	var player := context.resolve(target_path)
	if not player is AudioStreamPlayer and not player is AudioStreamPlayer3D:
		context.fail(&"invalid_audio_player")
		return
	context.state[&"player"] = player
	if command == Command.STOP:
		player.stop()
		context.complete()
		return
	if stream != null:
		player.stream = stream
	if player.stream == null:
		context.fail(&"missing_audio_stream")
		return
	context.state[&"started_playback"] = true
	if wait_for_finished:
		player.finished.connect(_finished.bind(context), CONNECT_ONE_SHOT)
	player.play()
	if not wait_for_finished:
		context.complete()


func cancel(context: SceneActionContext, _reason: StringName) -> void:
	var player = context.state.get(&"player")
	if context.state.get(&"started_playback", false) and is_instance_valid(player):
		var callback := _finished.bind(context)
		if player.finished.is_connected(callback):
			player.finished.disconnect(callback)
		player.stop()


func _finished(context: SceneActionContext) -> void:
	if context.is_current():
		context.complete()
