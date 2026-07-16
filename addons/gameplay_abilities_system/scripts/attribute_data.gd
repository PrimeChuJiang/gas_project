class_name GASAttributeDATA
extends RefCounted

enum ModifierOp{
	ADD,
	MULTIPLY,
	DIVIDE,
	OVERRIDE
}

var base_value: float = 0.0
# 只读计算属性
var current_value: float:
	get:
		if _dirty:
			_cached_value = _evaluate()
			_dirty = false
		return _cached_value

# 存放当前挂载在该属性上的修饰器列表(由 Duration/Infinite 的 GE 提供)
# 结构: [ {"handle": int, "operation": "add/sub/mul/div/override", "value": float}]
var _modifiers: Array[Dictionary] = []

var _dirty: bool = true
var _cached_value: float = 0.0

func get_current_value():
	return current_value
func set_current_value(new_value: float):
	current_value = new_value

func get_base_value():
	return base_value
func set_base_value(new_value: float):
	base_value = new_value
	_dirty = true

# 添加修改器
func add_modifier(handle: int, op: ModifierOp, magnitude: float) -> void:
	_modifiers.append({"handle": handle, "op": op, "magnitude": magnitude})
	_dirty = true

# 移除指定修改器
func remove_modifier(handle: int) -> void:
	for i in range(_modifiers.size() - 1, -1, -1):
		if _modifiers[i].handle == handle:
			_modifiers.remove_at(i)
	_dirty = true

# 移除所有修改器
func remove_all_modifiers():
	_modifiers.clear()
	_dirty = true

# 计算动态值
func _evaluate():
	#1. Override 短路
	for mod in _modifiers:
		if mod.op == ModifierOp.OVERRIDE:
			return mod.magnitude
	
	#2. 从基础数值开始
	var result = base_value
	
	#3. 累加
	for mod in _modifiers:
		if mod.op == ModifierOp.ADD:
			result += mod.magnitude
	
	#4. 累乘 (1 + magnitude)
	var mult = 1.0
	for mod in _modifiers:
		if mod.op == ModifierOp.MULTIPLY:
			mult *= (1.0 + mod.magnitude)
	result *= mult
	
	#5. 累除 (1 + magnitude)
	var div = 1.0
	for mod in _modifiers:
		if mod.op == ModifierOp.MULTIPLY:
			mult *= (1.0 + mod.magnitude)
	if div != 0.0:
		result /= div
	
	return result
