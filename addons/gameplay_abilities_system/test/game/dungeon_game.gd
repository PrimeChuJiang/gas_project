class_name DungeonGame
extends Node

enum Phase { HERO_TURN, MONSTER_TURN, VICTORY, DEFEAT }

signal phase_changed(phase: Phase)
signal hero_moved(hero: DungeonHero, from_index: int, to_index: int)
signal monster_moved(monster: DungeonMonster, from_index: int, to_index: int)
signal damage_applied(source_name: String, target_name: String, amount: float)
signal effect_applied(target_name: String, effect_name: String)
signal message(text: String)
signal game_over(won: bool)

const TAG_STUN := &"State.Debuff.Stun"
const TAG_POISON := &"State.Debuff.Poison"
const TAG_SLOW := &"State.Debuff.Slow"
const TAG_SHIELD := &"State.Buff.Shield"
const TAG_SPELL := &"Ability.Spell"

var board: DungeonBoard
var hero: DungeonHero
var monsters: Array[DungeonMonster] = []

var phase: Phase = Phase.HERO_TURN
var moves_left: int = 0
var action_used: bool = false
var turn_delay: float = 0.35
var rng := RandomNumberGenerator.new()

var gear_catalog: Dictionary = {}
var potions: Dictionary = {}
var _melee_attack_ge: GASGameplayEffect
var _monster_secondary_ges: Dictionary = {}
var _trap_damage_ge: GASGameplayEffect
var _treasure_bounty_ge: GASGameplayEffect
var _spell_damage_ges: Dictionary = {}
var _spell_cost_ges: Dictionary = {}
var _spell_cooldown_ges: Dictionary = {}
var _stun_tag: FGameplayTag
var _hit_cue_tag: FGameplayTag

var _game_started: bool = false

func _ready() -> void:
	_stun_tag = GameplayTags.request_gameplay_tag(TAG_STUN)
	_hit_cue_tag = GameplayTags.request_gameplay_tag(&"GameplayCue.Damage.Hit")

func setup_default_game() -> void:
	var hero_attrs: Dictionary[StringName, float] = {
		&"Body": 100.0, &"MaxBody": 100.0,
		&"Mind": 50.0, &"MaxMind": 50.0,
		&"Attack": 20.0, &"Defense": 5.0,
		&"Move": 2.0, &"Level": 3.0,
		&"CooldownReduction": 0.0,
	}
	var monsters_cfg: Array[Dictionary] = [
		{"name": "哥布林", "pos": 3, "kind": DungeonMonster.MonsterKind.CHARGER, "attrs": {
			&"Body": 45.0, &"MaxBody": 45.0, &"Attack": 15.0, &"Defense": 2.0, &"Move": 1.0,
			&"Mind": 0.0, &"MaxMind": 0.0, &"Level": 1.0, &"CooldownReduction": 0.0}},
		{"name": "骷髅兵", "pos": 4, "kind": DungeonMonster.MonsterKind.STUNNER, "attrs": {
			&"Body": 50.0, &"MaxBody": 50.0, &"Attack": 18.0, &"Defense": 6.0, &"Move": 1.0,
			&"Mind": 0.0, &"MaxMind": 0.0, &"Level": 1.0, &"CooldownReduction": 0.0}},
		{"name": "兽人", "pos": 5, "kind": DungeonMonster.MonsterKind.CHARGER, "attrs": {
			&"Body": 75.0, &"MaxBody": 75.0, &"Attack": 25.0, &"Defense": 5.0, &"Move": 1.0,
			&"Mind": 0.0, &"MaxMind": 0.0, &"Level": 1.0, &"CooldownReduction": 0.0}},
		{"name": "毒蛇", "pos": 7, "kind": DungeonMonster.MonsterKind.VENOM, "attrs": {
			&"Body": 40.0, &"MaxBody": 40.0, &"Attack": 12.0, &"Defense": 1.0, &"Move": 1.0,
			&"Mind": 0.0, &"MaxMind": 0.0, &"Level": 1.0, &"CooldownReduction": 0.0}},
	]
	var tiles: Array[int] = [
		DungeonBoard.TileType.EMPTY, DungeonBoard.TileType.EMPTY, DungeonBoard.TileType.TRAP,
		DungeonBoard.TileType.EMPTY, DungeonBoard.TileType.EMPTY, DungeonBoard.TileType.EMPTY,
		DungeonBoard.TileType.TREASURE, DungeonBoard.TileType.EMPTY, DungeonBoard.TileType.EXIT,
	]
	setup_game(tiles, hero_attrs, ["ge_sword"], monsters_cfg)

