class_name GASModifierPile
extends RefCounted

var op: GASEnums.ModifierOp = GASEnums.ModifierOp.ADD
var magnitude: float = 0.0
var handle: int = -1   # 账本条目用；装配桶不需要，默认 -1

func _init(p_op: GASEnums.ModifierOp, p_magnitude: float, p_handle: int = -1) -> void:
	op = p_op
	magnitude = p_magnitude
	handle = p_handle
