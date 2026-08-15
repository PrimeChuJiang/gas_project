class_name TopdownGameTest
extends Node

var _pass_count := 0
var _fail_count := 0
var _chest_opened := false
var _monster_dead := false
var _monster_respawned := false
var _game_over_flag := false

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
	await _run_presentation_smoke()
	await _run_smite_regression()
	await _run_combo_regression()
	await _run_berserk_regression()
	print("=== 回归结束：%s（通过 %d / 失败 %d）===" % ["ALL PASS" if is_pass() else "HAS FAILURE", _pass_count, _fail_count])

func _timer(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _new_game() -> TopdownGame:
	var g := TopdownGame.new()
	g.name = "TestTopdownGame"
	add_child(g)
	g._rng.seed = 42
	g.start_game()
	return g

func _make_dummy(p_name: String, p_attrs: Dictionary[StringName, float]) -> TopdownEntity:
	var e := TopdownEntity.new()
	e.name = p_name
	add_child(e)
	e.setup_entity(p_name, p_attrs)
	return e

## ---------------- 表现层冒烟（真实击杀 → 死亡动画 → freed 实体清理） ----------------

func _run_presentation_smoke() -> void:
	print("=== 表现层冒烟 ===")
	var scene := get_parent() as Node
	if scene == null or not "game" in scene:
		_check(false, "表现层-00 测试挂在 TopdownDungeon 场景下")
		return
	var sg: TopdownGame = scene.get("game")
	if sg == null or sg.monsters.is_empty():
		_check(false, "表现层-00 场景 game 可用")
		return
	var victim := sg.monsters[0]
	var spec: GASEffectSpec = sg.player.asc.make_effect_spec(load("res://addons/gameplay_abilities_system/test_topdown/game/items/ge_attack_damage.tres"))
	spec.set_setbycaller_magnitude(&"coeff", 500.0)
	sg.player.asc.apply_gameplay_effect_spec_to_target(spec, victim.asc)
	_check(not victim.is_alive(), "表现层-01 场景怪物被击杀")
	await _timer(1.0)
	_check(not scene.get("_entity_sprites").has(victim), "表现层-02 死亡动画完成后 freed 实体清理（无崩溃）")
	var sprites_before: int = scene.get("_entity_sprites").size()
	await _timer(2.6)
	_check(scene.get("_entity_sprites").size() == sprites_before + 1, "表现层-03 重生怪补回 sprite（respawn vfx 到期不崩）")

## ---------------- 基础框架回归（GAS 通用能力） ----------------

func _run_basic_regression() -> void:
	print("=== 基础框架回归 ===")
	var dummy := _make_dummy("木桩", {&"Health": 100.0, &"MaxHealth": 100.0, &"Attack": 20.0,
		&"Defense": 5.0, &"MoveSpeed": 150.0, &"Level": 1.0, &"XP": 0.0})

	var heal_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test_topdown/game/items/ge_heal_potion.tres")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(heal_ge))
	_check(is_equal_approx(dummy.get_attr(&"Health"), 100.0), "基础-01 治疗 +40 被 MaxHealth 钳制（100）")
	dummy.attr_set.apply_base_value_change(&"Health", -50.0)
	_check(is_equal_approx(dummy.get_attr(&"Health"), 50.0), "基础-02 直接扣血到 50")

	var sword_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test_topdown/game/gear/ge_sword.tres")
	var sword_handle := dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(sword_ge))
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 35.0), "基础-03 INFINITE 铁剑 Attack +15（20→35）")
	_check(dummy.asc.remove_active_effect(sword_handle), "基础-04 凭票摘除返回 true")
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 20.0), "基础-05 摘除后回退 Attack 20")
	_check(not dummy.asc.remove_active_effect(sword_handle), "基础-06 旧票无害化：二次摘除 false")

	var ring_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test_topdown/game/gear/ge_ring_attack.tres")
	var ring_handle := dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(ring_ge))
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 24.0), "基础-07 MULTIPLY 力量之戒 Attack ×1.2（20→24）")
	dummy.asc.remove_active_effect(ring_handle)
	_check(is_equal_approx(dummy.get_attr(&"Attack"), 20.0), "基础-08 摘戒指回退 20")

	var xp_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test_topdown/game/items/ge_xp_gain.tres")
	var xp_spec := dummy.asc.make_effect_spec(xp_ge)
	xp_spec.set_setbycaller_magnitude(&"xp", 25.0)
	dummy.asc.apply_gameplay_effect_spec_to_self(xp_spec)
	_check(is_equal_approx(dummy.get_attr(&"XP"), 25.0), "基础-09 SetByCaller 经验 +25")

	var cd_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test_topdown/game/items/ge_attack_cooldown.tres")
	var cd_tag := GameplayTags.request_gameplay_tag(&"Ability.Attack.Cooldown")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(cd_ge))
	_check(dummy.asc.has_tag(cd_tag), "基础-10 冷却 GE 授予 Ability.Attack.Cooldown")
	await _timer(0.7)
	_check(not dummy.asc.has_tag(cd_tag), "基础-11 冷却到期 tag 撤销")

	var attack_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test_topdown/game/items/ge_attack_damage.tres")
	var target := _make_dummy("靶子", {&"Health": 100.0, &"MaxHealth": 100.0, &"Attack": 1.0,
		&"Defense": 8.0, &"MoveSpeed": 0.0, &"Level": 1.0, &"XP": 0.0})
	var dmg_spec: GASEffectSpec = dummy.asc.make_effect_spec(attack_ge)
	dmg_spec.set_setbycaller_magnitude(&"coeff", 1.5)
	dummy.asc.apply_gameplay_effect_spec_to_target(dmg_spec, target.asc)
	_check(is_equal_approx(target.get_attr(&"Health"), 100.0 - 22.0), "基础-12 执行器公式 20×1.5−8=22（100→78）")
	var dmg_spec2: GASEffectSpec = dummy.asc.make_effect_spec(attack_ge)
	dmg_spec2.set_setbycaller_magnitude(&"coeff", 0.01)
	dummy.asc.apply_gameplay_effect_spec_to_target(dmg_spec2, target.asc)
	_check(is_equal_approx(target.get_attr(&"Health"), 100.0 - 23.0), "基础-13 执行器保底伤害 max(1, …)（78→77）")

