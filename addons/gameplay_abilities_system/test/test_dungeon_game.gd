class_name DungeonGameTest
extends Node

var _pass_count := 0
var _fail_count := 0

var _cue_active_count := 0
var _cue_executed_count := 0
var _cue_removed_count := 0
var _cue_last_target: Node = null
var _cue_last_magnitude := 0.0

var _cue_factory_spawns := 0
var _cue_factory_node: Node = null

var _ta_signal_count := 0

func _on_ta_selection_changed(_old_data: GASAbilityTargetData, _new_data: GASAbilityTargetData) -> void:
	_ta_signal_count += 1

var _wt_finished := false
var _wt_canceled := false

func _on_wt_task_finished() -> void:
	_wt_finished = true

func _on_wt_task_canceled() -> void:
	_wt_canceled = true

func _on_cue_factory(_params: GASGameplayCueParameters) -> Node:
	_cue_factory_spawns += 1
	_cue_factory_node = Node.new()
	_cue_factory_node.name = "StunCueNode"
	return _cue_factory_node

func is_pass() -> bool:
	return _fail_count == 0

func get_pass_count() -> int:
	return _pass_count

func get_fail_count() -> int:
	return _fail_count

func _on_cue(tag: FGameplayTag, event: GASEnums.GameplayCueEvent, params: GASGameplayCueParameters) -> void:
	match event:
		GASEnums.GameplayCueEvent.ON_ACTIVE:
			_cue_active_count += 1
			_cue_last_target = params.target
			_cue_last_magnitude = params.magnitude
		GASEnums.GameplayCueEvent.EXECUTED:
			_cue_executed_count += 1
		GASEnums.GameplayCueEvent.ON_REMOVED:
			_cue_removed_count += 1

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
	var stun_cue_tag: FGameplayTag = GameplayTags.request_gameplay_tag(&"GameplayCue.Status.Stun")
	_cue_active_count = 0
	_cue_removed_count = 0
	_cue_last_target = null
	_cue_last_magnitude = 0.0
	GameplayCueManager.register(stun_cue_tag, _on_cue)
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(stun_ge))
	_check(dummy.is_stunned(), "基础-24 纯标签 GE 授予 Stun")
	_check(_cue_active_count == 1, "基础-24b 施加眩晕 → GameplayCue OnActive ×1")
	_check(_cue_last_target != null, "基础-24c 小票携带 target（被打者）")
	_check(_cue_last_magnitude == 0.0, "基础-24d 纯标签 GE 无 modifier，magnitude 为 0")
	var dispel_query := FGameplayTagContainer.new()
	dispel_query.add_tag(GameplayTags.request_gameplay_tag(&"State.Debuff"))
	var removed := dummy.asc.remove_active_effects_with_tags(dispel_query)
	_check(removed >= 1, "基础-25 按 State.Debuff 驱散移除 %d 个效果" % removed)
	_check(not dummy.is_stunned(), "基础-26 驱散后 Stun 撤销")
	_check(_cue_removed_count == 1, "基础-26b 驱散 → GameplayCue OnRemoved ×1")
	dummy.asc.apply_gameplay_effect_spec_to_self(dummy.asc.make_effect_spec(stun_ge))
	await _timer(2.5)
	_check(_cue_removed_count == 2, "基础-26c 自然到期 → GameplayCue OnRemoved ×2")
	GameplayCueManager.unregister(stun_cue_tag, _on_cue)

	var ticket_tag: FGameplayTag = GameplayTags.request_gameplay_tag(&"GameplayCue.Test.Ticket")
	_cue_factory_spawns = 0
	_cue_factory_node = null
	GameplayCueManager.register_factory(ticket_tag, _on_cue_factory)
	var cue_target_a := Node.new()
	cue_target_a.name = "CueTargetA"
	add_child(cue_target_a)
	var cue_handle_a1 := GameplayCueManager.add_cue(ticket_tag, cue_target_a, GASGameplayCueParameters.new())
	_check(_cue_factory_spawns == 1, "基础-27 首张票 0→1 触发工厂")
	_check(_cue_factory_node != null and _cue_factory_node.get_parent() == cue_target_a, "基础-28 表现节点挂到目标身上")
	var cue_handle_a2 := GameplayCueManager.add_cue(ticket_tag, cue_target_a, GASGameplayCueParameters.new())
	_check(_cue_factory_spawns == 1, "基础-29 同目标第二张票复用表现（不再调工厂）")
	_check(cue_handle_a1 != cue_handle_a2, "基础-30 两张票 handle 不同")
	_check(GameplayCueManager.remove_cue(cue_handle_a1), "基础-31 凭票退一（count 2→1）")
	_check(is_instance_valid(_cue_factory_node), "基础-32 还剩一张票，表现节点存活")
	_check(GameplayCueManager.remove_cue(cue_handle_a2), "基础-33 凭票退一（count 1→0）")
	await _timer(0.1)
	_check(not is_instance_valid(_cue_factory_node), "基础-34 票根清零 → 表现节点销毁")
	_check(not GameplayCueManager.remove_cue(cue_handle_a1), "基础-35 旧票无害化：二次退票 false")
	var cue_target_b := Node.new()
	cue_target_b.name = "CueTargetB"
	add_child(cue_target_b)
	var cue_handle_b := GameplayCueManager.add_cue(ticket_tag, cue_target_b, GASGameplayCueParameters.new())
	_check(_cue_factory_spawns == 2, "基础-36 不同目标各自 0→1（新建独立表现）")
	GameplayCueManager.remove_cue(cue_handle_b)
	GameplayCueManager.unregister_factory(ticket_tag)
	GameplayCueManager.register_factory(ticket_tag, func(_params: GASGameplayCueParameters) -> Node: return null)
	var empty_handle := GameplayCueManager.add_cue(ticket_tag, cue_target_b, GASGameplayCueParameters.new())
	_check(empty_handle > 0, "基础-37 工厂返回空表现也合法（凭票照发）")
	_check(GameplayCueManager.remove_cue(empty_handle), "基础-38 空表现退票正常")
	GameplayCueManager.unregister_factory(ticket_tag)
	cue_target_a.queue_free()
	cue_target_b.queue_free()
	dummy.queue_free()
	await _timer(0.1)

	var dot2 := _make_dummy("木桩2", {&"Body": 50.0, &"MaxBody": 100.0, &"Mind": 50.0, &"MaxMind": 50.0,
		&"Attack": 20.0, &"Defense": 5.0, &"Move": 2.0, &"Level": 3.0, &"CooldownReduction": 0.0})

	# 周期 GE 三事件：ON_ACTIVE ×1 → EXECUTED ×N（每跳）→ ON_REMOVED ×1
	var dot_cue_ge := GASGameplayEffect.new()
	dot_cue_ge.duration_policy = GASEnums.DurationPolicy.DURATION
	dot_cue_ge.duration = 2.5
	dot_cue_ge.period = 1.0
	dot_cue_ge.gameplay_cue_tags.add_tag(stun_cue_tag)
	_cue_active_count = 0
	_cue_executed_count = 0
	_cue_removed_count = 0
	GameplayCueManager.register(stun_cue_tag, _on_cue)
	dot2.asc.apply_gameplay_effect_spec_to_self(dot2.asc.make_effect_spec(dot_cue_ge))
	_check(_cue_active_count == 1, "基础-39 周期 GE 挂账 → OnActive ×1")
	await _timer(2.2)
	_check(_cue_executed_count == 2, "基础-40 周期 GE 两跳 → Executed ×2（每跳一次）")
	await _timer(1.5)
	_check(_cue_removed_count == 1, "基础-41 周期 GE 到期 → OnRemoved ×1")
	_check(_cue_executed_count == 2, "基础-42 到期后不再跳（Executed 仍为 2）")

	# ASC 手动触发 API（文档 9.3）：execute 广播 / add+remove 凭票
	_cue_executed_count = 0
	GameplayCueManager.register(ticket_tag, _on_cue)
	var exec_params := GASGameplayCueParameters.new()
	exec_params.target = dot2
	dot2.asc.execute_gameplay_cue(ticket_tag, exec_params)
	_check(_cue_executed_count == 1, "基础-43 手动 ExecuteGameplayCue → Executed ×1")
	_cue_factory_spawns = 0
	_cue_factory_node = null
	GameplayCueManager.register_factory(ticket_tag, _on_cue_factory)
	var add_params := GASGameplayCueParameters.new()
	add_params.target = dot2
	var cue_handle_c := dot2.asc.add_gameplay_cue(ticket_tag, add_params)
	_check(_cue_factory_spawns == 1, "基础-44 ASC add_gameplay_cue → 工厂 0→1")
	_check(cue_handle_c > 0, "基础-45 add_gameplay_cue 返回有效 handle")
	_check(_cue_factory_node != null and _cue_factory_node.get_parent() == dot2, "基础-46 表现节点挂到小票 target")
	_check(dot2.asc.remove_gameplay_cue(cue_handle_c), "基础-47 ASC remove_gameplay_cue 凭票退")
	await _timer(0.1)
	_check(not is_instance_valid(_cue_factory_node), "基础-48 退票清零 → 节点销毁")
	_check(not dot2.asc.remove_gameplay_cue(cue_handle_c), "基础-49 无效票 → false")
	GameplayCueManager.unregister_factory(ticket_tag)
	GameplayCueManager.unregister(ticket_tag, _on_cue)
	GameplayCueManager.unregister(stun_cue_tag, _on_cue)
	dot2.queue_free()
	await _timer(0.1)

	var td_a := Node.new()
	var td_b := Node.new()
	var td_c := Node.new()

	var td_single := GASAbilityTargetData.from_actor(td_a)
	_check(td_single.get_actor() == td_a, "基础-50 from_actor 单目标返回同一实例")
	_check(td_single.get_actors().size() == 1, "基础-51 from_actor 容器大小为 1")
	_check(not td_single.has_location, "基础-52 纯 actor 目标无位置")

	var td_src: Array[Node] = [td_a, td_b]
	var td_multi := GASAbilityTargetData.from_actors(td_src)
	_check(td_multi.get_actors().size() == 2, "基础-53 from_actors 多目标大小为 2")
	_check(td_multi.get_actors()[0] == td_a and td_multi.get_actors()[1] == td_b, "基础-54 多目标元素为同一实例")
	td_src.append(td_c)
	_check(td_multi.get_actors().size() == 2, "基础-55 快照隔离：原数组 append 不影响 target_data")

	var td_empty := GASAbilityTargetData.new()
	_check(td_empty.get_actor() == null, "基础-56 空容器 get_actor 返回 null（fail-open 契约）")
	_check(td_empty.get_actors().is_empty(), "基础-57 空容器 get_actors 为空")
	_check(td_empty.get_location() == Vector3.ZERO, "基础-58 空容器 get_location 兜底 ZERO")
	_check(not td_empty.has_location, "基础-59 空容器无位置")

	var td_pos := Vector3(5.0, -2.0, 7.0)
	var td_loc := GASAbilityTargetData.from_location(td_pos)
	_check(td_loc.get_location() == td_pos, "基础-60 from_location 位置快照一致")
	_check(td_loc.has_location, "基础-61 from_location has_location 为 true")
	_check(td_loc.get_actor() == null, "基础-62 纯位置目标无 actor")

	td_a.free()
	td_b.free()
	td_c.free()

	var ta := GASAbilityTargetActor2D.new()
	ta.name = "TestTargetActor2D"
	add_child(ta)
	await get_tree().physics_frame

	var ta_body := StaticBody2D.new()
	ta_body.name = "BodyA"
	ta_body.position = Vector2(100.0, 100.0)
	var ta_shape := CollisionShape2D.new()
	var ta_circle := CircleShape2D.new()
	ta_circle.radius = 10.0
	ta_shape.shape = ta_circle
	ta_body.add_child(ta_shape)
	add_child(ta_body)
	var ta_entity := Node2D.new()
	ta_entity.name = "实体A"
	ta_entity.position = ta_body.position
	add_child(ta_entity)
	ta_body.set_meta(GASAbilityTargetActor.ENTITY_META, ta_entity)
	await get_tree().physics_frame

	ta.selection_changed.connect(_on_ta_selection_changed)

	_check(ta.select_at(Vector2(100.0, 100.0)), "基础-63 点选命中实体A")
	var ta_confirm := ta.confirm_target()
	_check(ta_confirm != null and ta_confirm.get_actor() == ta_entity, "基础-64 confirm 返回实体A")
	_check(ta_confirm.has_location and ta_confirm.location == Vector3(100.0, 100.0, 0.0), "基础-65 命中数据带实体位置")
	_check(_ta_signal_count == 1, "基础-66 首次选择信号 ×1")
	_check(ta.select_at(Vector2(100.0, 100.0)), "基础-67 重复点选同一实体")
	_check(_ta_signal_count == 1, "基础-68 跳变沿：选中未变不再发信号")
	_check(not ta.select_at(Vector2(400.0, 400.0)), "基础-69 点选空地返回 false")
	_check(ta.confirm_target() == null, "基础-70 空选择 confirm 为 null")
	_check(_ta_signal_count == 2, "基础-71 有→无 跳变信号 ×1")
	var ta_confirm2 := ta.confirm_target()
	_check(ta_confirm2 == null, "基础-72 空选择下 confirm 仍为 null")
	_check(ta.select_at(Vector2(100.0, 100.0)), "基础-73 重新点选实体A")
	var ta_copy := ta.confirm_target()
	ta_copy.actors.append(Node.new())
	_check(ta.confirm_target().get_actors().size() == 1, "基础-74 买定离手：改拷贝不影响缓存")
	ta.cancel_target()
	_check(ta.confirm_target() == null, "基础-75 cancel 后 confirm 为 null")
	_check(_ta_signal_count == 4, "基础-76 重新点选+取消 各发一次信号")

	ta.filter = func(node: Node) -> bool:
		return node.name == "实体A"
	_check(ta.select_at(Vector2(100.0, 100.0)), "基础-77 过滤器放行实体A")
	_check(not ta.select_at(Vector2(150.0, 100.0)), "基础-78 点选空地返回 false")
	var ta_body_b := StaticBody2D.new()
	ta_body_b.name = "BodyB"
	ta_body_b.position = Vector2(300.0, 100.0)
	var ta_shape_b := CollisionShape2D.new()
	var ta_circle_b := CircleShape2D.new()
	ta_circle_b.radius = 10.0
	ta_shape_b.shape = ta_circle_b
	ta_body_b.add_child(ta_shape_b)
	add_child(ta_body_b)
	var ta_entity_b := Node2D.new()
	ta_entity_b.name = "实体B"
	ta_entity_b.position = ta_body_b.position
	add_child(ta_entity_b)
	ta_body_b.set_meta(GASAbilityTargetActor.ENTITY_META, ta_entity_b)
	await get_tree().physics_frame
	_check(not ta.select_at(Vector2(300.0, 100.0)), "基础-79 过滤器拒收实体B")
	_check(ta.confirm_target() == null, "基础-80 拒收后为空选择")
	ta.filter = Callable()

	var ta_body_c := StaticBody2D.new()
	ta_body_c.name = "BodyC"
	ta_body_c.position = Vector2(500.0, 100.0)
	var ta_shape_c := CollisionShape2D.new()
	var ta_circle_c := CircleShape2D.new()
	ta_circle_c.radius = 10.0
	ta_shape_c.shape = ta_circle_c
	ta_body_c.add_child(ta_shape_c)
	add_child(ta_body_c)
	var ta_entity_c := Node2D.new()
	ta_entity_c.name = "实体C"
	ta_entity_c.position = ta_body_c.position
	add_child(ta_entity_c)
	ta_body_c.set_meta(GASAbilityTargetActor.ENTITY_META, ta_entity_c)
	var ta_body_d := StaticBody2D.new()
	ta_body_d.name = "BodyD"
	ta_body_d.position = Vector2(520.0, 100.0)
	var ta_shape_d := CollisionShape2D.new()
	var ta_circle_d := CircleShape2D.new()
	ta_circle_d.radius = 10.0
	ta_shape_d.shape = ta_circle_d
	ta_body_d.add_child(ta_shape_d)
	add_child(ta_body_d)
	var ta_entity_d := Node2D.new()
	ta_entity_d.name = "实体D"
	ta_entity_d.position = ta_body_d.position
	add_child(ta_entity_d)
	ta_body_d.set_meta(GASAbilityTargetActor.ENTITY_META, ta_entity_d)
	await get_tree().physics_frame

	_check(ta.select_area(Vector2(510.0, 100.0), 30.0), "基础-81 范围选择命中两个实体")
	var ta_area_confirm := ta.confirm_target()
	_check(ta_area_confirm != null and ta_area_confirm.get_actors().size() == 2, "基础-82 范围结果包含 2 个目标")
	_check(ta_area_confirm.get_actors().has(ta_entity_c) and ta_area_confirm.get_actors().has(ta_entity_d), "基础-83 范围目标 C 和 D 均在")
	_check(not ta.select_area(Vector2(900.0, 900.0), 30.0), "基础-84 范围在空地处返回 false")
	_check(ta.confirm_target() == null, "基础-85 范围空选择 confirm 为 null")
	ta.filter = func(node: Node) -> bool:
		return node.name == "实体C"
	_check(ta.select_area(Vector2(510.0, 100.0), 30.0), "基础-86 范围选择带过滤器仍命中")
	_check(ta.confirm_target().get_actors().size() == 1 and ta.confirm_target().get_actors()[0] == ta_entity_c, "基础-87 过滤器在范围内拒收 D 只留 C")
	ta.filter = Callable()
	_check(ta.select_at(Vector2(100.0, 100.0)), "基础-88 点选→范围 切换回点选")
	_check(_ta_signal_count == 10, "基础-89 选择切换均有跳变信号")
	ta_area_confirm.actors.append(Node.new())
	_check(ta.confirm_target().get_actors().size() == 1, "基础-90 范围 confirm 拷贝隔离")

	ta.queue_free()
	ta_body.queue_free()
	ta_body_b.queue_free()
	ta_body_c.queue_free()
	ta_body_d.queue_free()
	ta_entity.queue_free()
	ta_entity_b.queue_free()
	ta_entity_c.queue_free()
	ta_entity_d.queue_free()
	await _timer(0.1)

	var wt_actor := GASAbilityTargetActor2D.new()
	wt_actor.name = "WaitTargetActor"
	add_child(wt_actor)
	var wt_body := StaticBody2D.new()
	wt_body.name = "BodyWait"
	wt_body.position = Vector2(700.0, 100.0)
	var wt_shape := CollisionShape2D.new()
	var wt_circle := CircleShape2D.new()
	wt_circle.radius = 10.0
	wt_shape.shape = wt_circle
	wt_body.add_child(wt_shape)
	add_child(wt_body)
	var wt_entity := Node2D.new()
	wt_entity.name = "等待目标实体"
	wt_entity.position = wt_body.position
	add_child(wt_entity)
	wt_body.set_meta(GASAbilityTargetActor.ENTITY_META, wt_entity)
	await get_tree().physics_frame

	var wt_host := GASGameplayAbility.new()
	var wt_host_dummy := _make_dummy("等待宿主", {&"Body": 100.0, &"MaxBody": 100.0, &"Mind": 50.0, &"MaxMind": 50.0,
		&"Attack": 20.0, &"Defense": 5.0, &"Move": 2.0, &"Level": 1.0, &"CooldownReduction": 0.0})
	wt_host_dummy.asc.give_ability(wt_host)
	wt_host.is_active = true
	_wt_finished = false
	_wt_canceled = false
	var wt_task := GASAbilityTaskWaitTargetData.create(wt_host, wt_actor)
	wt_task.task_finished.connect(_on_wt_task_finished)
	wt_task.task_canceled.connect(_on_wt_task_canceled)
	_check(wt_task.is_running, "基础-91 Task 激活后处于运行态")
	_check(not wt_task.confirm_selection(), "基础-92 无选择时确认被拒绝")
	_check(wt_task.is_running, "基础-93 拒绝确认后任务继续等待")
	_check(wt_actor.select_at(Vector2(700.0, 100.0)), "基础-94 选择器命中目标")
	_check(wt_task.confirm_selection(), "基础-95 确认成功返回 true")
	_check(_wt_finished, "基础-96 task_finished 已触发")
	_check(not wt_task.is_running, "基础-97 确认后任务结束")
	var wt_data := wt_task.get_target_data()
	_check(wt_data != null and wt_data.get_actor() == wt_entity, "基础-98 能力拿到正确 TargetData")

	var wt_task2 := GASAbilityTaskWaitTargetData.create(wt_host, wt_actor)
	wt_task2.task_finished.connect(_on_wt_task_finished)
	wt_task2.task_canceled.connect(_on_wt_task_canceled)
	wt_actor.select_at(Vector2(700.0, 100.0))
	wt_task2.cancel_selection()
	_check(_wt_canceled, "基础-99 cancel_selection → task_canceled")
	_check(not wt_task2.is_running, "基础-100 取消后任务结束")
	_check(wt_actor.confirm_target() == null, "基础-101 取消后选择器状态被清空")

	var wt_ga := GAWaitTargetTest.new()
	wt_ga.target_actor = wt_actor
	_check(wt_host_dummy.asc.give_ability(wt_ga), "基础-102 注入测试能力")
	_check(wt_host_dummy.asc.try_activate_ability(wt_ga), "基础-103 GA 激活并挂起等待")
	_check(wt_ga.wait_task != null and wt_ga.wait_task.is_running, "基础-104 能力内任务已创建并等待")
	wt_actor.select_at(Vector2(700.0, 100.0))
	_check(wt_ga.wait_task.confirm_selection(), "基础-105 模拟玩家确认目标")
	_check(wt_ga.last_target_data != null and wt_ga.last_target_data.get_actor() == wt_entity, "基础-106 能力收到确认的 TargetData")
	_check(not wt_ga.is_active, "基础-107 确认后能力结束")

	var wt_ga2 := GAWaitTargetTest.new()
	wt_ga2.target_actor = wt_actor
	wt_host_dummy.asc.give_ability(wt_ga2)
	wt_host_dummy.asc.try_activate_ability(wt_ga2)
	wt_host_dummy.asc.cancel_ability(wt_ga2)
	_check(not wt_ga2.is_active, "基础-108 施放中被打断 → 能力结束")
	_check(wt_ga2.task_canceled_flag, "基础-109 能力打断 → 任务 task_canceled")
	_check(wt_actor.confirm_target() == null, "基础-110 打断后选择器状态被清空")
	_check(wt_ga2.wait_task == null or not wt_ga2.wait_task.is_running, "基础-111 任务随能力结束而终止")

	wt_actor.queue_free()
	wt_body.queue_free()
	wt_entity.queue_free()
	wt_host_dummy.queue_free()
	await _timer(0.1)

	var ov_actor := GASAbilityTargetActor2D.new()
	ov_actor.name = "OverlapTargetActor"
	add_child(ov_actor)
	var ov_body_1 := StaticBody2D.new()
	ov_body_1.name = "BodyZ5"
	ov_body_1.position = Vector2(800.0, 100.0)
	var ov_shape_1 := CollisionShape2D.new()
	var ov_circle_1 := CircleShape2D.new()
	ov_circle_1.radius = 10.0
	ov_shape_1.shape = ov_circle_1
	ov_body_1.add_child(ov_shape_1)
	add_child(ov_body_1)
	var ov_entity_1 := Node2D.new()
	ov_entity_1.name = "上层实体"
	ov_entity_1.position = ov_body_1.position
	ov_entity_1.z_index = 5
	add_child(ov_entity_1)
	ov_body_1.z_index = 5
	ov_body_1.set_meta(GASAbilityTargetActor.ENTITY_META, ov_entity_1)
	var ov_body_2 := StaticBody2D.new()
	ov_body_2.name = "BodyZ0"
	ov_body_2.position = Vector2(800.0, 100.0)
	var ov_shape_2 := CollisionShape2D.new()
	var ov_circle_2 := CircleShape2D.new()
	ov_circle_2.radius = 12.0
	ov_shape_2.shape = ov_circle_2
	ov_body_2.add_child(ov_shape_2)
	add_child(ov_body_2)
	var ov_entity_2 := Node2D.new()
	ov_entity_2.name = "下层实体"
	ov_entity_2.position = ov_body_2.position
	ov_entity_2.z_index = 0
	add_child(ov_entity_2)
	ov_body_2.z_index = 0
	ov_body_2.set_meta(GASAbilityTargetActor.ENTITY_META, ov_entity_2)
	await get_tree().physics_frame

	_check(ov_actor.select_at(Vector2(800.0, 100.0)), "基础-112 重叠命中点选返回 true")
	_check(ov_actor.confirm_target().get_actor() == ov_entity_1, "基础-113 重叠命中选 z 更高的实体")
	ov_entity_1.z_index = 0
	ov_body_1.z_index = 0
	ov_entity_2.z_index = 5
	ov_body_2.z_index = 5
	_check(ov_actor.select_at(Vector2(800.0, 100.0)), "基础-114 交换 z 后再次点选")
	_check(ov_actor.confirm_target().get_actor() == ov_entity_2, "基础-115 z 交换后选到新上层")
	ov_entity_1.z_index = 0
	ov_body_1.z_index = 0
	ov_entity_2.z_index = 0
	ov_body_2.z_index = 0
	ov_body_2.position = Vector2(800.0, 110.0)
	ov_entity_2.position = ov_body_2.position
	await get_tree().physics_frame
	_check(ov_actor.select_at(Vector2(800.0, 100.0)), "基础-116 z 平局时点选仍返回 true")
	_check(ov_actor.confirm_target().get_actor() == ov_entity_2, "基础-117 z 平局时选 y 更大的实体（俯视角惯例）")

	ov_actor.queue_free()
	ov_body_1.queue_free()
	ov_body_2.queue_free()
	ov_entity_1.queue_free()
	ov_entity_2.queue_free()
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
