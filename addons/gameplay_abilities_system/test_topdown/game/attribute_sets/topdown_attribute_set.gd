class_name TopdownAttributeSet
extends GASAttributeSet

const ATTR_HEALTH := &"Health"
const ATTR_MAX_HEALTH := &"MaxHealth"
const ATTR_ATTACK := &"Attack"
const ATTR_DEFENSE := &"Defense"
const ATTR_MOVE_SPEED := &"MoveSpeed"
const ATTR_LEVEL := &"Level"
const ATTR_XP := &"XP"

signal leveled_up(new_level: int)

var _initialized: bool = false

# 升级经验曲线：升到 n+1 级需要 xp_to_next(n) 点经验
func xp_to_next(level: float) -> float:
	return 40.0 * level

func pre_attribute_change(attr_name: StringName, new_value: float) -> float:
	match attr_name:
		ATTR_HEALTH:
			return clampf(new_value, 0.0, get_attribute_value(ATTR_MAX_HEALTH))
		ATTR_MAX_HEALTH:
			return maxf(new_value, 1.0)
		ATTR_ATTACK, ATTR_DEFENSE, ATTR_MOVE_SPEED, ATTR_LEVEL, ATTR_XP:
			return maxf(new_value, 0.0)
	return new_value

func initialize_attributes(owner_asc: GASAbilitySystemComponent):
	if _initialized:
		GameLogger.error("TopdownAttributeSet", "already initialized")
		return
	super.initialize_attributes(owner_asc)
	attribute_changed.connect(_on_attribute_changed)
	_initialized = true

func _on_attribute_changed(attr_name: StringName, new_value: float, old_value: float) -> void:
	if attr_name == ATTR_MAX_HEALTH:
		var cur := get_attribute_value(ATTR_HEALTH)
		if cur > new_value:
			apply_base_value_change(ATTR_HEALTH, new_value - cur)

## PostGameplayEffectExecute：XP 满则升级（Level/MaxHealth/Attack 成长 + 回满触发血量）
func post_gameplay_effect_execute(effect_spec: GASEffectSpec) -> void:
	var xp := get_attribute_value(ATTR_XP)
	var level := get_attribute_value(ATTR_LEVEL)
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1.0
		apply_base_value_change(ATTR_LEVEL, 1.0)
		apply_base_value_change(ATTR_MAX_HEALTH, 20.0)
		apply_base_value_change(ATTR_HEALTH, 20.0)
		apply_base_value_change(ATTR_ATTACK, 2.0)
		apply_base_value_change(ATTR_DEFENSE, 1.0)
		leveled_up.emit(int(level))
	apply_base_value_change(ATTR_XP, xp - get_attribute_value(ATTR_XP))
