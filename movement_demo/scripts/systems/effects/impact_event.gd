extends RefCounted

var position: Vector3
var normal: Vector3
var direction: Vector3
var collider: WeakRef
var source: WeakRef
var receiver: WeakRef
var region: WeakRef
var profile: ImpactProfile
var consumed: bool = false
