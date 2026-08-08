class_name DungeonGameTest
extends Node

var _pass_count := 0
var _fail_count := 0

func is_pass() -> bool:
	return _fail_count == 0

func get_pass_count() -> int:
	return _pass_count

func get_fail_count() -> int:
	return _fail_count

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + label)
	else:
		_fail_count += 1
		push_error("FAIL: " + label)

func run_all() -> void:
	await _run_basic_regression()
	await _run_gameplay_regression()
	await _run_endings_regression()
	print("=== 回归结束：%s（通过 %d / 失败 %d）===" % ["ALL PASS" if is_pass() else "HAS FAILURE", _pass_count, _fail_count])

func _timer(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _make_dummy(p_name: String, p_attrs: Dictionary[StringName, float]) -> DungeonEntity:
	var e := DungeonEntity.new()
	e.name = p_name
	add_child(e)
	e.setup(p_name, p_attrs)
	return e

func _new_game() -> DungeonGame:
	var g := DungeonGame.new()
	g.name = "TestGame"
	add_child(g)
	g.turn_delay = 0.0
	g.rng.seed = 42
	g.setup_default_game()
	g.start_game()
	return g

func _run_basic_regression() -> void:
	print("=== 基础框架回归 ===")
	var dummy := _make_dummy("木桩", {&"Body": 50.0, &"MaxBody": 100.0, &"Mind": 50.0, &"MaxMind": 50.0,
		&"Attack": 20.0, &"Defense": 5.0, &"Move": 2.0, &"Level": 3.0, &"CooldownReduction": 0.0})

	var heal_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test/game/items/ge_healing_potion.tres")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(heal_ge))
	_check(is_equal_approx(dummy.get_attr(&"Body"), 80.0), "基础-01 INSTANT 治疗 +30（50→80）")

	var hurt_ge := GASGameplayEffect.new()
	hurt_ge.duration_policy = GASEnums.DurationPolicy.INSTANT
	var hurt_mod := GEModifier.new()
	hurt_mod.attr_name = &"Body"
	hurt_mod.op = GASEnums.ModifierOp.ADD
	var hurt_mag: GASModifierMagnitudeSetByCaller = GASModifierMagnitudeSetByCaller.new()
	hurt_mag.data_key = &"damage"
	hurt_mag.default_value = 0.0
	hurt_mod.magnitude = hurt_mag
	hurt_ge.modifiers.append(hurt_mod)
	var hurt_spec := dummy.asc.make_effect_spec(hurt_ge)
	hurt_spec.set_setbycaller_magnitude(&"damage", -50.0)
	dummy.asc.apply_gameplay_effect_spec_to_self(hurt_spec)
	_check(is_equal_approx(dummy.get_attr(&"Body"), 30.0), "基础-02 SetByCaller INSTANT 伤害 -50（80→30）")

	var dot := GASGameplayEffect.new()
	dot.duration_policy = GASEnums.DurationPolicy.DURATION
	dot.duration = 2.5
	dot.period = 1.0
	var dot_mod := GEModifier.new()
	dot_mod.attr_name = &"Body"
	dot_mod.op = GASEnums.ModifierOp.ADD
	var dot_mag: GASModifierMagnitudeScalableFloat = GASModifierMagnitudeScalableFloat.new()
	dot_mag.value = -4.0
	dot_mod.magnitude = dot_mag
	dot.modifiers.append(dot_mod)
	var body_before := dummy.get_attr(&"Body")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(dot))
	await _timer(2.2)
	_check(is_equal_approx(dummy.get_attr(&"Body"), body_before - 8.0), "基础-03 DoT 两跳 -8（30→22）")
	await _timer(1.5)
	_check(is_equal_approx(dummy.get_attr(&"Body"), body_before - 8.0), "基础-04 DoT 到期停跳，伤害保留（22）")

	var sword_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test/game/gear/ge_sword.tres")
	var sword_handle := dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(sword_ge))
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 35.0), "基础-05 INFINITE 铁剑挂上 Attack +15（20→35）")
	_check(dummy.asc.remove_active_effect(sword_handle), "基础-06 凭票摘除返回 true")
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 20.0), "基础-07 摘除后回退 Attack 20")
	_check(not dummy.asc.remove_active_effect(sword_handle), "基础-08 旧票无害化：二次摘除返回 false")

	var belt_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test/game/gear/ge_giant_belt.tres")
	var heal_spec := dummy.asc.make_effect_spec(heal_ge)
	dummy.asc.apply_gameplay_effect_spec_to_self(heal_spec)
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(heal_ge))
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(heal_ge))
	_check(is_equal_approx(dummy.get_attr(&"Body"), 100.0), "基础-09 治疗溢出钳制在 MaxBody 100")
	var belt_handle := dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(belt_ge))
	_check(is_equal_approx(dummy.get_attr(&"MaxBody"), 160.0), "基础-10 巨人腰带 MaxBody +60")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(heal_ge))
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(heal_ge))
	_check(is_equal_approx(dummy.get_attr(&"Body"), 160.0), "基础-11 腰带加持下治疗至 MaxBody 160（100+30+30 钳制）")
	dummy.asc.remove_active_effect(belt_handle)
	_check(is_equal_approx(dummy.get_attr(&"MaxBody"), 100.0), "基础-12 摘除腰带 MaxBody 回 100")
	_check(is_equal_approx(dummy.get_attr(&"Body"), 100.0), "基础-13 MaxBody 下降联动 Body 收缩至 100")

	var focus := GASGameplayEffect.new()
	focus.duration_policy = GASEnums.DurationPolicy.INFINITE
	focus.stack_policy = GASEnums.StackingPolicy.LIMITED
	focus.stack_limit = 2
	var focus_mod := GEModifier.new()
	focus_mod.attr_name = &"Attack"
	focus_mod.op = GASEnums.ModifierOp.ADD
	var focus_mag: GASModifierMagnitudeScalableFloat = GASModifierMagnitudeScalableFloat.new()
	focus_mag.value = 10.0
	focus_mod.magnitude = focus_mag
	focus.modifiers.append(focus_mod)
	var focus_handle_1 := dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(focus))
	var focus_handle_2 := dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(focus))
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 40.0), "基础-14 LIMITED 叠两层 +20（20→40）")
	_check(dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(focus)) == GASAbilitySystemComponent.INVALID_HANDLE, "基础-15 第三层被堆叠上限拒绝")
	_check(dummy.asc.get_stack_count(focus_handle_1) == 2, "基础-16 叠层计数为 2")
	dummy.asc.remove_active_effect(focus_handle_1)
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 20.0), "基础-17 LIMITED 单条目：移除即清整叠层（回退 20）")

	var warcry := GASGameplayEffect.new()
	warcry.duration_policy = GASEnums.DurationPolicy.INFINITE
	warcry.relevant_attributes.append(GASCaptureDefinition.new(&"MaxBody", false))
	var warcry_mod := GEModifier.new()
	warcry_mod.attr_name = &"Attack"
	warcry_mod.op = GASEnums.ModifierOp.ADD
	var warcry_mag: GASModifierMagnitudeAttributeBased = GASModifierMagnitudeAttributeBased.new()
	warcry_mag.attr_name = &"MaxBody"
	warcry_mag.coefficient = 0.3
	warcry_mag.snapshot = false
	warcry_mag.from_target = false
	warcry_mod.magnitude = warcry_mag
	warcry.modifiers.append(warcry_mod)
	var warcry_handle := dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(warcry))
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 50.0), "基础-18 跨墙依赖：战吼 Attack += 30%×MaxBody（100→+30，共50）")
	dummy.attr_set.apply_base_value_change(&"MaxBody", 100.0)
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 80.0), "基础-19 MaxBody 200 → 实时重算 Attack +60（共80）")
	dummy.asc.remove_active_effect(warcry_handle)
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 20.0), "基础-20 拆线回退 Attack 20")

	var sbc_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test/game/spells/ge_fireball_damage.tres")
	var sbc_before := dummy.get_attr(&"Body")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(sbc_ge))
	_check(is_equal_approx(dummy.get_attr(&"Body"), sbc_before), "基础-21 SetByCaller 缺省走 default 0（血量不变）")

	var curve_ge := GASGameplayEffect.new()
	curve_ge.duration_policy = GASEnums.DurationPolicy.INSTANT
	var curve_mod := GEModifier.new()
	curve_mod.attr_name = &"Body"
	curve_mod.op = GASEnums.ModifierOp.ADD
	var curve_mag: GASModifierMagnitudeScalableFloat = GASModifierMagnitudeScalableFloat.new()
	curve_mag.set_level_curve_from_points(PackedVector2Array([Vector2(0, -10.0), Vector2(2, -14.0), Vector2(4, -18.0)]))
	curve_mod.magnitude = curve_mag
	curve_ge.modifiers.append(curve_mod)
	var c1 := dummy.get_attr(&"Body")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(curve_ge, 1.0))
	_check(is_equal_approx(dummy.get_attr(&"Body"), c1 - 12.0), "基础-22 等级曲线 level=1 线性插值 -12")
	var c2 := dummy.get_attr(&"Body")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(curve_ge, 3.0))
	_check(is_equal_approx(dummy.get_attr(&"Body"), c2 - 16.0), "基础-23 等级曲线 level=3 外推 -16")

	var stun_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test/game/monsters/ge_skeleton_stun.tres")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(stun_ge))
	_check(dummy.is_stunned(), "基础-24 纯标签 GE 授予 Stun")
	var dispel_query := FGameplayTagContainer.new()
	dispel_query.add_tag(GameplayTags.request_gameplay_tag(&"State.Debuff"))
	var removed := dummy.asc.remove_active_effects_with_tags(dispel_query)
	_check(removed >= 1, "基础-25 按 State.Debuff 驱散移除 %d 个效果" % removed)
	_check(not dummy.is_stunned(), "基础-26 驱散后 Stun 撤销")
	dummy.queue_free()
	await _timer(0.1)

