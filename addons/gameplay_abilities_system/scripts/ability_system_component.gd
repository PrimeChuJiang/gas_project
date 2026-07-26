class_name GASAbilitySystemComponent
extends Node

signal gameplay_tag_changed(tag: FGameplayTag, added: bool)

const INVALID_HANDLE: int = -1

# ASC的逻辑持有者，例如英雄死后依然存在，属性/等级/装备不丢，此时owner_actor是PlayerState
var owner_actor: Node
# ASC的物理表现体，例如英雄死后销毁、复活后重建，此时avatar_actor是Character
var avatar_actor: Node
# 属性集列表
var _attribute_sets: Array[GASAttributeSet] = []
# 带计数的tag容器，结构为{key(FGameplayTag):value(int)}
var _tag_counts: Dictionary = {}

# 效果句柄，自增 ID，唯一标识一个已激活的 GE
# 用于 GE 到期时精确移除对应的 modifiers 和 granted_tags
var _next_handle: int = 1
# 结构为：[{handle, spec, remaining_time, period_timer, granted_tags}]
var _active_effects: Array = []
# 已授予的能力列表
var _abilities: Array[GASGameplayAbility] = []
# 当前正在激活的能力列表
var _active_abilities: Array[GASGameplayAbility] = []

func make_effect_spec(ge: GASGameplayEffect) -> GASEffectSpec:
	var context : GASEffectContext = GASEffectContext.new()
	context.instigator = owner_actor
	context.effect_causer = avatar_actor
	var spec = GASEffectSpec.new(ge, context, self)
	return spec

func apply_gameplay_effect_spec_to_self(spec: GASEffectSpec) -> int:
	if not spec : 
		GameLogger.error("GameAbilitySystemComponent", "spec is null!")
		return INVALID_HANDLE
	spec.target_asc = self
	spec.resolve_all()
	if spec.effect_def.duration_policy == GASEnums.DurationPolicy.INSTANT:
		for mod in spec.modifiers:
			var attr_set : GASAttributeSet = _find_attribute_set(mod.attr_name)
			if attr_set != null:
				attr_set.apply_base_value_change(mod.attr_name, mod.get_magnitude())
		_run_executions(spec)
		for attr_set in _attribute_sets:
			attr_set.post_gameplay_effect_execute(spec)
		return INVALID_HANDLE
	elif spec.effect_def.duration_policy == GASEnums.DurationPolicy.DURATION or spec.effect_def.duration_policy == GASEnums.DurationPolicy.INFINITE:
		var handle = _next_handle
		_next_handle += 1
		for mod in spec.modifiers:
			var attr_set : GASAttributeSet = _find_attribute_set(mod.attr_name)
			if attr_set != null:
				if spec.period == 0:
					attr_set.apply_modifier(mod.attr_name, handle, mod.op, mod.get_magnitude())
		if not spec.effect_def.executions.is_empty():
			if spec.period <= 0:
				GameLogger.warn("GameAbilitySystemComponent", "execution only support \"period > 0\" type")
		_active_effects.append({"handle": handle, "spec": spec, "remaining_time": spec.duration, "granted_tags":spec.effect_def.granted_tag, "period_timer": spec.period})
		for tag in spec.effect_def.granted_tag._tags:
			_add_owned_tag(tag)
		return handle
	return INVALID_HANDLE

func apply_gameplay_effect_spec_to_target(spec: GASEffectSpec, target_asc: GASAbilitySystemComponent) -> int:
	if not spec : 
		GameLogger.error("GameAbilitySystemComponent", "spec is null!")
		return INVALID_HANDLE
	if not target_asc:
		GameLogger.error("GameAbilitySystemComponent", "target asc is null!")
		return INVALID_HANDLE
	return target_asc.apply_gameplay_effect_spec_to_self(spec)

func remove_active_effect(handle: int) -> bool:
	for entry in _active_effects:
		if entry.handle == handle:
			_active_effects.erase(entry)
			_cleanup_effect(entry)
			return true
	return false

func init_ability_actor_info(owner: Node, avatar: Node) -> void:
	owner_actor = owner
	avatar_actor = avatar

func add_attribute_set(_set: GASAttributeSet) -> void:
	_attribute_sets.append(_set)

# 层级匹配查询：持有 State.Debuff.Stun 时，查询 State.Debuff 也应命中
func has_tag(tag: FGameplayTag) -> bool:
	for owned_tag in _tag_counts:
		if owned_tag.matches_tag(tag):
			return true
	return false

func find_attribute_set(attr_name: StringName) -> GASAttributeSet:
	return _find_attribute_set(attr_name)

