class_name GASAbilitySystemComponent
extends Node

signal gameplay_tag_changed(tag: FGameplayTag, added: bool)

# ASC的逻辑持有者，例如英雄死后依然存在，属性/等级/装备不丢，此时owner_actor是PlayerState
var owner_actor: Node
# ASC的物理表现体，例如英雄死后销毁、复活后重建，此时avatar_actor是Character
var avatar_actor: Node

var _attribute_sets: Array[GASAttributeSet] = []
var _owned_tags: FGameplayTagContainer = FGameplayTagContainer.new()

# 效果句柄，自增 ID，唯一标识一个已激活的 GE
# 用于 GE 到期时精确移除对应的 modifiers 和 granted_tags
var _next_handle: int = 1
# 结构为：[{handle, spec, remaining_time, period_timer, granted_tags}]
var _active_effects: Array = []

func _ready():
	set_process(true)

func apply_gameplay_effect_spec_to_self(spec: GASEffectSpec) -> void:
	if spec.effect_def.duration_policy == GASEnums.DurationPolicy.INSTANT:
		for mod in spec.modifiers:
			var attr_set : GASAttributeSet = _find_attribute_set(mod.attr_name)
			if attr_set != null:
				attr_set.apply_base_value_change(mod.attr_name, mod.magnitude)
		for attr_set in _attribute_sets:
			attr_set.post_gameplay_effect_execute(spec)
	elif spec.effect_def.duration_policy == GASEnums.DurationPolicy.DURATION or spec.effect_def.duration_policy == GASEnums.DurationPolicy.INFINITE:
		for mod in spec.modifiers:
			var attr_set : GASAttributeSet = _find_attribute_set(mod.attr_name)
			if attr_set != null:
				if spec.period == 0:
					attr_set.apply_modifier(mod.attr_name, _next_handle, mod.op, mod.magnitude)
		_active_effects.append({"handle": _next_handle, "spec": spec, "remaining_time": spec.duration, "granted_tags":spec.effect_def.granted_tag, "period_timer": spec.period})
		for tag in spec.effect_def.granted_tag._tags:
			_owned_tags.add_tag(tag)
			gameplay_tag_changed.emit(tag, true)
		_next_handle += 1

func init_ability_actor_info(owner: Node, avatar: Node) -> void:
	owner_actor = owner
	avatar_actor = avatar

func add_attribute_set(_set: GASAttributeSet) -> void:
	_attribute_sets.append(_set)

func has_tag(tag: FGameplayTag):
	_owned_tags.has_matching_tag(tag)

func _find_attribute_set(attr_name: StringName) -> GASAttributeSet:
	for set in _attribute_sets:
		if set._attributes.has(attr_name):
			return set
	return null

func _process(delta: float):
	for i in range(_active_effects.size()-1, -1, -1): # 倒序遍历，安全删除
		var entry = _active_effects[i]
		if entry.spec.effect_def.duration_policy == GASEnums.DurationPolicy.INSTANT:
			continue
		if entry.spec.effect_def.duration_policy == GASEnums.DurationPolicy.DURATION:
			entry.remaining_time -= delta
		# 周期性检查
		if entry.spec.period > 0:
			entry.period_timer -= delta
			if entry.period_timer <= 0:
				entry.period_timer += entry.spec.period
				_apply_periodic_effect(entry)
		# 到期
		if entry.spec.effect_def.duration_policy == GASEnums.DurationPolicy.DURATION and entry.remaining_time <= 0:
			_remove_effect(entry.handle)
			_active_effects.remove_at(i)

func _remove_effect(handle: int) -> void:
	# 从所有 AttributeSet 移除该 handle 的 modifiers
	for set in _attribute_sets:
		for attr_name in set._attributes.keys():
			set.remove_modifier(attr_name, handle)
	# 找到对应的活跃效果，退掉标签
	for entry in _active_effects:
		if entry.handle == handle:
			for tag in entry.granted_tags._tags:
				_owned_tags.remove_tag(tag)
				gameplay_tag_changed.emit(tag, false)
			break

func _apply_periodic_effect(entry: Dictionary) -> void:
	var spec: GASEffectSpec = entry.spec
	for mod in spec.modifiers:
		var attr_set = _find_attribute_set(mod.attr_name)
		if attr_set != null:
			attr_set.apply_base_value_change(mod.attr_name, mod.magnitude)
	for attr_set in _attribute_sets:
		attr_set.post_gameplay_effect_execute(spec)