## ---------------- 玩法回归（Top-Down 地城） ----------------

func _run_gameplay_regression() -> void:
	print("=== 玩法回归 ===")
	var game := _new_game()

	_check(is_equal_approx(game.player.get_attr(&"Attack"), 35.0), "玩法-01 初始 Attack 35（20 + 铁剑 15）")
	_check(is_equal_approx(game.player.get_attr(&"MoveSpeed"), 150.0), "玩法-02 初始 MoveSpeed 150")
	_check(game.monsters.size() == 4, "玩法-03 4 只怪物出生")
	_check(game.chests.size() == 4, "玩法-04 4 个宝箱出生")
	var start_pos := game.player.pos

	game.player.move_input = Vector2.RIGHT
	await _timer(0.4)
	game.player.move_input = Vector2.ZERO
	_check(game.player.pos.x > start_pos.x + 40.0, "玩法-05 WASD 向右移动（0.4s × 150px/s）")
	_check(is_equal_approx(game.player.pos.y, start_pos.y), "玩法-06 纯横向移动 y 不动")

	var wall_before := game.player.pos
	game.player.move_input = Vector2.RIGHT
	await _timer(1.0)
	game.player.move_input = Vector2.ZERO
	_check(game.player.pos.distance_to(wall_before) < 120.0, "玩法-07 撞墙被阻挡（不穿墙）")

	var monster := game.monsters[0]
	game.player.pos = Vector2(176.0, 368.0)
	game.player.facing = Vector2.RIGHT
	monster.pos = game.player.pos + Vector2(60.0, 0.0)
	var monster_hp_before := monster.get_attr(&"Health")
	var player_hp_before := game.player.get_attr(&"Health")
	var ok := game.player.try_attack()
	_check(ok, "玩法-08 攻击能力激活成功")
	var damage := monster_hp_before - monster.get_attr(&"Health")
	_check(is_equal_approx(damage, maxf(1.0, 35.0 * 1.0 - monster.get_attr(&"Defense"))), "玩法-09 近战伤害 = max(1, Attack−Defense)")
	_check(game.player.get_attr(&"Health") == player_hp_before, "玩法-10 攻击不伤自己")

	await _timer(0.1)
	game._process(0.016)
	_check(game.player.get_attr(&"Health") < player_hp_before, "玩法-11 怪物反击玩家（AI 索敌→攻击）")
	_check(monster.get_attr(&"Health") > 0.0, "玩法-12 怪物扛住一击未死")

	var archer := game.monsters[3]
	game.player.pos = Vector2(176.0, 368.0)
	archer.pos = game.player.pos + Vector2(150.0, 0.0)
	archer._attack_timer = 0.0  # 重置 CD：排除玩法-07 移动期间弓手可能已射箭的偶发
	var hp_before_arrow := game.player.get_attr(&"Health")
	await _timer(0.4)
	_check(game.projectiles.size() > 0, "玩法-13 狗头人弓手 AI 索敌发射弹道")
	var proj_after_shot := game.projectiles.size()
	await _timer(1.0)
	_check(game.player.get_attr(&"Health") < hp_before_arrow, "玩法-14 弹道命中玩家造成伤害")
	_check(game.projectiles.size() < proj_after_shot, "玩法-14b 命中后弹道被消耗移除")

	var xp_spec: GASEffectSpec = game.player.asc.make_effect_spec(load("res://addons/gameplay_abilities_system/test_topdown/game/items/ge_xp_gain.tres"))
	xp_spec.set_setbycaller_magnitude(&"xp", 40.0)
	game.player.asc.apply_gameplay_effect_spec_to_self(xp_spec)
	_check(is_equal_approx(game.player.get_attr(&"Level"), 2.0), "玩法-15 40 XP 升到 Lv2（40×1 阈值）")
	_check(is_equal_approx(game.player.get_attr(&"MaxHealth"), 120.0), "玩法-16 升级 MaxHealth +20（100→120）")
	_check(is_equal_approx(game.player.get_attr(&"Attack"), 37.0), "玩法-17 升级 Attack +2（35→37）")
	_check(game.get_current_attack_form().kind == TopdownAttackForm.Kind.MELEE_ARC, "玩法-18 Lv2 仍是近战斩击")

	var xp_spec2: GASEffectSpec = game.player.asc.make_effect_spec(load("res://addons/gameplay_abilities_system/test_topdown/game/items/ge_xp_gain.tres"))
	xp_spec2.set_setbycaller_magnitude(&"xp", 80.0)
	game.player.asc.apply_gameplay_effect_spec_to_self(xp_spec2)
	_check(is_equal_approx(game.player.get_attr(&"Level"), 3.0), "玩法-19 再 80 XP 升到 Lv3")
	_check(game.get_current_attack_form().kind == TopdownAttackForm.Kind.PROJECTILE, "玩法-20 Lv3 形态切换为圣光飞弹")
	var proj_before := game.projectiles.size()
	game.player.try_attack()
	_check(game.projectiles.size() == proj_before + 1, "玩法-21 飞弹形态：一次攻击生成 1 发弹道")

	var speed_ge: GASGameplayEffect = load("res://addons/gameplay_abilities_system/test_topdown/game/gear/ge_ring_speed.tres")
	game.player.equip_gear(speed_ge, TopdownPlayer.SLOT_RING, "疾风之戒")
	_check(is_equal_approx(game.player.get_attr(&"MoveSpeed"), 190.0), "玩法-22 疾风之戒 MoveSpeed +40（150→190）")
	game.player.unequip_gear(TopdownPlayer.SLOT_RING)
	_check(is_equal_approx(game.player.get_attr(&"MoveSpeed"), 150.0), "玩法-23 摘戒指移速回退 150")

	var chest := game.chests[0]
	game.player.pos = chest.pos + Vector2(30.0, 0.0)
	_chest_opened = false
	game.chest_opened.connect(func(_c: TopdownChest, _l: String) -> void: _chest_opened = true)
	game.try_interact()
	_check(chest.opened and _chest_opened, "玩法-24 靠近按 E 开箱成功")

	var monster3 := game.monsters[0]
	_monster_dead = false
	game.monster_died.connect(func(_m: TopdownMonster) -> void: _monster_dead = true)
	var kill_spec: GASEffectSpec = game.player.asc.make_effect_spec(load("res://addons/gameplay_abilities_system/test_topdown/game/items/ge_attack_damage.tres"))
	kill_spec.set_setbycaller_magnitude(&"coeff", 100.0)
	game.player.asc.apply_gameplay_effect_spec_to_target(kill_spec, monster3.asc)
	_check(_monster_dead, "玩法-25 巨量伤害击杀怪物（died 信号）")
	_check(game.monsters.size() == 3, "玩法-26 死亡怪物立即移除")
	# 清场：弓手（kind 3）已被玩法-21 飞弹打到垂死，显式击杀避免等待期间意外死亡干扰重生计数
	for m in game.monsters:
		if m.kind_index == 3 and m.is_alive():
			m.attr_set.apply_base_value_change(&"Health", -1000.0)
	_monster_respawned = false
	game.monster_respawned.connect(func(_m: TopdownMonster) -> void: _monster_respawned = true)
	game.player.attr_set.apply_base_value_change(&"Health", 9999.0)
	await _timer(3.3)
	_check(_monster_respawned and game.monsters.size() == 4, "玩法-27 3 秒后原地重生（4 只恢复）")

	_game_over_flag = false
	game.game_over.connect(func() -> void: _game_over_flag = true)
	var lethal: GASEffectSpec = game.player.asc.make_effect_spec(load("res://addons/gameplay_abilities_system/test_topdown/game/items/ge_attack_damage.tres"))
	lethal.set_setbycaller_magnitude(&"coeff", 500.0)
	var dummy_source := _make_dummy("暗影", {&"Health": 1.0, &"MaxHealth": 1.0, &"Attack": 1.0,
		&"Defense": 0.0, &"MoveSpeed": 0.0, &"Level": 1.0, &"XP": 0.0})
	dummy_source.asc.apply_gameplay_effect_spec_to_target(lethal, game.player.asc)
	_check(_game_over_flag, "玩法-28 玩家死亡触发 game_over")

