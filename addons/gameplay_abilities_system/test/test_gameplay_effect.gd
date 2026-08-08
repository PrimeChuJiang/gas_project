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
var ge_buff_armor_from_attack: GASGameplayEffect

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
	ge_buff_armor_from_attack = load("res://addons/gameplay_abilities_system/test/ge_buff_armor_from_attack.tres")
	
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
			assert(asc.has_tag(stun_tag), "眩晕 tag 添加后 has_tag 应为 true")
		else:
			status_label.text = "状态: 无"
			assert(not asc.has_tag(stun_tag), "眩晕 tag 移除后 has_tag 应为 false")

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
	npc_armor_label.text = "护甲：%d" % attr_set_npc.get_attribute_value(&"Armor")
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
			status_label.text = "状态: 中毒 (每0.5秒 -5)"
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
		"S":
			var spec = asc.make_effect_spec(ge_buff_armor_from_attack)
			asc.apply_gameplay_effect_spec_to_target(spec, asc_npc)
		"F":
			_run_auto_regression()

## 一键自动化回归（增量断言，可从任意场景状态开始跑）
## 覆盖：INSTANT 伤害/治疗/MULTIPLY 砍半、DoT 周期与到期、INFINITE 挂摘、
##       跨墙依赖实时重算与拆线
func _run_auto_regression() -> void:
	print("=== 自动化回归开始 ===")
	# 1. INSTANT 伤害 -50
	var h := attr_set.get_attribute_value(&"Health")
	asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_damage))
	assert(attr_set.get_attribute_value(&"Health") == h - 50.0, "1 INSTANT 伤害应为 -50")
	print("PASS: 1 INSTANT 伤害 -50")
	# 2. INSTANT 治疗 +50
	h = attr_set.get_attribute_value(&"Health")
	asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_heal_50))
	assert(attr_set.get_attribute_value(&"Health") == h + 50.0, "2 INSTANT 治疗应为 +50")
	print("PASS: 2 INSTANT 治疗 +50")
	# 3. INSTANT MULTIPLY -0.5 砍半（聚合器验证目标 2 的常驻配方）
	h = attr_set.get_attribute_value(&"Health")
	asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_big_damage))
	assert(attr_set.get_attribute_value(&"Health") == h * 0.5, "3 MULTIPLY -0.5 应砍半")
	print("PASS: 3 MULTIPLY -0.5 砍半")
	# 4. DoT 每 0.5s -5，到期回退
	h = attr_set.get_attribute_value(&"Health")
	asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_dot))
	await get_tree().create_timer(1.2).timeout   # 0.5/1.0 两跳，1.5 第三跳未到
	assert(attr_set.get_attribute_value(&"Health") == h - 10.0, "4a DoT 两跳应为 -10")
	print("PASS: 4a DoT 两跳 -10")
	await get_tree().create_timer(1.5).timeout   # 2.7s > 2.1s 到期（第 3/4 跳在 1.5/2.0 已结算）
	assert(attr_set.get_attribute_value(&"Health") == h - 20.0, "4b DoT 到期停跳但伤害保留（周期落账是买断）")
	print("PASS: 4b DoT 到期停跳，总伤 -20 保留")
	# 5. INFINITE 挂/摘
	var a := attr_set.get_attribute_value(&"Attack")
	var shield_handle := asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_storm_shield))
	assert(attr_set.get_attribute_value(&"Attack") == a + 50.0, "5a INFINITE 应 +50")
	assert(asc.remove_active_effect(shield_handle), "5b 票移除应为 true")
	assert(attr_set.get_attribute_value(&"Attack") == a, "5c 摘后应回退")
	print("PASS: 5 INFINITE 挂摘")
	# 6. 跨墙依赖：挂上生效 / 实时跟涨 / 拆线
	var armor := attr_set_npc.get_attribute_value(&"Armor")
	var attack_before := attr_set.get_attribute_value(&"Attack")
	var armor_handle := asc.apply_gameplay_effect_spec_to_target(asc.make_effect_spec(ge_buff_armor_from_attack), asc_npc)
	assert(is_equal_approx(attr_set_npc.get_attribute_value(&"Armor"), armor + 30.0), "6a 挂上应 +30")
	print("PASS: 6a 挂上 +30")
	asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge_buff))
	assert(attr_set.get_attribute_value(&"Attack") == attack_before + 50.0, "6b Attack buff 应生效")
	assert(is_equal_approx(attr_set_npc.get_attribute_value(&"Armor"), armor + 45.0), "6c 实时跟涨应 +45")
	print("PASS: 6b/c 跨墙实时重算（两段对照死刑一）")
	asc_npc.remove_active_effect(armor_handle)
	assert(is_equal_approx(attr_set_npc.get_attribute_value(&"Armor"), armor), "6d 拆线后 Armor 应回退")
	assert(is_equal_approx(attr_set_npc.get_attribute_value(&"Armor"), armor), "6e Attack 仍在 150，Armor 纹丝不动（尸体听者反证）")
	print("PASS: 6d/e 拆线干净")
	await get_tree().create_timer(3.2).timeout   # Attack buff 3.0s 到期
	assert(attr_set.get_attribute_value(&"Attack") == attack_before, "6f Attack buff 到期回退")
	assert(is_equal_approx(attr_set_npc.get_attribute_value(&"Armor"), armor), "6g 到期后 Armor 仍不动")
	print("PASS: 6f/g 全链路收尾")
	print("=== 自动化回归全部通过 ===")
