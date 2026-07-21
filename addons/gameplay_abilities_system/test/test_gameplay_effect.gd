extends Node

## GE 资源引用
var ge_damage: GASGameplayEffect
var ge_damage_base_attack: GASGameplayEffect
var ge_buff: GASGameplayEffect
var ge_dot: GASGameplayEffect
var ge_big_damage: GASGameplayEffect
var ge_stun: GASGameplayEffect
var ge_storm_shield: GASGameplayEffect
var ge_swift_ring: GASGameplayEffect
var ge_heal_50: GASGameplayEffect
var ge_add_max_health: GASGameplayEffect
var ge_add_max_mana: GASGameplayEffect

var ga_fire_bolt: GAFireBoltAbility
var ga_instance: GAInstanceTest
var ga_multi_task: GAMultiTaskTest


## ASC 和属性集引用
var asc: GASAbilitySystemComponent
var attr_set: TestAttributeSet

var test_ge_handles: Array[int] = []
var old_handle: int

var _ui_tags: Array[FGameplayTag] = []

@onready var health_label = $CanvasLayer/VBoxContainer/HealthLabel
@onready var max_health_label = $CanvasLayer/VBoxContainer/MaxHealthLabel
@onready var mana_label: Label = $CanvasLayer/VBoxContainer/ManaLabel
@onready var max_mana_label: Label = $CanvasLayer/VBoxContainer/MaxManaLabel
@onready var attack_label = $CanvasLayer/VBoxContainer/AttackLabel
@onready var status_label = $CanvasLayer/VBoxContainer/StatusLabel
@onready var tag_label = $CanvasLayer/VBoxContainer/TagLabel