func setup_game(p_tiles: Array[int], p_hero_attrs: Dictionary[StringName, float], p_initial_gear: Array[String], p_monsters_cfg: Array[Dictionary]) -> void:
	_clear_entities()
	_load_content()
	board = DungeonBoard.new()
	board.name = "Board"
	add_child(board)
	board.build(p_tiles)
	var hero_abilities := _build_hero_abilities()
	hero = DungeonHero.new()
	hero.name = "Hero"
	add_child(hero)
	hero.setup_hero("勇者", p_hero_attrs, hero_abilities)
	hero.died.connect(_on_hero_died)
	for gear_name in p_initial_gear:
		var entry: Dictionary = gear_catalog[gear_name]
		hero.equip_gear(entry.ge, entry.slot, gear_name)
	for cfg in p_monsters_cfg:
		var monster := DungeonMonster.new()
		monster.name = cfg.name
		add_child(monster)
		monster.setup_monster(cfg.name, cfg.attrs, cfg.kind, _melee_attack_ge, _monster_secondary_ges.get(cfg.kind, null))
		monster.board_index = cfg.pos
		monster.died.connect(_on_monster_died.bind(monster))
		monsters.append(monster)
	monsters.sort_custom(func(a: DungeonMonster, b: DungeonMonster) -> bool: return a.board_index < b.board_index)
	hero.board_index = 0

func start_game() -> void:
	_game_started = true
	_start_hero_turn()

func _start_hero_turn() -> void:
	if not _game_started:
		return
	phase = Phase.HERO_TURN
	moves_left = hero.get_move_attr()
	action_used = false
	phase_changed.emit(phase)
	message.emit("—— 英雄回合（移动 %d 步 + 1 个行动）——" % moves_left)

func _clear_entities() -> void:
	if hero:
		hero.died.disconnect(_on_hero_died)
		hero.queue_free()
	for monster in monsters:
		monster.died.disconnect(_on_monster_died)
		monster.queue_free()
	hero = null
	monsters.clear()