func _run_gameplay_regression() -> void:
	print("=== 地城桌游回归 ===")
	var g := _new_game()
	var hero := g.hero
	var goblin: DungeonMonster = g.monsters[0]
	var skeleton: DungeonMonster = g.monsters[1]
	var orc: DungeonMonster = g.monsters[2]
	var venom: DungeonMonster = g.monsters[3]

	_check(is_equal_approx(hero.get_attr(&"Body"), 100.0), "桌游-01 勇者初始 Body 100")
	_check(is_equal_approx(hero.get_attr(&"Attack"), 35.0), "桌游-02 初始攻击 35（20+铁剑15）")
	_check(hero.get_gear_name(DungeonHero.GEAR_SLOT_WEAPON) == "ge_sword", "桌游-03 初始装备铁剑")
	_check(g.moves_left == 2, "桌游-04 回合移动步数 = Move 2")

	_check(g.hero_move(1), "桌游-05 移动至第 1 格")
	_check(g.hero_move(1), "桌游-06 移动至第 2 格（陷阱）")
	var trap_body := hero.get_attr(&"Body")
	_check(trap_body >= 100.0 - 30.0 and trap_body <= 100.0 - 15.0, "桌游-07 陷阱 SetByCaller 伤害 15~30（实际 %d）" % int(100.0 - trap_body))
	_check(not g.hero_move(1), "桌游-08 步数耗尽无法再移动")

	var catalog: Dictionary = g.get_gear_catalog()
	_check(hero.equip_gear(catalog["ge_great_sword"].ge, DungeonHero.GEAR_SLOT_WEAPON, "ge_great_sword"), "桌游-09 换装大剑")
	_check(is_equal_approx(hero.get_attr(&"Attack"), 50.0), "桌游-10 换装后 Attack 50（旧铁剑已摘）")

	var fireball: GASGameplayAbility = hero.spells[&"Ability.Spell.Fireball"]
	_check(g.hero_cast(fireball, goblin), "桌游-11 火球开始蓄力（0.6s）")
	var mind_before := hero.get_attr(&"Mind")
	var stun_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test/game/monsters/ge_skeleton_stun.tres")
	hero.asc.apply_gameplay_effect_spec_to_self(hero.asc.make_effect_spec(stun_ge))
	await _timer(1.0)
	_check(is_equal_approx(hero.get_attr(&"Mind"), mind_before), "桌游-12 蓄力中被眩晕打断，未扣 Mind（cancel 不 commit）")
	_check(not fireball.is_active, "桌游-13 火球能力已结束")
	var debuff_query := FGameplayTagContainer.new()
	debuff_query.add_tag(GameplayTags.request_gameplay_tag(&"State.Debuff"))
	hero.asc.remove_active_effects_with_tags(debuff_query)

	g.hero_end_turn()
	await _timer(0.2)
	_check(is_equal_approx(hero.get_attr(&"Body"), trap_body - 10.0), "桌游-14 哥布林反击伤害 10（15-防御5）")
	_check(not hero.is_stunned(), "桌游-15 哥布林无眩晕附加")
	_check(venom.board_index == 6, "桌游-16 毒蛇逼近到第 6 格")
	_check(orc.board_index == 5, "桌游-17 兽人被前排挡住停在 5")
	_check(skeleton.board_index == 4, "桌游-18 骷髅被哥布林挡住停在 4")

	_check(g.hero_attack(goblin), "桌游-19 近战攻击哥布林")
	_check(is_equal_approx(goblin.get_attr(&"Body"), 0.0), "桌游-20 伤害 48 溢出 45 并钳制为 0")
	_check(not goblin.is_alive(), "桌游-21 哥布林被一击击杀")
	_check(not g.hero_attack(goblin), "桌游-22 尸体不可再攻击")
	_check(not g.hero_cast(fireball, skeleton), "桌游-23 行动次数已用尽，本回合无法再施法")

	g.hero_end_turn()
	await _timer(0.2)
	_check(not hero.is_stunned(), "桌游-24 骷髅上前一格（4→3），贴脸未及攻击")
	await _timer(1.4)
	_check(g.hero_attack(skeleton), "桌游-25 近战骷髅（等过 1.2s 攻击冷却）")
	_check(is_equal_approx(skeleton.get_attr(&"Body"), 6.0), "桌游-26 骷髅 50-44 剩 6 点")
	_check(not g.hero_cast(hero.spells[&"Ability.Spell.Heal"]), "桌游-27 行动次数已用尽，无法施法")

	g.hero_end_turn()
	await _timer(0.2)
	_check(hero.is_stunned(), "桌游-28 骷髅贴脸攻击并眩晕（18-防御5=13）")
	_check(not g.hero_attack(skeleton), "桌游-29 眩晕门禁：无法攻击")
	_check(not g.hero_cast(hero.spells[&"Ability.Spell.Heal"]), "桌游-30 眩晕门禁：无法施法")
	await _timer(2.3)
	_check(not hero.is_stunned(), "桌游-31 眩晕 2s 到期撤销")

	var heal: GASGameplayAbility = hero.spells[&"Ability.Spell.Heal"]
	var body_before_heal := hero.get_attr(&"Body")
	_check(g.hero_cast(heal), "桌游-32 施放治疗术")
	_check(is_equal_approx(hero.get_attr(&"Mind"), 40.0), "桌游-33 治疗消耗 Mind -10（50→40）")
	_check(is_equal_approx(hero.get_attr(&"Body"), minf(body_before_heal + 40.0, hero.get_attr(&"MaxBody"))), "桌游-34 治疗 +40（溢出钳制在 MaxBody）")

	g.hero_end_turn()
	await _timer(0.2)
	_check(hero.is_stunned(), "桌游-35 骷髅反击眩晕")
	hero.asc.remove_active_effects_with_tags(debuff_query)
	_check(not hero.is_stunned(), "桌游-36 驱散 Stun 恢复行动")

	var poison: GASGameplayAbility = hero.spells[&"Ability.Spell.PoisonCloud"]
	_check(g.hero_cast(poison, orc), "桌游-37 毒雾术命中兽人")
	_check(is_equal_approx(hero.get_attr(&"Mind"), 20.0), "桌游-38 毒雾消耗 Mind -20（40→20）")
	_check(orc.asc.has_tag(GameplayTags.request_gameplay_tag(&"State.Debuff.Poison")), "桌游-39 兽人挂上 Poison 标签")
	var orc_poison_before := orc.get_attr(&"Body")
	await _timer(2.2)
	_check(is_equal_approx(orc.get_attr(&"Body"), orc_poison_before - 12.0), "桌游-40 毒雾 DoT 两跳 -12")

	g.hero_end_turn()
	await _timer(0.2)
	_check(hero.is_stunned(), "桌游-41 骷髅反击眩晕")
	hero.asc.remove_active_effects_with_tags(debuff_query)
	_check(not hero.is_stunned(), "桌游-42 驱散 Stun 恢复行动")

	var frost: GASGameplayAbility = hero.spells[&"Ability.Spell.FrostNova"]
	_check(g.hero_cast(frost, venom), "桌游-43 冰霜新星命中毒蛇")
	_check(is_equal_approx(hero.get_attr(&"Mind"), 5.0), "桌游-44 冰霜消耗 Mind -15（20→5）")
	_check(venom.get_attr(&"Move") <= 0.0, "桌游-45 毒蛇 Move ≤ 0（被减速）")

	g.hero_end_turn()
	await _timer(0.2)
	_check(venom.board_index == 5, "桌游-46 冰霜生效：毒蛇原地不动（Move≤0）")
	_check(hero.is_stunned(), "桌游-47 骷髅反击眩晕")
	hero.asc.remove_active_effects_with_tags(debuff_query)
	_check(not hero.is_stunned(), "桌游-48 驱散 Stun 恢复行动")

	_check(not g.hero_cast(fireball, orc), "桌游-49 法力不足：火球消耗 15 > 当前 5，门禁拒绝")
	_check(g.hero_use_potion("mana"), "桌游-50 饮用法力药水（本回合行动已用）")
	_check(is_equal_approx(hero.get_attr(&"Mind"), 35.0), "桌游-51 法力 +30（5→35）")
	_check(not g.hero_cast(fireball, orc), "桌游-52 行动次数已用尽，火球需等下一回合")

	g.hero_end_turn()
	await _timer(0.2)
	_check(hero.is_stunned(), "桌游-53 骷髅反击眩晕")
	hero.asc.remove_active_effects_with_tags(debuff_query)
	_check(not hero.is_stunned(), "桌游-54 驱散 Stun 恢复行动")

	_check(g.hero_cast(fireball, orc), "桌游-55 火球命中兽人（伤害 30+3×10=60）")
	await _timer(0.8)
	_check(is_equal_approx(hero.get_attr(&"Mind"), 20.0), "桌游-56 火球消耗 Mind -15（35→20）")
	_check(hero.asc.has_tag(GameplayTags.request_gameplay_tag(&"Ability.Spell.Fireball.Cooldown")), "桌游-57 火球冷却标签授予")
	_check(orc.get_attr(&"Body") <= 3.0, "桌游-58 兽人遭重创（剩余 ≤3，余毒即将致命）")
	_check(not g.hero_cast(fireball, venom), "桌游-59 行动次数已用尽，本回合无法再施法")

	g.hero_end_turn()
	await _timer(0.5)
	_check(not orc.is_alive(), "桌游-60 余毒结算，兽人阵亡")
	_check(venom.board_index == 5, "桌游-61 毒蛇仍被冻结无法逼近")
	_check(hero.is_stunned(), "桌游-62 骷髅反击眩晕")
	hero.asc.remove_active_effects_with_tags(debuff_query)
	_check(not hero.is_stunned(), "桌游-63 驱散 Stun 恢复行动")

	_check(not g.hero_cast(fireball, venom), "桌游-64 冷却门禁：火球的 4s 冷却仍在，被拒绝")
	var spell_query := FGameplayTagContainer.new()
	spell_query.add_tag(GameplayTags.request_gameplay_tag(&"Ability.Spell"))
	var dispelled := hero.asc.remove_active_effects_with_tags(spell_query)
	_check(dispelled >= 1, "桌游-65 驱散冷却（移除 %d 个）" % dispelled)
	_check(g.hero_cast(fireball, venom), "桌游-66 火球命中毒蛇（40-60）")
	await _timer(0.8)
	_check(not venom.is_alive(), "桌游-67 毒蛇被击杀")

	g.hero_end_turn()
	await _timer(0.2)
	_check(hero.is_stunned(), "桌游-68 骷髅独自反击眩晕")
	hero.asc.remove_active_effects_with_tags(debuff_query)
	_check(g.hero_attack(skeleton), "桌游-69 近战骷髅")
	_check(is_equal_approx(skeleton.get_attr(&"Body"), 0.0), "桌游-70 骷髅 6-44 溢出钳制为 0")
	_check(not skeleton.is_alive(), "桌游-71 骷髅被击杀")

	_check(g.phase == DungeonGame.Phase.VICTORY, "桌游-72 全歼怪物 → 胜利")

	g.queue_free()
	await _timer(0.1)

