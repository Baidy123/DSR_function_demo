@tool
class_name SceneEventDefinition
extends Resource

enum Scope { SCENE, REGION }
enum Combination { ANY, ALL }
enum FailurePolicy { STOP, CONTINUE }
enum StartMode { AUTO, TRIGGERS, MANUAL }

@export var event_id: StringName
@export var label: String
@export var enabled := true
@export var scope: Scope = Scope.SCENE
@export var start_mode: StartMode = StartMode.TRIGGERS
@export var combination: Combination = Combination.ANY
@export var triggers: Array[SceneEventTrigger] = []
@export var conditions: Array[SceneCondition] = []
@export var actions: Array[SceneAction] = []
@export var failure_policy: FailurePolicy = FailurePolicy.STOP
