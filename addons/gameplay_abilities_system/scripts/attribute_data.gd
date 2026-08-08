class_name GASAttributeDATA
extends RefCounted

var base_value: float = 0.0
# 只读计算属性
var current_value: float:
	get:
		if _dirty:
			_cached_value = evaluate(base_value, _modifiers)
			_dirty = false
		return _cached_value

# 租约账页：由 DURATION/INFINITE（period == 0）的 GE 挂载，带 handle 追踪，到期退租
var _modifiers: Array[GASModifierPile] = []

var _dirty: bool = true
var _cached_value: float = 0.0

func get_base_value():
	return base_value
func set_base_value(new_value: float):
	base_value = new_value
	_dirty = true

# 添加修改器
func add_modifier(handle: int, op: GASEnums.ModifierOp, magnitude: float) -> void:
	_modifiers.append(GASModifierPile.new(op, magnitude, handle))
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

# 按照 handle 找到GASModifierPile，修改它的magnitude，置dirty
func set_modifier_magnitude(handle: int, magnitude: float) -> void:
	for pile in _modifiers:
		if pile.handle == handle:
			pile.magnitude = magnitude
			_dirty = true
			return
	GameLogger.warn("GASAttributeData", "setting a unexisting modifier!")

# 计算动态值
static func evaluate(base: float, modifiers: Array[GASModifierPile]):
	#1. Override 短路
	for mod in modifiers:
		if mod.op == GASEnums.ModifierOp.OVERRIDE:
			return mod.magnitude
	
	#2. 从基础数值开始
	var result = base
	
	#3. 累加
	for mod in modifiers:
		if mod.op == GASEnums.ModifierOp.ADD:
			result += mod.magnitude
	
	#4. 累乘 (1 + magnitude)
	var mult = 1.0
	for mod in modifiers:
		if mod.op == GASEnums.ModifierOp.MULTIPLY:
			mult *= (1.0 + mod.magnitude)
	result *= mult
	
	#5. 累除 (1 + magnitude)
	var div = 1.0
	for mod in modifiers:
		if mod.op == GASEnums.ModifierOp.DIVIDE:
			div *= (1.0 + mod.magnitude)
	if div != 0.0:
		result /= div
	
	return result
