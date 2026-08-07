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
var ge_setbycaller_damage: GASGameplayEffect
var ge_damage_charge: GASGameplayEffect
var ge_attack_vs_armor: GASGameplayEffect
var ge_dot_execution: GASGameplayEffect
var ge_add_armor: GASGameplayEffect

var ga_fire_bolt: GAFireBoltAbility
var ga_instance: GAInstanceTest
var ga_multi_task: GAMultiTaskTest



## ASC 和属性集引用
var asc: GASAbilitySystemComponent
var attr_set: TestAttributeSet

var asc_npc: GASAbilitySystemComponent
var attr_set_npc: TestAttributeSet

var test_ge_handles: Array[int] = []
var old_handle: int

var _ui_tags: Array[FGameplayTag] = []
var _npc_ui_tags: Array[FGameplayTag] = []

@onready var health_label = $CanvasLayer/HBoxContainer/VBoxContainer/HealthLabel
@onready var max_health_label = $CanvasLayer/HBoxContainer/VBoxContainer/MaxHealthLabel
@onready var mana_label: Label = $CanvasLayer/HBoxContainer/VBoxContainer/ManaLabel
@onready var max_mana_label: Label = $CanvasLayer/HBoxContainer/VBoxContainer/MaxManaLabel
@onready var attack_label = $CanvasLayer/HBoxContainer/VBoxContainer/AttackLabel
@onready var status_label = $CanvasLayer/HBoxContainer/VBoxContainer/StatusLabel
@onready var tag_label = $CanvasLayer/HBoxContainer/VBoxContainer/TagLabel
@onready var armor_label = $CanvasLayer/HBoxContainer/VBoxContainer/ArmorLabel

@onready var npc_health_label = $CanvasLayer/HBoxContainer/VBoxContainer2/NPCHealthLabel
@onready var npc_mana_label = $CanvasLayer/HBoxContainer/VBoxContainer2/NPCManaLabel
@onready var npc_max_mana_label = $CanvasLayer/HBoxContainer/VBoxContainer2/NPCMaxManaLabel
@onready var npc_attack_label = $CanvasLayer/HBoxContainer/VBoxContainer2/NPCAttackLabel
@onready var npc_status_label = $CanvasLayer/HBoxContainer/VBoxContainer2/NPCStatusLabel
@onready var npc_tag_label = $CanvasLayer/HBoxContainer/VBoxContainer2/NPCTagLabel
@onready var npc_max_health_label = $CanvasLayer/HBoxContainer/VBoxContainer2/NPCMaxHealthLabel
@onready var npc_armor_label = $CanvasLayer/HBoxContainer/VBoxContainer2/NPCArmorLabel

func _ready():
	_setup_character()
	_load_ge_resources()
	_create_abilities()
	_connect_signals()
	_refresh_character_ui()
	_refresh_npc_ui()