## ---------------- 天罚选择器回归（账目 4+5：真选择器 + AOE 预览） ----------------

func _run_smite_regression() -> void:
	print("=== 天罚选择器回归 ===")
	var scene := get_parent() as Node
	var sg: TopdownGame = scene.get("game")
	if sg == null or sg.monsters.is_empty():
		_check(false, "天罚-00 场景 game 可用")
		return
	var smite: GAPlayerSmite = sg.player.smite_ability
	var actor := scene.get("_smite_target_actor") as GASAbilityTargetActor2D
	if smite == null or actor == null:
		_check(false, "天罚-00 能力与选择器已装配")
		return
	sg._running = false
	sg._respawn_queue.clear()
	sg.player.attr_set.apply_base_value_change(&"Health", 9999.0)
	var radius_px := TopdownGame.SMITE_RADIUS * 2.0
	var victims: Array[TopdownMonster] = []
	for m in sg.monsters:
		if m.is_alive() and scene.get("_entity_sprites").has(m) and victims.size() < 2:
			victims.append(m)
	if victims.size() < 2:
		_check(false, "天罚-00 找到两只带物理身份证的活怪")
		return
	var victim_a: TopdownMonster = victims[0]
	var victim_c: TopdownMonster = victims[1]
	var attack := sg.player.get_attr(&"Attack")

	victim_a.pos = Vector2(64.0, 64.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var a_hp0 := victim_a.get_attr(&"Health")
	_check(sg.player.try_smite(actor), "天罚-01 右键激活落雷能力")
	_check(smite.is_active and smite.wait_task != null and smite.wait_task.is_running, "天罚-02 瞄准态：Task 运行中")
	_check(actor.select_area(victim_a.pos * 2.0, radius_px), "天罚-03 瞄准圈住目标")
	_check(smite.wait_task.confirm_selection(), "天罚-04 左键确认（进入前摇）")
	_check(smite.notify_task != null and smite.notify_task.is_running, "天罚-05 前摇：WaitAnimNotify 等待命中帧")
	_check(smite.is_active, "天罚-06 前摇中能力未结束")
	_check(is_equal_approx(victim_a.get_attr(&"Health"), a_hp0), "天罚-07 前摇中未结算伤害")
	var a_expected := maxf(1.0, attack * 1.8 - victim_a.get_attr(&"Defense"))
	sg.emit_signal(&"anim_notify", &"smite_strike")
	_check(not smite.is_active, "天罚-08 命中帧通知 → 能力结束")
	_check(is_equal_approx(victim_a.get_attr(&"Health"), a_hp0 - a_expected), "天罚-09 公式伤害 max(1, 攻×1.8−防)")

	_check(sg.player.try_smite(actor), "天罚-10 再次激活")
	_check(actor.select_area(victim_a.pos * 2.0, radius_px), "天罚-11 圈住目标")
	_check(smite.wait_task.confirm_selection(), "天罚-12 确认（进入前摇）")
	var hp_before_mismatch := victim_a.get_attr(&"Health")
	sg.emit_signal(&"anim_notify", &"wrong_notify")
	_check(smite.is_active and smite.notify_task != null and smite.notify_task.is_running, "天罚-13 通知名不匹配：前摇继续")
	_check(is_equal_approx(victim_a.get_attr(&"Health"), hp_before_mismatch), "天罚-14 不匹配通知不结算")
	sg.player.asc.cancel_ability(smite)
	_check(not smite.is_active, "天罚-15 取消前摇（不匹配段收尾）")

	_check(sg.player.try_smite(actor), "天罚-16 再次激活")
	_check(not actor.select_area(Vector2(1600.0, 700.0), radius_px), "天罚-17 瞄准远处空地返回 false（选择器清空）")
	_check(not smite.wait_task.confirm_selection(), "天罚-18 空圈确认被拒（fail-closed）")
	_check(smite.is_active and smite.wait_task.is_running, "天罚-19 拒绝后能力继续等待")
	smite.wait_task.cancel_selection()
	_check(not smite.is_active, "天罚-20 右键取消后能力结束")
	_check(is_equal_approx(victim_a.get_attr(&"Health"), hp_before_mismatch), "天罚-21 取消不造成伤害")

	var hp_before_interrupt := victim_a.get_attr(&"Health")
	_check(sg.player.try_smite(actor), "天罚-22 激活")
	_check(actor.select_area(victim_a.pos * 2.0, radius_px), "天罚-23 圈住目标")
	_check(smite.wait_task.confirm_selection(), "天罚-24 确认（进入前摇）")
	_check(smite.is_active and smite.notify_task.is_running, "天罚-25 前摇中")
	sg.player.asc.cancel_ability(smite)
	_check(not smite.is_active, "天罚-26 前摇被打断 → 能力结束")
	_check(is_equal_approx(victim_a.get_attr(&"Health"), hp_before_interrupt), "天罚-27 打断不结算伤害")
	sg.emit_signal(&"anim_notify", &"smite_strike")
	_check(is_equal_approx(victim_a.get_attr(&"Health"), hp_before_interrupt), "天罚-28 打断后通知无人听（连接已断）")

	victim_a.attr_set.apply_base_value_change(&"Health", 9999.0)
	victim_c.attr_set.apply_base_value_change(&"Health", 9999.0)
	victim_a.pos = Vector2(96.0, 96.0)
	victim_c.pos = Vector2(128.0, 96.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var a2_hp0 := victim_a.get_attr(&"Health")
	var c_hp0 := victim_c.get_attr(&"Health")
	var mid := (victim_a.pos + victim_c.pos) * 0.5 * 2.0
	_check(sg.player.try_smite(actor), "天罚-29 多目标激活")
	_check(actor.select_area(mid, radius_px), "天罚-30 中间圈住两只")
	_check(smite.wait_task.confirm_selection(), "天罚-31 确认（进入前摇）")
	var a_expected2 := maxf(1.0, attack * 1.8 - victim_a.get_attr(&"Defense"))
	var c_expected := maxf(1.0, attack * 1.8 - victim_c.get_attr(&"Defense"))
	sg.emit_signal(&"anim_notify", &"smite_strike")
	_check(not smite.is_active, "天罚-32 命中帧通知 → 结算")
	_check(is_equal_approx(victim_a.get_attr(&"Health"), a2_hp0 - a_expected2), "天罚-33 目标A 满血复战后受公式伤害")
	_check(is_equal_approx(victim_c.get_attr(&"Health"), c_hp0 - c_expected), "天罚-34 目标C 受公式伤害")
	sg._running = true

## ---------------- 连击回归（WaitInput：攻击后 0.6s 窗口内再按攻击键 → 强化斩击） ----------------

func _run_combo_regression() -> void:
	print("=== 连击回归 ===")
	var g := _new_game()
	var orc: TopdownMonster = g.monsters[2]
	orc.pos = g.player.pos + Vector2(60.0, 0.0)
	g.player.attr_set.apply_base_value_change(&"Health", 9999.0)
	var attack := g.player.get_attr(&"Attack")
	var combo: GAPlayerCombo = g.player.combo_ability
	if combo == null:
		_check(false, "连击-00 连击能力已装配")
		return
	Input.action_release("attack")

	var orc_hp0 := orc.get_attr(&"Health")
	var defense := orc.get_attr(&"Defense")
	_check(g.player.try_attack(), "连击-01 普通攻击")
	_check(combo.is_active and combo.wait_task != null and combo.wait_task.is_running, "连击-02 攻击后连击窗口开启")
	_check(is_equal_approx(orc.get_attr(&"Health"), orc_hp0 - (attack - defense)), "连击-03 普攻伤害 max(1, 攻−防)")

	var hp_after_hit := orc.get_attr(&"Health")
	Input.action_press("attack")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("attack")
	_check(not combo.is_active, "连击-04 窗口内按攻击键 → 连击触发")
	_check(is_equal_approx(orc.get_attr(&"Health"), hp_after_hit - (attack * 1.5 - defense)), "连击-05 强化斩击伤害 max(1, 攻×1.5−防)")
	await _timer(0.6)
	orc.attr_set.apply_base_value_change(&"Health", 9999.0)
	var hp_before_timeout := orc.get_attr(&"Health")
	_check(g.player.try_attack(), "连击-06 冷却过后再次攻击开窗")
	_check(combo.is_active, "连击-07 窗口开启")
	await _timer(0.7)
	_check(not combo.is_active, "连击-08 0.6s 超时窗口关闭")
	_check(is_equal_approx(orc.get_attr(&"Health"), hp_before_timeout - (attack - defense)), "连击-09 超时不触发强化斩击")

	_check(g.player.try_attack(), "连击-10 攻击开窗")
	_check(combo.is_active, "连击-11 窗口开启")
	g.player.asc.cancel_ability(combo)
	_check(not combo.is_active, "连击-12 能力打断 → 窗口关闭（Task 取消善后）")

	g.queue_free()
	await _timer(0.1)

## ---------------- 狂暴回归（互斥矩阵：block/cancel abilities with tags） ----------------

func _run_berserk_regression() -> void:
	print("=== 狂暴互斥回归 ===")
	var scene := get_parent() as Node
	var sg: TopdownGame = scene.get("game")
	if sg == null or sg.monsters.is_empty():
		_check(false, "狂暴-00 场景 game 可用")
		return
	var smite: GAPlayerSmite = sg.player.smite_ability
	var actor := scene.get("_smite_target_actor") as GASAbilityTargetActor2D
	if smite == null or actor == null:
		_check(false, "狂暴-00 能力与选择器已装配")
		return
	sg._running = false
	sg._respawn_queue.clear()
	sg.player.attr_set.apply_base_value_change(&"Health", 9999.0)
	var victims: Array[TopdownMonster] = []
	for m in sg.monsters:
		if m.is_alive() and scene.get("_entity_sprites").has(m) and victims.size() < 1:
			victims.append(m)
	if victims.is_empty():
		_check(false, "狂暴-00 找到带物理身份证的活怪")
		return
	var victim: TopdownMonster = victims[0]
	victim.pos = Vector2(64.0, 64.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var radius_px := TopdownGame.SMITE_RADIUS * 2.0
	var attack := sg.player.get_attr(&"Attack")
	var berserk_tag := GameplayTags.request_gameplay_tag(&"Ability.Berserk")

	_check(sg.player.try_berserk(), "狂暴-01 激活狂暴")
	_check(is_equal_approx(sg.player.get_attr(&"Attack"), attack * 2.0), "狂暴-02 狂暴中攻击力 ×2（MULTIPLY 1.0）")
	_check(sg.player.asc.has_tag(berserk_tag), "狂暴-03 狂暴 GE 授予 Ability.Berserk tag")
	_check(not sg.player.try_smite(actor), "狂暴-04 狂暴中落雷被拒（block_abilities_with_tags）")
	var hp_berserk := victim.get_attr(&"Health")
	_check(sg.player.try_attack(), "狂暴-05 狂暴中普攻正常（互斥不误伤）")
	_check(not sg.player.try_smite(actor), "狂暴-06 狂暴中落雷仍被拒")

	var berserk_query := FGameplayTagContainer.new()
	berserk_query.add_tag(berserk_tag)
	sg.player.asc.remove_active_effects_with_tags(berserk_query)
	_check(is_equal_approx(sg.player.get_attr(&"Attack"), attack), "狂暴-07 移除狂暴后攻击力回落")

	var victim_hp0 := victim.get_attr(&"Health")
	_check(sg.player.try_smite(actor), "狂暴-08 落雷恢复可激活")
	_check(actor.select_area(victim.pos * 2.0, radius_px), "狂暴-09 圈住目标")
	_check(smite.wait_task.confirm_selection(), "狂暴-10 确认（进入前摇）")
	_check(smite.is_active and smite.notify_task.is_running, "狂暴-11 落雷前摇中")
	_check(sg.player.try_berserk(), "狂暴-12 前摇中狂暴激活")
	_check(not smite.is_active, "狂暴-13 落雷被打断（cancel_abilities_with_tags）")
	_check(is_equal_approx(victim.get_attr(&"Health"), victim_hp0), "狂暴-14 打断无伤害")

	await _timer(TopdownGame.BERSERK_DURATION + 0.2)
	_check(is_equal_approx(sg.player.get_attr(&"Attack"), attack), "狂暴-15 狂暴 3s 到期攻击力回落")
	_check(not sg.player.asc.has_tag(berserk_tag), "狂暴-16 到期 tag 撤销")
	_check(sg.player.try_smite(actor), "狂暴-17 到期后落雷恢复可激活")
	_check(sg.player.try_berserk(), "狂暴-18 狂暴再次可用")
	_check(not sg.player.try_smite(actor), "狂暴-19 狂暴中落雷再次被拒")
	var berserk_query2 := FGameplayTagContainer.new()
	berserk_query2.add_tag(berserk_tag)
	sg.player.asc.remove_active_effects_with_tags(berserk_query2)
	sg._running = true