func _load_content() -> void:
	if not gear_catalog.is_empty():
		return
	var base := "res://addons/gameplay_abilities_system/test/game/"
	gear_catalog["ge_sword"] = {"slot": DungeonHero.GEAR_SLOT_WEAPON, "ge": load(base + "gear/ge_sword.tres")}
	gear_catalog["ge_great_sword"] = {"slot": DungeonHero.GEAR_SLOT_WEAPON, "ge": load(base + "gear/ge_great_sword.tres")}
	gear_catalog["ge_wooden_shield"] = {"slot": DungeonHero.GEAR_SLOT_SHIELD, "ge": load(base + "gear/ge_wooden_shield.tres")}
	gear_catalog["ge_iron_shield"] = {"slot": DungeonHero.GEAR_SLOT_SHIELD, "ge": load(base + "gear/ge_iron_shield.tres")}
	gear_catalog["ge_holy_shield"] = {"slot": DungeonHero.GEAR_SLOT_SHIELD, "ge": load(base + "gear/ge_holy_shield.tres")}
	gear_catalog["ge_boots_of_wind"] = {"slot": DungeonHero.GEAR_SLOT_BOOTS, "ge": load(base + "gear/ge_boots_of_wind.tres")}
	gear_catalog["ge_ring_of_wind"] = {"slot": DungeonHero.GEAR_SLOT_RING, "ge": load(base + "gear/ge_ring_of_wind.tres")}
	gear_catalog["ge_giant_belt"] = {"slot": DungeonHero.GEAR_SLOT_BELT, "ge": load(base + "gear/ge_giant_belt.tres")}
	gear_catalog["ge_mana_crystal"] = {"slot": DungeonHero.GEAR_SLOT_CRYSTAL, "ge": load(base + "gear/ge_mana_crystal.tres")}
	potions["healing"] = {"ge": load(base + "items/ge_healing_potion.tres")}
	potions["mana"] = {"ge": load(base + "items/ge_mana_potion.tres")}
	_melee_attack_ge = GASGameplayEffect.new()
	_melee_attack_ge.duration_policy = GASEnums.DurationPolicy.INSTANT
	_melee_attack_ge.executions.append(DungeonDamageExecution.new())
	_monster_secondary_ges[DungeonMonster.MonsterKind.VENOM] = load(base + "monsters/ge_goblin_venom.tres")
	_monster_secondary_ges[DungeonMonster.MonsterKind.STUNNER] = load(base + "monsters/ge_skeleton_stun.tres")
	_trap_damage_ge = load(base + "traps/ge_trap_damage.tres")
	_treasure_bounty_ge = load(base + "traps/ge_treasure_bounty.tres")
	_spell_damage_ges["fireball"] = load(base + "spells/ge_fireball_damage.tres")
	_spell_damage_ges["heal"] = load(base + "spells/ge_heal_effect.tres")
	_spell_damage_ges["poison_cloud"] = load(base + "spells/ge_poison_cloud_dot.tres")
	_spell_damage_ges["frost_nova"] = load(base + "spells/ge_frost_nova.tres")
	_spell_damage_ges["shield"] = load(base + "spells/ge_shield_spell.tres")
	for spell_name in ["melee", "fireball", "heal", "poison_cloud", "frost_nova", "shield"]:
		if spell_name == "melee":
			_spell_cooldown_ges[spell_name] = load(base + "spells/ge_melee_cooldown.tres")
			continue
		_spell_cost_ges[spell_name] = load(base + "spells/ge_%s_cost.tres" % spell_name)
		_spell_cooldown_ges[spell_name] = load(base + "spells/ge_%s_cooldown.tres" % spell_name)

func _build_hero_abilities() -> Array[GASGameplayAbility]:
	var stun_blocked := FGameplayTagContainer.new()
	stun_blocked.add_tag(_stun_tag)
	var abilities: Array[GASGameplayAbility] = []
	var melee := GAMeleeStrike.new()
	melee.attack_ge = _melee_attack_ge
	melee.cooldown_ge = _spell_cooldown_ges["melee"]
	melee.activation_blocked_tags = stun_blocked
	melee.cancel_with_tags = stun_blocked
	var melee_tag := FGameplayTagContainer.new()
	melee_tag.add_tag(GameplayTags.request_gameplay_tag(&"Ability.Melee"))
	melee.ability_tags = melee_tag
	abilities.append(melee)
	var fireball := GAFireballSpell.new()
	fireball.damage_ge = _spell_damage_ges["fireball"]
	_configure_spell(fireball, &"Ability.Spell.Fireball", "fireball", stun_blocked)
	abilities.append(fireball)
	var heal := GAHealSpell.new()
	heal.heal_ge = _spell_damage_ges["heal"]
	_configure_spell(heal, &"Ability.Spell.Heal", "heal", stun_blocked)
	abilities.append(heal)
	var poison := GAPoisonCloud.new()
	poison.dot_ge = _spell_damage_ges["poison_cloud"]
	_configure_spell(poison, &"Ability.Spell.PoisonCloud", "poison_cloud", stun_blocked)
	abilities.append(poison)
	var frost := GAFrostNova.new()
	frost.nova_ge = _spell_damage_ges["frost_nova"]
	_configure_spell(frost, &"Ability.Spell.FrostNova", "frost_nova", stun_blocked)
	abilities.append(frost)
	var shield := GAShieldSpell.new()
	shield.shield_ge = _spell_damage_ges["shield"]
	_configure_spell(shield, &"Ability.Spell.Shield", "shield", stun_blocked)
	abilities.append(shield)
	return abilities

