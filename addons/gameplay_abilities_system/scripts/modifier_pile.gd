class_name GASModifierPile
extends RefCounted

var op: GASEnums.ModifierOp = GASEnums.ModifierOp.ADD
var magnitude: float = 0.0
var handle: int = -1   
var stack_count: int = 1
var suspended: bool = false

func _init(p_op: GASEnums.ModifierOp, p_magnitude: float, p_handle: int = -1) -> void:
	op = p_op
	magnitude = p_magnitude
	handle = p_handle