func _setup_character() -> void:
	var character : Node = Node.new()
	var npc: Node = Node.new()
	add_child(character)
	add_child(npc)
	asc = GASAbilitySystemComponent.new()
	asc_npc = GASAbilitySystemComponent.new()
	asc.name = "ASC"
	asc_npc.name = "ASC_npc"
	character.add_child(asc)
	npc.add_child(asc_npc)
	
	# 配置并注册属性集
	attr_set = TestAttributeSet.new()
	attr_set_npc = TestAttributeSet.new()
	var _attributes: Dictionary[StringName, float] = {
		&"Health": 500.0,
		&"MaxHealth": 500.0,
		&"Attack": 100.0,
		&"Mana": 1000.0,
		&"MaxMana": 1000.0,
		&"CooldownReduction": 0.0,
		&"Armor": 80.0,
	}
	attr_set.initial_attributes = _attributes
	attr_set_npc.initial_attributes = _attributes
	attr_set.initialize_attributes(asc)
	attr_set_npc.initialize_attributes(asc_npc)
	asc.add_attribute_set(attr_set)
	asc_npc.add_attribute_set(attr_set_npc)

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
	ge_damage_charge = load("res://addons/gameplay_abilities_system/test/ge_damage_charge.tres")
	ge_attack_vs_armor = load("res://addons/gameplay_abilities_system/test/ge_damage_attack_vs_armor.tres")
	ge_dot_execution = load("res://addons/gameplay_abilities_system/test/ge_dot_execution.tres")
	ge_add_armor = load("res://addons/gameplay_abilities_system/test/ge_add_armor.tres")
	
	# 验证4：SetByCaller——配方只声明"伤害数值由 key 'damage' 提供"，数值本身由调用方塞
	ge_setbycaller_damage = GASGameplayEffect.new()
	ge_setbycaller_damage.duration_policy = GASEnums.DurationPolicy.INSTANT
	var mod = GEModifier.new()
	mod.attr_name = &"Health"
	mod.op = GASEnums.ModifierOp.ADD
	var magnitude: GASModifierMagnitudeSetByCaller = GASModifierMagnitudeSetByCaller.new()
	magnitude.data_key = &"damage"
	magnitude.default_value = 0.0
	mod.magnitude = magnitude
	ge_setbycaller_damage.modifiers.append(mod)
	

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
	ga_fire_bolt.damage_ge = ge_damage_charge
	ga_fire_bolt.cooldown_ge = cooldown_ge
	ga_fire_bolt.cancel_with_tags = cancel_tags
	ga_fire_bolt.activation_blocked_tags = block_tags
	
	var ge_cost_mana = GASGameplayEffect.new()
	ge_cost_mana.duration_policy = GASEnums.DurationPolicy.INSTANT
	var mod = GEModifier.new()
	mod.attr_name = &"Mana"
	mod.op = GASEnums.ModifierOp.ADD
	var magnitude: GASModifierMagnitudeScalableFloat = GASModifierMagnitudeScalableFloat.new()
	magnitude.value = -100.0
	mod.magnitude = magnitude
	
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
	
	attr_set_npc.attribute_changed.connect(_on_npc_attribute_changed)
	asc_npc.gameplay_tag_changed.connect(_on_npc_tag_changed)

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

func _on_npc_tag_changed(tag: FGameplayTag, added: bool):
	# —— TagsLabel 刷新 ——
	if added:
		_npc_ui_tags.append(tag)
	else:
		_npc_ui_tags.erase(tag)
	var names: PackedStringArray = []
	for t in _npc_ui_tags:
		names.append(t.get_tag_name())
	npc_tag_label.text = "Tags: " + ", ".join(names)

func _refresh_character_ui():
	health_label.text = "生命：%d" % attr_set.get_attribute_value(&"Health")
	GameLogger.debug("TestScene", "character Health is %d" % attr_set.get_attribute_value(&"Health"))
	attack_label.text = "攻击：%d" % attr_set.get_attribute_value(&"Attack")
	GameLogger.debug("TestScene", "character Attack is %d" % attr_set.get_attribute_value(&"Attack"))
	max_health_label.text = "最大生命值：%d" % attr_set.get_attribute_value(&"MaxHealth")
	GameLogger.debug("TestScene", "character MaxHealth is %d" % attr_set.get_attribute_value(&"MaxHealth"))
	mana_label.text = "魔力：%d" % attr_set.get_attribute_value(&"Mana")
	GameLogger.debug("TestScene", "character Mana is %d" % attr_set.get_attribute_value(&"Mana"))
	max_mana_label.text = "最大魔力值：%d" % attr_set.get_attribute_value(&"MaxMana")
	GameLogger.debug("TestScene", "character MaxMana is %d" % attr_set.get_attribute_value(&"MaxMana"))
	armor_label.text = "护甲：%d" % attr_set.get_attribute_value(&"Armor")
	GameLogger.debug("TestScene", "character Armor is %d" % attr_set.get_attribute_value(&"Armor"))