func _configure_spell(spell: GASGameplayAbility, spell_tag: StringName, key: String, stun_blocked: FGameplayTagContainer) -> void:
	spell.cost_ge = _spell_cost_ges[key]
	spell.cooldown_ge = _spell_cooldown_ges[key]
	spell.activation_blocked_tags = stun_blocked
	spell.cancel_with_tags = stun_blocked
	var tags := FGameplayTagContainer.new()
	tags.add_tag(GameplayTags.request_gameplay_tag(spell_tag))
	spell.ability_tags = tags

func get_hero() -> DungeonHero:
	return hero

func get_alive_monsters() -> Array[DungeonMonster]:
	var alive: Array[DungeonMonster] = []
	for monster in monsters:
		if monster.is_alive():
			alive.append(monster)
	return alive

func get_target_in_front() -> DungeonMonster:
	for monster in monsters:
		if monster.is_alive() and monster.board_index > hero.board_index:
			return monster
	for monster in monsters:
		if monster.is_alive():
			return monster
	return null

func get_adjacent_monster() -> DungeonMonster:
	for monster in monsters:
		if monster.is_alive() and absi(monster.board_index - hero.board_index) <= 1:
			return monster
	return null

func hero_move(dir: int) -> bool:
	if phase != Phase.HERO_TURN or moves_left <= 0 or not hero.is_alive():
		return false
	var to := hero.board_index + dir
	if not board.is_in_bounds(to) or _monster_at(to) != null:
		return false
	var from := hero.board_index
	hero.board_index = to
	moves_left -= 1
	hero_moved.emit(hero, from, to)
	message.emit("%s 移动到第 %d 格（剩余 %d 步）" % [hero.display_name, to, moves_left])
	_handle_tile(to)
	return true

func hero_attack(target: DungeonEntity) -> bool:
	if phase != Phase.HERO_TURN or action_used or not hero.is_alive() or not target.is_alive():
		return false
	if absi(target.board_index - hero.board_index) > 1:
		return false
	var success := hero.try_melee_attack(target)
	if success:
		action_used = true
		# 手动 API 演示：无 GE 的逻辑事件也能发 cue（近战命中由 Execution 结算，不走 modifier GE）
		var cue_params := GASGameplayCueParameters.new()
		cue_params.target = target
		cue_params.instigator = hero
		hero.asc.execute_gameplay_cue(_hit_cue_tag, cue_params)
	return success

func hero_cast(spell: GASGameplayAbility, target: DungeonEntity = null) -> bool:
	if phase != Phase.HERO_TURN or action_used or not hero.is_alive():
		return false
	var success := hero.try_cast_spell(spell, target)
	if success:
		action_used = true
	return success

func hero_use_potion(potion_name: String) -> bool:
	if phase != Phase.HERO_TURN or action_used or not hero.is_alive():
		return false
	if not potions.has(potion_name):
		return false
	var success := hero.use_potion(potions[potion_name].ge, potion_name)
	if success:
		action_used = true
	return success

func hero_end_turn() -> void:
	if phase != Phase.HERO_TURN:
		return
	phase = Phase.MONSTER_TURN
	phase_changed.emit(phase)
	message.emit("—— 怪物回合 ——")
	_run_monster_turns()

func _run_monster_turns() -> void:
	for monster in monsters:
		if phase != Phase.MONSTER_TURN:
			return
		if not monster.is_alive():
			continue
		_monster_take_turn(monster)
		if turn_delay > 0.0:
			await get_tree().create_timer(turn_delay).timeout
	_check_game_end()
	if phase == Phase.MONSTER_TURN:
		_start_hero_turn()

func _monster_take_turn(monster: DungeonMonster) -> void:
	var dx := hero.board_index - monster.board_index
	if absi(dx) <= 1 and hero.is_alive():
		_monster_attack(monster)
		return
	if monster.get_move_attr() <= 0:
		message.emit("%s 被减速，动弹不得" % monster.display_name)
		return
	var step := signi(dx) if dx != 0 else 0
	var to := monster.board_index + step
	if step != 0 and board.is_in_bounds(to) and _monster_at(to) == null:
		var from := monster.board_index
		monster.board_index = to
		monster_moved.emit(monster, from, to)
		message.emit("%s 逼近到第 %d 格" % [monster.display_name, to])

