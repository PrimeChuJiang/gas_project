class_name GASAttributeSet
extends Resource


signal attribute_changed(attr_name: StringName, new_value: float, old_value: float)
# 仅在 initialize_attributes 时发射;需在初始化前连接,迟到的监听者请改用 get_attribute_value() 拉取
signal attribute_initialized(attr_name: StringName, value: float)

# 编辑器内静态配置属性，结构为{attribute_name(StringName) : data(float)}
@export var initial_attributes : Dictionary[StringName, float] = {}

# 运行时实际工作的属性映射表，结构为{attribute_name(StringName) : data(AttributeData)}
"""
_attributes = {
	&"Health":    <GASAttributeDATA>{ base_value: 500, _modifiers: [...], _dirty: bool, _cached_value: 500 },
	&"MaxHealth": <GASAttributeDATA>{ base_value: 500, _modifiers: [...], _dirty: bool, _cached_value: 500 },
	&"Attack":    <GASAttributeDATA>{ base_value: 100, _modifiers: [...], _dirty: bool, _cached_value: 100 },
	&"Mana":      <GASAttributeDATA>{ base_value: 300, _modifiers: [...], _dirty: bool, _cached_value: 300 },
}
"""
var _attributes: Dictionary[StringName, GASAttributeDATA] = {}
# 宿主ASC
var asc : GASAbilitySystemComponent = null 

# 初始化运行数据
func initialize_attributes(owner_asc: GASAbilitySystemComponent):
	self.asc = owner_asc
	for attr_name in initial_attributes.keys():
		var data = GASAttributeDATA.new()
		data.base_value = initial_attributes[attr_name]
		_attributes[attr_name] = data
		attribute_initialized.emit(attr_name, initial_attributes[attr_name])

# 获取最终计算值
func get_attribute_value(attr_name: StringName) -> float:
	if _attributes.has(attr_name):
		return _attributes[attr_name].current_value
	return 0.0

# 应用BaseValue修改(带Pre钳制)
func apply_base_value_change(attr_name: StringName, delta: float) -> float:
	if not _attributes.has(attr_name):
		return 0.0
	var data: GASAttributeDATA = _attributes[attr_name]
	var old_base = data.base_value
	var new_base = pre_attribute_change(attr_name, data.base_value + delta)
	var old_current = data.current_value
	data.set_base_value(new_base)
	if data.current_value != old_current:
		attribute_changed.emit(attr_name, data.current_value, old_current)
	return new_base - old_base

# 添加/移除修改器(带信号)
func apply_modifier(attr_name: StringName, handle: int, op: GASEnums.ModifierOp, magnitude: float) -> void:
	if not _attributes.has(attr_name):
		return
	var data: GASAttributeDATA = _attributes[attr_name]
	var old_value = data.current_value
	data.add_modifier(handle, op, magnitude)
	if data.current_value != old_value:
		attribute_changed.emit(attr_name, data.current_value, old_value)

func remove_modifier(attr_name: StringName, handle: int):
	if not _attributes.has(attr_name):
		return
	var data: GASAttributeDATA = _attributes[attr_name]
	var old_value = data.current_value
	data.remove_modifier(handle)
	if data.current_value != old_value:
		attribute_changed.emit(attr_name, data.current_value, old_value)

func apply_modifiers_to_base(attr_name: StringName, modifiers: Array[GASModifierPile]) -> void:
	var data = _attributes[attr_name]
	if data:
		var final = GASAttributeDATA.evaluate(data.base_value, modifiers)
		apply_base_value_change(attr_name, final - data.base_value)
	else:
		GameLogger.error("GASAttributeSet", "can't find data in _attributes[%s]!" % attr_name)

## PreAttributeChange: BaseValue 写入前的拦截器（门禁）
##
## 职责：
##   接收提议的新 BaseValue → 钳制到合法范围 → 返回审批后的值
##
## 规则：
##   1. 只做纯函数：给一个值，返回修正后的值，不修改其他属性（防止递归）
##   2. 不在此处处理连锁反应（溢出转护盾、死亡检测等），那些交给 PostGameplayEffectExecute
##   3. 不钳制 CurrentValue，只钳制 BaseValue
##      ——因为 CurrentValue = BaseValue + 临时 Modifiers，超出上限是 Buff 预期的行为
##      ——BaseValue 才是永久存储，需要有合法性下限（如血量不能为负）
##
## 外部不应直接调 data.set_base_value()，写入入口只有 apply_base_value_change() 这一个
func pre_attribute_change(attr_name: StringName, new_value: float) -> float:
	return new_value

## PostGameplayEffectExecute: GE 所有 Modifier 应用完毕后的连锁反应阶段
##
## 职责：
##   1. 读取 Meta Attribute（如 IncomingDamage），按优先级分配到具体属性
##      （护盾 → 血量 → 溢出）
##   2. 处理属性变化引发的连锁逻辑（血量归零 → 死亡、治疗溢出 → 转护盾）
##   3. 消费并清空 Meta Attribute（它是临时传值容器，不持久化）
##
## 为什么不在 Modifier 聚合阶段做？
##   Modifier 的计算是无优先级的纯聚合（加→乘→除），无法插入"护盾先扛"这种有序决策
##   所以伤害量由 GE 写入 Meta Attribute，分配逻辑放在这里处理
## 常见 Meta Attribute 示例：
##
##   IncomingDamage    收到的原始伤害（护甲/护盾减免前）
##   IncomingHealing   收到的原始治疗量
##   OutgoingDamage    打出的原始伤害
##   ShieldAbsorption  护盾吸收量
##   FinalDamage       最终实际伤害（减免处理后的落地值）
##   OverkillDamage    溢出伤害（目标死亡后的多余伤害，用于碎尸/鞭尸效果）
##   BonusExperience   额外经验值
##   ThreatGenerated   生成的仇恨值
##
## 共性：都是 GE 计算出的"临时中间值"，不持久化、不复用、每次 GE 消费后立刻归零
func post_gameplay_effect_execute(effect_spec: GASEffectSpec):
	pass