func _run_endings_regression() -> void:
	print("=== 结局路径回归 ===")
	var win := DungeonGame.new()
	win.name = "WinGame"
	add_child(win)
	win.turn_delay = 0.0
	var win_tiles: Array[int] = [DungeonBoard.TileType.EMPTY, DungeonBoard.TileType.EMPTY, DungeonBoard.TileType.EXIT]
	var win_attrs: Dictionary[StringName, float] = {&"Body": 100.0, &"MaxBody": 100.0, &"Mind": 50.0, &"MaxMind": 50.0,
		&"Attack": 20.0, &"Defense": 5.0, &"Move": 2.0, &"Level": 1.0, &"CooldownReduction": 0.0}
	win.setup_game(win_tiles, win_attrs, [], [])
	win.start_game()
	_check(win.hero_move(1), "结局-01 走向出口 1")
	_check(win.hero_move(1), "结局-02 踏出出口")
	_check(win.phase == DungeonGame.Phase.VICTORY, "结局-03 抵达终点 → 胜利")
	win.queue_free()
	await _timer(0.1)

	var lose := DungeonGame.new()
	lose.name = "LoseGame"
	add_child(lose)
	lose.turn_delay = 0.0
	var lose_tiles: Array[int] = [DungeonBoard.TileType.EMPTY, DungeonBoard.TileType.EMPTY, DungeonBoard.TileType.EXIT]
	var lose_attrs: Dictionary[StringName, float] = {&"Body": 20.0, &"MaxBody": 100.0, &"Mind": 50.0, &"MaxMind": 50.0,
		&"Attack": 20.0, &"Defense": 0.0, &"Move": 2.0, &"Level": 1.0, &"CooldownReduction": 0.0}
	var killer_cfg: Array[Dictionary] = [{"name": "屠夫", "pos": 1, "kind": DungeonMonster.MonsterKind.CHARGER, "attrs": {
		&"Body": 50.0, &"MaxBody": 50.0, &"Attack": 30.0, &"Defense": 5.0, &"Move": 1.0,
		&"Mind": 0.0, &"MaxMind": 0.0, &"Level": 1.0, &"CooldownReduction": 0.0}}]
	lose.setup_game(lose_tiles, lose_attrs, [], killer_cfg)
	lose.start_game()
	lose.hero_end_turn()
	await _timer(0.2)
	_check(lose.phase == DungeonGame.Phase.DEFEAT, "结局-04 体力归零 → 失败")
	lose.queue_free()
	await _timer(0.1)