func _monster_attack(monster: DungeonMonster) -> void:
	var damage := maxf(1.0, monster.get_attr(&"Attack") - hero.get_attr(&"Defense"))
	var spec: GASEffectSpec = monster.asc.make_effect_spec(monster.attack_ge)
	hero.asc.apply_gameplay_effect_spec_to_self(spec)
	damage_applied.emit(monster.display_name, hero.display_name, damage)
	message.emit("%s 攻击了 %s（-%d）" % [monster.display_name, hero.display_name, int(damage)])
	if monster.secondary_ge:
		hero.asc.apply_gameplay_effect_spec_to_self(monster.asc.make_effect_spec(monster.secondary_ge))
		effect_applied.emit(hero.display_name, monster.secondary_ge.resource_path.get_file())
		message.emit("%s 附加了效果：%s" % [monster.display_name, monster.secondary_ge.comment])

func _handle_tile(index: int) -> void:
	match board.get_tile_type(index):
		DungeonBoard.TileType.TRAP:
			var damage := rng.randf_range(15.0, 30.0)
			var spec: GASEffectSpec = hero.asc.make_effect_spec(_trap_damage_ge)
			spec.set_setbycaller_magnitude(&"damage", -damage)
			hero.asc.apply_gameplay_effect_spec_to_self(spec)
			damage_applied.emit("陷阱", hero.display_name, damage)
			message.emit("踩中陷阱，受到 %d 点伤害！" % int(damage))
		DungeonBoard.TileType.TREASURE:
			_grant_treasure()
		DungeonBoard.TileType.EXIT:
			if hero.is_alive():
				_victory()

func _grant_treasure() -> void:
	var roll := rng.randi_range(0, 2)
	match roll:
		0:
			hero.asc.apply_gameplay_effect_spec_to_self(hero.asc.make_effect_spec(potions["healing"].ge))
			message.emit("宝箱：获得治疗药水（Body +30）")
		1:
			hero.asc.apply_gameplay_effect_spec_to_self(hero.asc.make_effect_spec(potions["mana"].ge))
			message.emit("宝箱：获得法力药水（Mind +30）")
		2:
			hero.asc.apply_gameplay_effect_spec_to_self(hero.asc.make_effect_spec(_treasure_bounty_ge))
			message.emit("宝箱：获得永久祝福（MaxBody +30）")

func _monster_at(index: int) -> DungeonMonster:
	for monster in monsters:
		if monster.is_alive() and monster.board_index == index:
			return monster
	return null

func get_monster_at(index: int) -> DungeonMonster:
	return _monster_at(index)

func _on_hero_died(entity: DungeonEntity) -> void:
	if phase == Phase.DEFEAT:
		return
	phase = Phase.DEFEAT
	phase_changed.emit(phase)
	message.emit("勇者倒下了……")
	game_over.emit(false)

func _on_monster_died(entity: DungeonEntity, monster: DungeonMonster) -> void:
	message.emit("%s 被击败了！" % monster.display_name)
	_check_game_end()

func _check_game_end() -> void:
	if phase == Phase.VICTORY or phase == Phase.DEFEAT:
		return
	if hero.is_alive() and board.is_exit(hero.board_index):
		_victory()
	elif get_alive_monsters().is_empty():
		_victory()

func _victory() -> void:
	if phase == Phase.VICTORY:
		return
	phase = Phase.VICTORY
	phase_changed.emit(phase)
	message.emit("勇者抵达出口，地城探索胜利！")
	game_over.emit(true)

func get_phase_name() -> String:
	match phase:
		Phase.HERO_TURN:
			return "英雄回合"
		Phase.MONSTER_TURN:
			return "怪物回合"
		Phase.VICTORY:
			return "胜利"
		Phase.DEFEAT:
			return "失败"
	return ""

func get_gear_catalog() -> Dictionary:
	return gear_catalog
