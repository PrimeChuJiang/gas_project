class_name GASEffectSpec
extends RefCounted

# 引用的效果定义
var effect_def: GASGameplayEffect

# 上下文 (谁发起的、打在哪了)
var context: GASEffectContext

# 来源和目标 ASC
var source_asc: GASAbilitySystemComponent
var target_asc: GASAbilitySystemComponent

var set_by_caller: Dictionary[StringName, float] = {}

# 当前等级
var level: float = 0.0

# 运行时参数(定义层数可能被等级/标签修正，这里存最终值)
var duration: float = 0.0
var period: float = 0.0
# 和定义层的结构是一致的，但magnitude是已经计算好了的
var modifiers: Array[GASModifierSpec] = [] 

func _init(effect: GASGameplayEffect, spec_context: GASEffectContext = null, spec_source_asc: GASAbilitySystemComponent = null, spec_target_asc: GASAbilitySystemComponent = null):
	effect_def = effect
	duration = effect.duration
	period = effect.period
	context = spec_context
	source_asc = spec_source_asc
	target_asc = spec_target_asc
	for mod in effect.modifiers:
		var mod_spec: GASModifierSpec = GASModifierSpec.new(mod, self)
		modifiers.append(mod_spec)

func resolve_all():
	for mod_spec in modifiers:
		if not mod_spec.resolved:
			mod_spec.resolve(self)

func set_setbycaller_magnitude(key: StringName, value: float) -> void:
	set_by_caller[key] = value

func get_setbycaller_magnitude(key: StringName, default_value: float) -> float:
	if set_by_caller.has(key):
		return set_by_caller[key]
	GameLogger.warn("GameplayEffectSpec", "can't find key %s in set_by_caller" % key)
	return default_value
