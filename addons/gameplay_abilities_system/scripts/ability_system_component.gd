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
# 结构为：[{handle, spec, remaining_time, period_timer, granted_tags, stack_count}]
var _active_effects: Array = []
# 已授予的能力列表
var _abilities: Array[GASGameplayAbility] = []
# 当前正在激活的能力列表
var _active_abilities: Array[GASGameplayAbility] = []
# 属性依赖列表
# Array内结构为[{"asc":ASC, "attr_name": StringName, "handle": int, "mod_spec": GASModifierSpec}]
var _attribute_dependencies: Dictionary[StringName, Array] = {}
# 正在重算链上的属性
var _recalc_stack: Array[StringName] = []

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
	if not spec.effect_def.application_tag_requirements.requirements_met(has_tag):
		GameLogger.warn("GameAbilitySystemComponent", "ge %s rejected by application tag requirements" % spec.effect_def.resource_path)
		return INVALID_HANDLE
	spec.resolve_all()
	if spec.effect_def.duration_policy == GASEnums.DurationPolicy.INSTANT:
		_apply_effect_modifiers(spec)
		_run_executions(spec)
		for attr_set in _attribute_sets:
			attr_set.post_gameplay_effect_execute(spec)
		return INVALID_HANDLE
	elif spec.effect_def.duration_policy == GASEnums.DurationPolicy.DURATION or spec.effect_def.duration_policy == GASEnums.DurationPolicy.INFINITE:
		if spec.effect_def.stack_policy == GASEnums.StackingPolicy.LIMITED:
			var effect := _find_stack_entry(spec)
			if not effect.is_empty():
				if effect.stack_count >= spec.effect_def.stack_limit:
					GameLogger.warn("GameAbilitySystemComponent", "ge %s stack get limit" % spec.effect_def.resource_path)
					return INVALID_HANDLE
				else:
					effect.stack_count += 1
					_sync_stack_count(effect)
					return effect.handle
		elif spec.effect_def.stack_policy == GASEnums.StackingPolicy.REFRESH_DURATION:
			var effect := _find_stack_entry(spec)
			if not effect.is_empty():
				if effect.stack_count < spec.effect_def.stack_limit:
					effect.stack_count += 1
				effect.remaining_time = spec.duration
				if spec.effect_def.reset_period_on_stack:
					effect.period_timer = spec.period
				_sync_stack_count(effect)
				return effect.handle
		if spec.period == 0:
			for mod_spec in spec.modifiers:
				var attr_based := mod_spec.magnitude_def as GASModifierMagnitudeAttributeBased
				if attr_based and not attr_based.is_snapshot() and _find_capture_def(spec.effect_def, attr_based.attr_name, attr_based.from_target) == null:
					GameLogger.error("GameAbilitySystemComponent", "ge %s reads %s but not declared in relevant_attributes!" % [spec.effect_def.resource_path, attr_based.attr_name])
					return INVALID_HANDLE
		var handle = _next_handle
		_next_handle += 1
		for mod_spec in spec.modifiers:
			var attr_set: GASAttributeSet = _find_attribute_set(mod_spec.attr_name)
			if attr_set != null and spec.period == 0:
				attr_set.apply_modifier(mod_spec.attr_name, handle, mod_spec.op, mod_spec.get_magnitude())
		if spec.period == 0:
			for mod_spec in spec.modifiers:
				var attr_based := mod_spec.magnitude_def as GASModifierMagnitudeAttributeBased
				if attr_based and not attr_based.is_snapshot():
					var capture_def := _find_capture_def(spec.effect_def, attr_based.attr_name, attr_based.from_target)
					var home: GASAbilitySystemComponent = self
					if not capture_def.from_target:
						home = spec.source_asc
						if home == null:
							GameLogger.error("GameAbilitySystemComponent", "source_asc is null for dependency!")
							continue
					if not home._attribute_dependencies.has(capture_def.attr_name):
						home._attribute_dependencies[capture_def.attr_name] = []
					home._attribute_dependencies[capture_def.attr_name].append({
						"asc":self,
						"attr_name": mod_spec.attr_name,
						"handle": handle,
						"mod_spec": mod_spec
					})
		if not spec.effect_def.executions.is_empty():
			if spec.period <= 0:
				GameLogger.warn("GameAbilitySystemComponent", "execution only support \"period > 0\" type, executions ignored")
		_active_effects.append({"handle": handle, "spec": spec, "remaining_time": spec.duration, "granted_tags": spec.effect_def.granted_tag, "period_timer": spec.period, "stack_count": 1})
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