# 往ASC内注入Ability
func give_ability(ability: GASGameplayAbility) -> bool:
	if not _can_give_ability(ability):
		return false
	ability.asc = self
	ability.ability_ended.connect(_on_ability_ended)
	_abilities.append(ability)
	return true

# 尝试调用Ability
func try_activate_ability(ability: GASGameplayAbility) -> bool:
	if ability.can_activate():
		_active_abilities.append(ability)
		ability.activate()
		return true
	return false

# 取消Ability
func cancel_ability(ability: GASGameplayAbility):
	if _active_abilities.has(ability):
		ability.end_ability(true)

func _ready():
	set_process(true)

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
			remove_active_effect(entry.handle)

func _cleanup_effect(entry: Dictionary) -> void:
	# 从所有 AttributeSet 移除该 handle 的 modifiers
	for attr_set in _attribute_sets:
		for attr_name in attr_set._attributes.keys():
			attr_set.remove_modifier(attr_name, entry.handle)
	for tag in entry.granted_tags._tags:
		_remove_owned_tag(tag)


func _apply_periodic_effect(entry: Dictionary) -> void:
	var spec: GASEffectSpec = entry.spec
	for mod in spec.modifiers:
		var attr_set = _find_attribute_set(mod.attr_name)
		if attr_set != null:
			attr_set.apply_base_value_change(mod.attr_name, mod.get_magnitude())
	_run_executions(spec)
	for attr_set in _attribute_sets:
		attr_set.post_gameplay_effect_execute(spec)

func _on_ability_ended(ability: GASGameplayAbility, was_cancelled: bool):
	var idx = _active_abilities.find(ability)
	if idx >= 0:
		_active_abilities.remove_at(idx)

func _can_give_ability(ability: GASGameplayAbility) -> bool:
	if ability.cooldown_ge:
		if ability.cooldown_ge.granted_tag._tags.is_empty():
			GameLogger.error("GameAbilitySystemComponent", "have cooldown_ge but cooldown_ge don't have granted_tag")
			return false
		if ability.cooldown_ge.duration_policy != GASEnums.DurationPolicy.DURATION:
			GameLogger.error("GameAbilitySystemComponent", "have cooldown_ge but cooldown_ge's duration_policy is not DURATION")
			return false
	if ability.cost_ge:
		if ability.cost_ge.duration_policy != GASEnums.DurationPolicy.INSTANT:
			GameLogger.error("GameAbilitySystemComponent", "have cost_ge but cost_ge's duration_policy is not INSTANT")
			return false
	if _abilities.has(ability):
		GameLogger.error("GameAbilitySystemComponent", "already have a same ability")
		return false
	return true

func _add_owned_tag(tag: FGameplayTag):
	if not _tag_counts.has(tag):
		_tag_counts[tag] = 1
		gameplay_tag_changed.emit(tag, true)
		_cancel_active_abilities_with_tag(tag)
	else :
		_tag_counts[tag] += 1

func _remove_owned_tag(tag: FGameplayTag):
	if not _tag_counts.has(tag):
		GameLogger.error("GameAbilitySystemComponent", "remove a nonexistent tag: " + tag.get_tag_name())
		return
	_tag_counts[tag] -= 1
	if _tag_counts[tag] == 0:
		_tag_counts.erase(tag)
		gameplay_tag_changed.emit(tag, false)

func _cancel_active_abilities_with_tag(tag: FGameplayTag):
	var _active_ability_duplicate: Array[GASGameplayAbility]
	_active_ability_duplicate = _active_abilities.duplicate()
	for ability in _active_ability_duplicate:
		for ability_tag in ability.cancel_with_tags._tags:
			if tag.matches_tag(ability_tag):
				cancel_ability(ability)
				break

func _run_executions(spec: GASEffectSpec) -> void:
	for exec in spec.effect_def.executions:
		var exec_array:Array[GASModifierEvaluatedData] = exec._execute(spec)
		if exec_array:
			for mod_eval in exec_array:
				if mod_eval.op != GASEnums.ModifierOp.ADD:
					GameLogger.error("GameAbilitySystemComponent", "executions_calculation only support Add op !")
					continue
				var attr_set: GASAttributeSet = null
				match mod_eval.receiver:
					GASEnums.Receiver.TARGET:
						attr_set = _find_attribute_set(mod_eval.attr_name)
					GASEnums.Receiver.SOURCE:
						if spec.source_asc:
							attr_set = spec.source_asc.find_attribute_set(mod_eval.attr_name)
						else:
							GameLogger.error("GameAbilitySystemComponent", "source_asc in spec is null!")
				if attr_set != null:
					attr_set.apply_base_value_change(mod_eval.attr_name, mod_eval.value)