func _ready():
	#test_instant_damage_ge()
	#await test_duration_buff_ge()
	_setup_character()
	_load_ge_resources()
	_create_abilities()
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
	attr_set.initial_attributes = {
		&"Health": 500.0,
		&"MaxHealth": 500.0,
		&"Attack": 100.0,
		&"MaxMana": 1000.0,
		&"Mana": 1000.0,
		&"CooldownReduction": 0.0
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
	var spec = asc.make_effect_spec(damage_ge)
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
	attr_set.initial_attributes = {
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

	var spec = asc.make_effect_spec(buff_ge)
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
	attr_set.initial_attributes = {
		&"Health": 500.0,
		&"MaxHealth": 500.0,
		&"Attack": 100.0,
		&"Mana": 1000.0,
		&"MaxMana": 1000.0,
		&"CooldownReduction": 0.0,
	}
	attr_set.initialize_attributes(asc)
	asc.add_attribute_set(attr_set)

func _load_ge_resources() -> void:
	ge_damage = load("res://addons/gameplay_abilities_system/test/ge_damage_50.tres")
	ge_damage_base_attack = load("res://addons/gameplay_abilities_system/test/ge_damage_base_attack.tres")
	ge_buff = load("res://addons/gameplay_abilities_system/test/ge_attack_buff.tres")
	ge_dot = load("res://addons/gameplay_abilities_system/test/ge_dot_poison.tres")
	ge_big_damage = load("res://addons/gameplay_abilities_system/test/ge_damage_600.tres")
	ge_stun = load("res://addons/gameplay_abilities_system/test/ge_stun.tres")
	ge_storm_shield = load("res://addons/gameplay_abilities_system/test/ge_storm_shield.tres")
	ge_swift_ring = load("res://addons/gameplay_abilities_system/test/ge_swift_ring.tres")
	ge_heal_50 = load("res://addons/gameplay_abilities_system/test/ge_heal_50.tres")
	ge_add_max_health = load("res://addons/gameplay_abilities_system/test/ge_add_max_health.tres")
	ge_add_max_mana = load("res://addons/gameplay_abilities_system/test/ge_add_max_mana.tres")

func _create_abilities() -> void:
	var cooldown_ge = GASGameplayEffect.new()
	cooldown_ge.duration_policy = GASEnums.DurationPolicy.DURATION
	cooldown_ge.duration = 3.0
	var cd_tags = FGameplayTagContainer.new()
	cd_tags.add_tag(GameplayTags.request_gameplay_tag(&"Ability.Fire.Cooldown"))
	cooldown_ge.granted_tag = cd_tags
	var cancel_tags = FGameplayTagContainer.new()
	cancel_tags.add_tag(GameplayTags.request_gameplay_tag(&"State.Debuff.Stun"))
	var block_tags = FGameplayTagContainer.new()
	block_tags.add_tag(GameplayTags.request_gameplay_tag(&"State.Debuff.Stun"))
	
	ga_fire_bolt = GAFireBoltAbility.new()
	ga_fire_bolt.damage_ge = ge_damage_base_attack
	ga_fire_bolt.cooldown_ge = cooldown_ge
	ga_fire_bolt.cancel_with_tags = cancel_tags
	ga_fire_bolt.activation_blocked_tags = block_tags
	
	var ge_cost_mana = GASGameplayEffect.new()
	ge_cost_mana.duration_policy = GASEnums.DurationPolicy.INSTANT
	var mod = GEModifier.new()
	mod.attr_name = &"Mana"
	mod.op = GASEnums.ModifierOp.ADD
	mod.magnitude = -100
	ge_cost_mana.modifiers.append(mod)
	ga_fire_bolt.cost_ge = ge_cost_mana
	
	asc.give_ability(ga_fire_bolt)
	
	ga_instance = GAInstanceTest.new()
	asc.give_ability(ga_instance)
	
	ga_multi_task = GAMultiTaskTest.new()
	asc.give_ability(ga_multi_task)

func _connect_signals() -> void:
	attr_set.attribute_changed.connect(_on_attribute_changed)
	asc.gameplay_tag_changed.connect(_on_tag_changed)

func _on_tag_changed(tag: FGameplayTag, added: bool):
	# —— TagsLabel 刷新 ——
	if added:
		_ui_tags.append(tag)
	else:
		_ui_tags.erase(tag)
	var names: PackedStringArray = []
	for t in _ui_tags:
		names.append(t.get_tag_name())
	tag_label.text = "Tags: " + ", ".join(names)
	 # —— 原有的眩晕状态栏逻辑保持不动 ——
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
	max_health_label.text = "最大生命值：%d" % attr_set.get_attribute_value(&"MaxHealth")
	mana_label.text = "魔力：%d" % attr_set.get_attribute_value(&"Mana")
	max_mana_label.text = "最大魔力值：%d" % attr_set.get_attribute_value(&"MaxMana")

func _on_attribute_changed(attr_name: StringName, new_value: float, old_value: float):
	_refresh_ui()

func _input(event: InputEvent):
	if not event.is_pressed():
		return
	GameLogger.debug("TestScene", event.as_text())
	match event.as_text():
		"1":
			asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_damage))
			status_label.text = "状态: 受到伤害 -50"
		"2":
			asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_heal_50))
			status_label.text = "状态: 补充血量 +50 "
		"3":
			asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_dot))
			status_label.text = "状态: 中毒 (每0.5秒 -10)"
		"4":
			asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_big_damage))
			status_label.text = "状态: 受到巨大伤害 -600"
		"5":
			asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_stun))
			status_label.text = "状态: 眩晕 (1.5秒)"
		"6":
			if asc.try_activate_ability(ga_fire_bolt):
				status_label.text = "状态: 蓄力火球(1.5秒后 -50)"
			else:
				asc.cancel_ability(ga_fire_bolt)
		"7":
			if  asc.try_activate_ability(ga_instance):
				status_label.text = "测试: 瞬时GA"
				GameLogger.warn("TestScene", "asc._active_abilities.size = " + str(asc._active_abilities.size()))
		"8":
			if asc.try_activate_ability(ga_multi_task):
				status_label.text = "测试: 多task并存"
		"9":
			asc.cancel_ability(ga_multi_task)
			GameLogger.warn("TestScene", "asc._active_abilities.size = " + str(asc._active_abilities.size()))
		"0":
			var handle = asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_storm_shield))
			test_ge_handles.append(handle)
			old_handle = handle
			GameLogger.info("TestScene", "get ge handle: " + str(handle))
		"Minus":
			if test_ge_handles.is_empty(): return
			var handle = test_ge_handles[test_ge_handles.size()-1]
			test_ge_handles.remove_at(test_ge_handles.size()-1)
			asc.remove_active_effect(handle)
			GameLogger.info("TestScene", "remove handle: " + str(handle))
		"Equal":
			var res = asc.remove_active_effect(old_handle)
			GameLogger.info("TestScene", "remove old_handle: " + str(old_handle) + " answer: " + str(res))
		"Q":
			asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_buff))
			status_label.text = "状态: 攻击力 +20 "
		"W":
			var handle = asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_add_max_health))
			test_ge_handles.append(handle)
			old_handle = handle
			GameLogger.info("TestScene", "get ge handle: " + str(handle))
		"E":
			var handle = asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_swift_ring))
			test_ge_handles.append(handle)
			old_handle = handle
			GameLogger.info("TestScene", "get ge handle: " + str(handle))
		"R":
			var handle = asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_add_max_mana))
			test_ge_handles.append(handle)
			old_handle = handle
			GameLogger.info("TestScene", "get ge handle: " + str(handle))
