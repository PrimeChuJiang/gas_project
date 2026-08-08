class_name GASCaptureDefinition
extends Resource     # ← 定义层（可 @export、可进 .tres）；账页等运行时记录才用 RefCounted

@export var attr_name: StringName = &""
@export var from_target: bool = false

func _init(p_attr_name: StringName = &"", p_from_target: bool = false) -> void:
	attr_name = p_attr_name
	from_target = p_from_target
