class_name TopdownProjectile
extends RefCounted

var pos: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.RIGHT
var speed: float = 300.0
var traveled: float = 0.0
var form: TopdownAttackForm
var source: TopdownEntity
var hit_targets: Array[TopdownEntity] = []
