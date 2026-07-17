class_name GASEffectSpec
extends RefCounted

# 引用的效果定义
var effect_def: GASGameplayEffect

# 上下文 (谁发起的、打在哪了)
var context: GASEffectContext

# 来源和目标 ASC
var source_asc: GASAbilitySystemComponent
var target_asc: GASAbilitySystemComponent

# 当前等级
var level: float = 0.0

# 运行时参数(定义层数可能被等级/标签修正，这里存最终值)
var duration: float = 0.0
var period: float = 0.0
# 和定义层的结构是一致的，但magnitude是已经计算好了的
# 元素为Dictionary:{attr_name: StringName, op: ModifierOp, magnitude: float}
var modifiers: Array[GEModifier] = [] 

func _init(effect: GASGameplayEffect):
	effect_def = effect
	duration = effect.duration
	period = effect.period
	for mod in effect.modifiers:
		modifiers.append(mod.duplicate())