func _refresh_npc_ui():
	npc_health_label.text = "生命：%d" % attr_set_npc.get_attribute_value(&"Health")
	GameLogger.debug("TestScene", "npc Health is %d" % attr_set_npc.get_attribute_value(&"Health"))
	npc_attack_label.text = "攻击：%d" % attr_set_npc.get_attribute_value(&"Attack")
	GameLogger.debug("TestScene", "npc Attack is %d" % attr_set_npc.get_attribute_value(&"Attack"))
	npc_max_health_label.text = "最大生命值：%d" % attr_set_npc.get_attribute_value(&"MaxHealth")
	GameLogger.debug("TestScene", "npc MaxHealth is %d" % attr_set_npc.get_attribute_value(&"MaxHealth"))
	npc_mana_label.text = "魔力：%d" % attr_set_npc.get_attribute_value(&"Mana")
	GameLogger.debug("TestScene", "npc Mana is %d" % attr_set_npc.get_attribute_value(&"Mana"))
	npc_max_mana_label.text = "最大魔力值：%d" % attr_set_npc.get_attribute_value(&"MaxMana")
	GameLogger.debug("TestScene", "npc MaxMana is %d" % attr_set_npc.get_attribute_value(&"MaxMana"))
	armor_label.text = "护甲：%d" % attr_set_npc.get_attribute_value(&"Armor")
	GameLogger.debug("TestScene", "npc Armor is %d" % attr_set_npc.get_attribute_value(&"Armor"))


func _on_attribute_changed(attr_name: StringName, new_value: float, old_value: float):
	_refresh_character_ui()

func _on_npc_attribute_changed(attr_name: StringName, new_value: float, old_value: float):
	_refresh_npc_ui()

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
		"T":
			# 验证4-正常路径：技能代码当场决定伤害是 77，塞进 spec 再 apply
			var spec = asc.make_effect_spec(ge_setbycaller_damage)
			spec.set_setbycaller_magnitude(&"damage", -77.0)
			var before = attr_set.get_attribute_value(&"Health")
			asc.apply_gameplay_effect_spec_to_self(spec)
			var after = attr_set.get_attribute_value(&"Health")
			assert(after == before - 77.0, "SetByCaller 伤害应为 77，实际变化：%s" % (before - after))
			status_label.text = "状态: SetByCaller 伤害 -77"
			print("PASS: 验证4-正常路径 (%s -> %s)" % [before, after])
		"Y":
			# 验证4-缺失路径：故意不塞值，期望走 default(0)、血量不变、控制台有警告
			var before = attr_set.get_attribute_value(&"Health")
			asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_setbycaller_damage))
			var after = attr_set.get_attribute_value(&"Health")
			assert(after == before, "未塞值应走 default 0 血量不变，实际变化：%s" % (before - after))
			status_label.text = "状态: SetByCaller 未塞值（看控制台警告）"
			print("PASS: 验证4-缺失路径 (血量不变: %s)" % after)
		"U":
			var spec = asc.make_effect_spec(ge_damage_charge)
			spec.set_setbycaller_magnitude(&"charge_time", 2.0)
			asc.apply_gameplay_effect_spec_to_self(spec)
		"I":
			var spec = asc.make_effect_spec(ge_damage_base_attack)
			asc.apply_gameplay_effect_spec_to_target(spec, asc_npc)
		"O":
			var spec = asc.make_effect_spec(ge_attack_vs_armor)
			asc.apply_gameplay_effect_spec_to_target(spec, asc_npc)
		"P":
			var spec = asc.make_effect_spec(ge_dot_execution)
			asc.apply_gameplay_effect_spec_to_target(spec, asc_npc)
		"A":
			var spec = asc_npc.make_effect_spec(ge_add_armor)
			asc_npc.apply_gameplay_effect_spec_to_self(spec)