# 驱散：按 granted tag 匹配移除活跃效果（has_any = 含 query 任一 tag 的家族成员，
# 与 has_tag 同向层级匹配）；快照遍历（remove 会改 _active_effects）；返回移除数量
func remove_active_effects_with_tags(tags: FGameplayTagContainer) -> int:
	var removed := 0
	var snapshot: Array = _active_effects.duplicate()
	for entry in snapshot:
		if entry.granted_tags.has_any(tags):
			if remove_active_effect(entry.handle):
				removed += 1
	return removed

func init_ability_actor_info(owner: Node, avatar: Node) -> void:
	owner_actor = owner
	avatar_actor = avatar

func add_attribute_set(attr_set: GASAttributeSet) -> void:
	_attribute_sets.append(attr_set)
	attr_set.attribute_changed.connect(_on_attribute_changed)

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

# 获取GE堆叠层数
func get_stack_count(handle: int) -> int:
	for entry in _active_effects:
		if entry.handle == handle:
			return entry.stack_count
	return 0

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
			if entry.spec.effect_def.expiration_policy == GASEnums.StackingExpirationPolicy.REMOVE_SINGLE and entry.stack_count > 1:
				# 到期掉一层，续满时长
				entry.stack_count -= 1
				entry.remaining_time = entry.spec.duration
				_sync_stack_count(entry)
			else:
				remove_active_effect(entry.handle)

func _cleanup_effect(entry: Dictionary) -> void:
	# 从所有 AttributeSet 移除该 handle 的 modifiers
	for attr_set in _attribute_sets:
		for attr_name in attr_set._attributes.keys():
			attr_set.remove_modifier(attr_name, entry.handle)
	for tag in entry.granted_tags._tags:
		_remove_owned_tag(tag)
	for mod in entry.spec.modifiers:
		var mod_attr_based:= mod.magnitude_def as GASModifierMagnitudeAttributeBased
		if mod_attr_based and not mod_attr_based.is_snapshot() and entry.spec.period == 0:
			var home: GASAbilitySystemComponent = self
			if not mod_attr_based.from_target:
				home = entry.spec.source_asc
				if home == null:
					continue
			var dep_attr: StringName = mod.magnitude_def.attr_name
			if not home._attribute_dependencies.has(dep_attr):
				continue
			var deps: Array = home._attribute_dependencies[dep_attr]
			for i in range(deps.size() - 1, -1, -1):
				if deps[i].handle == entry.handle:
					deps.remove_at(i)
			if deps.is_empty():
				home._attribute_dependencies.erase(dep_attr)
				

func _apply_effect_modifiers(spec: GASEffectSpec) -> void:
	var buckets := GASModifierBucket.new()
	for mod in spec.modifiers:
		buckets.append(mod.attr_name, mod.op, mod.get_magnitude())
	for attr_name in buckets.items:
		var attr_set := _find_attribute_set(attr_name)
		if attr_set != null:
			attr_set.apply_modifiers_to_base(attr_name, buckets.get_pile(attr_name))

func _apply_periodic_effect(entry: Dictionary) -> void:
	var spec: GASEffectSpec = entry.spec
	# 每跳前重算非快照modifier
	for mod_spec in spec.modifiers:
		if not mod_spec.magnitude_def.is_snapshot():
			mod_spec.resolve(spec)
	_apply_effect_modifiers(spec)
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
		_update_ongoing_requirements()
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
		_update_ongoing_requirements()

func _cancel_active_abilities_with_tag(tag: FGameplayTag):
	var _active_ability_duplicate: Array[GASGameplayAbility]
	_active_ability_duplicate = _active_abilities.duplicate()
	for ability in _active_ability_duplicate:
		for ability_tag in ability.cancel_with_tags._tags:
			if tag.matches_tag(ability_tag):
				cancel_ability(ability)
				break

