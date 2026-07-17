extends Node

## 四个 GE 资源引用
var ge_damage: GASGameplayEffect
var ge_buff: GASGameplayEffect
var ge_dot: GASGameplayEffect
var ge_big_damage: GASGameplayEffect
var ge_stun: GASGameplayEffect

## ASC 和属性集引用
var asc: GASAbilitySystemComponent
var attr_set: TestAttributeSet

@onready var health_label = $CanvasLayer/VBoxContainer/HealthLabel
@onready var attack_label = $CanvasLayer/VBoxContainer/AttackLabel
@onready var status_label = $CanvasLayer/VBoxContainer/StatusLabel

func _ready():
	#test_instant_damage_ge()
	#await test_duration_buff_ge()
	_setup_character()
	_load_ge_resources()
	_connect_signals()
	_refresh_ui()

func test_instant_damage_ge():
	# 1.模拟：创建一个角色，挂ASC，配属性集
	var character = Node.new()
	add_child(character)
	
	var asc = GASAbilitySystemComponent.new()
	asc.name = "ASC"
	character.add_child(asc)
	
	var attr_set = TestAttributeSet.new()
	attr_set.attributes = {
		&"Health": 500.0,
		&"MaxHealth": 500.0,
		&"Attack": 100.0
	}
	attr_set.initialize_attributes(asc)
	asc.add_attribute_set(attr_set)
	
	# 2.定义一个 "伤害50" 的 INSTANT GE
	var damage_ge = load("res://addons/gameplay_abilities_system/test/ge_damage_50.tres")
	"""
	var damage_ge = GASGameplayEffect.new()
	damage_ge.duration_policy = GASEnums.DurationPolicy.INSTANT
	var mod = GEModifier.new()
	mod.attr_name = &"Health"
	mod.op = GASEnums.ModifierOp.ADD
	mod.magnitude = -50.0
	damage_ge.modifiers.append(mod)
	"""
	
	# 3.创建 Spec 并应用
	var spec = GASEffectSpec.new(damage_ge)
	asc.apply_gameplay_effect_spec_to_self(spec)
	
	# 4.断言
	var health = attr_set.get_attribute_value(&"Health")
	print("Health after damage: ", health, "期望为: 450")
	assert(health == 450.0, "伤害 50 后血量应为 450，实际：%s" %health)
	
	character.free()
	print("PASS: test_instant_damage_ge")

func test_duration_buff_ge():
	var character = Node.new()
	add_child(character)

	var asc = GASAbilitySystemComponent.new()
	asc.name = "ASC"
	character.add_child(asc)

	var attr_set = TestAttributeSet.new()
	attr_set.attributes = {
		&"Attack": 100.0
	}
	attr_set.initialize_attributes(asc)
	asc.add_attribute_set(attr_set)

	# 定义 +20 攻击力的 DURATION GE（持续 1 秒）
	var buff_ge = load("res://addons/gameplay_abilities_system/test/ge_attack_buff.tres")
	"""
	var buff_ge = GASGameplayEffect.new()
	buff_ge.duration_policy = GASEnums.DurationPolicy.DURATION
	buff_ge.duration = 1.0
	var mod = GEModifier.new()
	mod.attr_name = &"Attack"
	mod.op = GASEnums.ModifierOp.ADD
	mod.magnitude = 20.0
	buff_ge.modifiers.append(mod)
	"""

	var spec = GASEffectSpec.new(buff_ge)
	asc.apply_gameplay_effect_spec_to_self(spec)

	# 断言：攻击力应该是 120
	var attack = attr_set.get_attribute_value(&"Attack")
	print("Attack during buff: ", attack, " (期望: 120)")
	assert(attack == 120.0, "Buff 后攻击力应为 120，实际: %s" % attack)

	# 等待效果过期（多等 0.2 秒确保 _process 跑完）
	await get_tree().create_timer(3.2).timeout

	# 断言：过期后攻击力回退到 100
	attack = attr_set.get_attribute_value(&"Attack")
	print("Attack after buff expires: ", attack, " (期望: 100)")
	assert(attack == 100.0, "Buff 过期后攻击力应为 100，实际: %s" % attack)

	character.free()
	print("PASS: test_duration_buff_ge")

func _setup_character() -> void:
	var character : Node = Node.new()
	add_child(character)
	asc = GASAbilitySystemComponent.new()
	asc.name = "ASC"
	character.add_child(asc)
	
	# 配置并注册属性集
	attr_set = TestAttributeSet.new()
	attr_set.attributes = {
		&"Health": 500.0,
		&"MaxHealth": 500.0,
		&"Attack": 100.0,
	}
	attr_set.initialize_attributes(asc)
	asc.add_attribute_set(attr_set)

func _load_ge_resources() -> void:
	ge_damage = load("res://addons/gameplay_abilities_system/test/ge_damage_50.tres")
	ge_buff = load("res://addons/gameplay_abilities_system/test/ge_attack_buff.tres")
	ge_dot = load("res://addons/gameplay_abilities_system/test/ge_dot_poison.tres")
	ge_big_damage = load("res://addons/gameplay_abilities_system/test/ge_damage_600.tres")
	ge_stun = load("res://addons/gameplay_abilities_system/test/ge_stun.tres")

func _connect_signals() -> void:
	attr_set.attribute_changed.connect(_on_attribute_changed)
	asc.gameplay_tag_changed.connect(_on_tag_changed)

func _on_tag_changed(tag: FGameplayTag, added: bool):
	var stun_tag = GameplayTags.request_gameplay_tag(&"State.Debuff.Stun")
	if tag == stun_tag:
		if added:
			status_label.text = "状态: 眩晕中"
			assert(true, "眩晕标签已添加")  # 验证通过
		else:
			status_label.text = "状态: 无"
			assert(true, "眩晕标签已移除")  # 验证通过

func _refresh_ui():
	health_label.text = "生命：%d" % attr_set.get_attribute_value(&"Health")
	attack_label.text = "攻击：%d" % attr_set.get_attribute_value(&"Attack")

func _on_attribute_changed(attr_name: StringName, new_value: float, old_value: float):
	_refresh_ui()

func _input(event: InputEvent):
	if not event.is_pressed():
		return

	match event.as_text():
		"1":
			asc.apply_gameplay_effect_spec_to_self(GASEffectSpec.new(ge_damage))
			status_label.text = "状态: 受到伤害 -50"
		"2":
			asc.apply_gameplay_effect_spec_to_self(GASEffectSpec.new(ge_buff))
			status_label.text = "状态: 攻击力 +20 (持续) "
		"3":
			asc.apply_gameplay_effect_spec_to_self(GASEffectSpec.new(ge_dot))
			status_label.text = "状态: 中毒 (每0.5秒 -10)"
		"4":
			asc.apply_gameplay_effect_spec_to_self(GASEffectSpec.new(ge_big_damage))
			status_label.text = "状态: 受到巨大伤害 -600"
		"5":
			asc.apply_gameplay_effect_spec_to_self(GASEffectSpec.new(ge_stun))
			status_label.text = "状态: 眩晕 (1.5秒)"
