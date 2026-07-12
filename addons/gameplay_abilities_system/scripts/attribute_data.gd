class_name GASAttributeDATA
extends RefCounted

var base_value: float = 0.0
var current_value: float = 0.0

# 存放当前挂载在该属性上的修饰器(由 Duration/Infinite 的 GE 提供)
# 结构: { modifier_id(int): {"operation": "add/sub/mul/div/override", "value": float}}
var modifiers: Dictionary = {}

func get_current_value():
	return current_value
func set_current_value(new_value: float):
	current_value = new_value

func get_base_value():
	return base_value
func set_base_value(new_value: float):
	base_value = new_value