func _run_executions(spec: GASEffectSpec) -> void:
	var target_buckets := GASModifierBucket.new()
	var source_buckets := GASModifierBucket.new()
	for exec in spec.effect_def.executions:
		var exec_array: Array[GASModifierEvaluatedData] = exec._execute(spec)
		if exec_array:
			for mod_eval in exec_array:
				match mod_eval.receiver:
					GASEnums.Receiver.TARGET:
						target_buckets.append(mod_eval.attr_name, mod_eval.op, mod_eval.value)
					GASEnums.Receiver.SOURCE:
						if spec.source_asc:
							source_buckets.append(mod_eval.attr_name, mod_eval.op, mod_eval.value)
						else:
							GameLogger.error("GameAbilitySystemComponent", "source_asc in spec is null!")
	for attr_name in target_buckets.items:
		var attr_set := _find_attribute_set(attr_name)
		if attr_set != null:
			attr_set.apply_modifiers_to_base(attr_name, target_buckets.get_pile(attr_name))
	for attr_name in source_buckets.items:
		var attr_set := spec.source_asc.find_attribute_set(attr_name)
		if attr_set != null:
			attr_set.apply_modifiers_to_base(attr_name, source_buckets.get_pile(attr_name))

func _on_attribute_changed(attr_name: StringName, new_value: float, old_value: float) -> void:
	if _attribute_dependencies.has(attr_name):
		_recalculate_dependencies(attr_name)

func _recalculate_dependencies(attr_name: StringName) -> void:
	if _recalc_stack.has(attr_name):
		GameLogger.warn("GameAbilitySystemComponent", "dependency loop detected: %s" % attr_name)
		return
	_recalc_stack.append(attr_name)
	for dep in _attribute_dependencies[attr_name]:
		var new_magnitude: float = dep.mod_spec.magnitude_def._calculate(dep.mod_spec.effect_spec)
		var attr_set: GASAttributeSet = dep.asc.find_attribute_set(dep.attr_name)
		if attr_set:
			attr_set.update_modifier_magnitude(dep.attr_name, dep.handle, new_magnitude)
	_recalc_stack.pop_back()

func _same_ge(ge_a: GASGameplayEffect, ge_b: GASGameplayEffect) -> bool:
	if not ge_a.resource_path.is_empty() and not ge_b.resource_path.is_empty():
		return ge_a.resource_path == ge_b.resource_path
	return ge_a == ge_b

# 按照attr_name和from_target找捕获声明
func _find_capture_def(effect_def: GASGameplayEffect, attr_name: StringName, from_target: bool) -> GASCaptureDefinition:
	for capture_def in effect_def.relevant_attributes:
		if capture_def.attr_name == attr_name and capture_def.from_target == from_target:
			return capture_def
	return null

func _sync_stack_count(entry: Dictionary) -> void:
	if entry.spec.period != 0:
		return   # 周期 GE 不挂账（无 pile 可同步），层数只活在条目上
	for mod in entry.spec.modifiers:
		var attr_set := _find_attribute_set(mod.attr_name)
		if attr_set != null:
			attr_set.update_modifier_stack_count(mod.attr_name, entry.handle, entry.stack_count)

func _update_ongoing_requirements() -> void:
	for entry in _active_effects:
		var reqs: GASGameplayTagRequirements = entry.spec.effect_def.ongoing_tag_requirements
		var met := reqs.requirements_met(has_tag)
		for mod_spec in entry.spec.modifiers:
			var attr_set := _find_attribute_set(mod_spec.attr_name)
			if attr_set != null:
				attr_set.update_modifier_suspended(mod_spec.attr_name, entry.handle, not met)

func _find_stack_entry(spec: GASEffectSpec) -> Dictionary:
	for entry in _active_effects:
		if _same_ge(entry.spec.effect_def, spec.effect_def):
			if spec.effect_def.stack_type == GASEnums.StackType.STACK_BY_SOURCE and entry.spec.source_asc != spec.source_asc:
				continue
			return entry
	return {}
