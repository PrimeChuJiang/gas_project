## 不论Ability怎么运作，所有的结果都必须调用end_ability()这个函数
class_name GASGameplayAbility
extends Resource

signal ability_activated
signal ability_ended(ability: GASGameplayAbility, was_cancelled: bool)

# 能力标识，可以通过标签来查找能力
@export var ability_tags: FGameplayTagContainer = FGameplayTagContainer.new()

# 激活能力必须有的标签，少了任何一个都不能激活
@export var activation_required_tags: FGameplayTagContainer = FGameplayTagContainer.new()

# 激活能力不能有的标签，有任何一个都不能激活
@export var activation_blocked_tags: FGameplayTagContainer = FGameplayTagContainer.new()

# 消耗GE(例如扣除蓝量)， 激活时施加给自身
@export var cost_ge: GASGameplayEffect

# 冷却GE，其granted_tag作为冷却标记，激活的时候施加给自身
@export var cooldown_ge: GASGameplayEffect

# 所属的asc，在调用give_ability的时候注入
var asc: GASAbilitySystemComponent

# 是否正在激活
var is_active: bool = false

# 生效的task
var _active_task: Array[GASAbilityTask] = []

# 能力能否激活
func can_activate() -> bool:
	# 如果能力正在施展，那么我们返回false
	if is_active: 
		GameLogger.info("GameplayAbility", "can_activate = false, is in activate")
		return false
	return _check_cooldown() and _check_block() and _check_cost() and _check_required()


"""
activate = "能力开始执行了"
commit_ability = "确认扣钱 + 开始冷却"
按下按钮 → activate (开始蓄力动画)
           ↓
        如果中途被眩晕打断 → end_ability(was_cancelled=true) → 没扣蓝、没进冷却
           ↓
        蓄力0.5秒完成 → commit_ability (扣蓝 + 进冷却) → 放出火球
因此active()和commit_ability会分开调用
"""
# 确认能力开始执行
func activate() -> void:
	is_active = true
	ability_activated.emit()
	GameLogger.info("GameplayAbility", "Ability activated")

# 扣除相对应的数值
func commit_ability() -> bool:
	if not asc: 
		return false
	if _check_cooldown() and _check_cost():
		if cost_ge:
			asc.apply_gameplay_effect_spec_to_self(GASEffectSpec.new(cost_ge))
		if cooldown_ge:
			asc.apply_gameplay_effect_spec_to_self(GASEffectSpec.new(cooldown_ge))
		GameLogger.info("GameplayAbility", "Cost & cooldown applied")
		return true
	return false

func end_ability(was_cancelled: bool) -> void:
	is_active = false
	for i in range(_active_task.size() - 1 , -1, -1):
		if _active_task[i].is_running:
			GameLogger.info("GameplayAbility", "Cancelling task [" + _active_task[i].name + "]")
			_active_task[i].end_task(true)
	assert(_active_task.is_empty(), "still some uncleared task")
	ability_ended.emit(self, was_cancelled)
	GameLogger.info("GameplayAbility", "Ending ability, cancelling active tasks")

# 如果能力正处于冷却状态，则返回false
func _check_cooldown() -> bool:
	if cooldown_ge and not cooldown_ge.granted_tag._tags.is_empty():
		for tag in cooldown_ge.granted_tag._tags:
			if asc.has_tag(tag):
				GameLogger.info("GameplayAbility", "_check_cooldown = false, in cooldown")
				return false
	return true

# 检查是否足够消耗
func _check_cost() -> bool:
	if cost_ge:
		for mod in cost_ge.modifiers:
			if mod.op == GASEnums.ModifierOp.ADD and mod.magnitude < 0:
				var attr_set = asc.find_attribute_set(mod.attr_name)
				if attr_set:
					var current = attr_set.get_attribute_value(mod.attr_name)
					if current + mod.magnitude < 0:
						GameLogger.info("GameplayAbility", "_check_cost = false, cost not enough")
						return false
				else:
					GameLogger.error("GameplayAbility", "no attr_name called " + mod.attr_name + " in attr_set")
					return false
	return true

# 如果能力被阻挠了，则返回false
func _check_block() -> bool:
	if not activation_blocked_tags._tags.is_empty():
		for tag in activation_blocked_tags._tags:
			if asc.has_tag(tag):
				GameLogger.info("GameplayAbility", "_check_block = false, asc block ability")
				return false
	return true

# 如果能力缺少了必要的tag，则返回false
func _check_required() -> bool:
	if not activation_required_tags._tags.is_empty():
		for tag in activation_required_tags._tags:
			if not asc.has_tag(tag):
				GameLogger.info("GameplayAbility", "_check_required = false, asc required need")
				return false
	return true
