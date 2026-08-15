class_name TopdownGame
extends Node

signal message(text: String)
signal damage_applied(source_name: String, target_name: String, amount: float, target: TopdownEntity, source: TopdownEntity)
signal attack_performed(form: TopdownAttackForm, from: TopdownEntity)
signal projectile_hit(pos: Vector2)
signal blast_effect(pos: Vector2, radius: float)
signal player_leveled_up(level: int)
signal monster_died(monster: TopdownMonster)
signal monster_respawned(monster: TopdownMonster)
signal chest_opened(chest: TopdownChest, loot_name: String)
signal game_over()
signal smite_casting()
signal anim_notify(notify_name: StringName)

## 地图：'#'=墙 '.'=地板 'P'=玩家出生 'M'=怪物出生 'C'=宝箱
const MAP: Array[String] = [
	"####################",
	"#....#.........#...#",
	"#.C..#..M......#C..#",
	"#....#...####...#...#",
	"#...........#......#",
	"#..M..........M....#",
	"#..........#........#",
	"#....C.....#.....M..#",
	"#....####.#.........#",
	"#.........#.....#...#",
	"#.........#..C..#...#",
	"#....P....####..#...#",
	"#..........#........#",
	"####################",
]
const TILE_SIZE: float = 32.0
const RESPAWN_DELAY: float = 3.0
const MONSTER_GROWTH_PER_LEVEL: float = 0.12
const SMITE_RADIUS: float = 90.0
const SMITE_COEFF: float = 1.8
const COMBO_WINDOW: float = 0.6
const COMBO_COEFF: float = 1.5
const COMBO_RANGE: float = 110.0
const COMBO_ARC_DEG: float = 50.0

const TAG_ATTACK := &"Ability.Attack"
const TAG_ATTACK_COOLDOWN := &"Ability.Attack.Cooldown"
const TAG_SMITE := &"Ability.Spell.Smite"
const TAG_BERSERK := &"Ability.Berserk"
const BERSERK_DURATION: float = 3.0

var player: TopdownPlayer
var monsters: Array[TopdownMonster] = []
var chests: Array[TopdownChest] = []
var projectiles: Array[TopdownProjectile] = []

var _grid: Array[Array] = []
var _wall_tiles: Array[Vector2i] = []
var _player_spawn: Vector2i
var _monster_spawns: Array[Vector2i] = []
var _chest_spawns: Array[Vector2i] = []

var attack_forms: Array[TopdownAttackForm] = []
var _attack_ge: GASGameplayEffect
var _cooldown_ge: GASGameplayEffect
var _xp_ge: GASGameplayEffect
var _heal_potion_ge: GASGameplayEffect
var _xp_potion_ge: GASGameplayEffect
var berserk_ge: GASGameplayEffect = null
var _gear_catalog: Dictionary = {}
var _respawn_queue: Array[Dictionary] = []  # {kind, tile, timer}
var _rng := RandomNumberGenerator.new()
var _running: bool = false

func _ready() -> void:
	_build_grid()
	_load_content()
	_build_attack_forms()
	_spawn_world()

## ---------------- 世界构建 ----------------

func _build_grid() -> void:
	_grid.clear()
	_wall_tiles.clear()
	for y in MAP.size():
		var row: Array = []
		for x in MAP[y].length():
			var c: String = MAP[y][x]
			var is_wall := c == "#"
			row.append(is_wall)
			if is_wall:
				_wall_tiles.append(Vector2i(x, y))
			elif c == "P":
				_player_spawn = Vector2i(x, y)
			elif c == "M":
				_monster_spawns.append(Vector2i(x, y))
			elif c == "C":
				_chest_spawns.append(Vector2i(x, y))
		_grid.append(row)

func _load_content() -> void:
	var base := "res://addons/gameplay_abilities_system/test_topdown/game/"
	_attack_ge = load(base + "items/ge_attack_damage.tres")
	_cooldown_ge = load(base + "items/ge_attack_cooldown.tres")
	_xp_ge = load(base + "items/ge_xp_gain.tres")
	_heal_potion_ge = load(base + "items/ge_heal_potion.tres")
	_xp_potion_ge = load(base + "items/ge_xp_potion.tres")
	_gear_catalog["sword"] = {"slot": TopdownPlayer.SLOT_WEAPON, "name": "铁剑", "ge": load(base + "gear/ge_sword.tres")}
	_gear_catalog["great_sword"] = {"slot": TopdownPlayer.SLOT_WEAPON, "name": "大剑", "ge": load(base + "gear/ge_great_sword.tres")}
	_gear_catalog["chain_mail"] = {"slot": TopdownPlayer.SLOT_ARMOUR, "name": "锁甲", "ge": load(base + "gear/ge_chain_mail.tres")}
	_gear_catalog["plate_mail"] = {"slot": TopdownPlayer.SLOT_ARMOUR, "name": "板甲", "ge": load(base + "gear/ge_plate_mail.tres")}
	_gear_catalog["ring_attack"] = {"slot": TopdownPlayer.SLOT_RING, "name": "力量之戒", "ge": load(base + "gear/ge_ring_attack.tres")}
	_gear_catalog["ring_speed"] = {"slot": TopdownPlayer.SLOT_RING, "name": "疾风之戒", "ge": load(base + "gear/ge_ring_speed.tres")}
	_gear_catalog["boots"] = {"slot": TopdownPlayer.SLOT_BOOTS, "name": "疾风靴", "ge": load(base + "gear/ge_boots.tres")}

func _build_attack_forms() -> void:
	attack_forms = [
		_make_form(&"斩击", 1, TopdownAttackForm.Kind.MELEE_ARC, 1.0, 84.0, 0.55),
		_make_form(&"飞弹", 3, TopdownAttackForm.Kind.PROJECTILE, 1.15, 360.0, 0.5),
		_make_form(&"三连", 5, TopdownAttackForm.Kind.SPREAD, 1.1, 360.0, 0.45),
		_make_form(&"裁决", 7, TopdownAttackForm.Kind.PIERCE_BLAST, 1.5, 420.0, 0.4),
	]

func _make_form(p_name: StringName, p_min_level: int, p_kind: TopdownAttackForm.Kind, p_coeff: float, p_range: float, p_cooldown: float) -> TopdownAttackForm:
	var form := TopdownAttackForm.new()
	form.form_name = p_name
	form.min_level = p_min_level
	form.kind = p_kind
	form.damage_coefficient = p_coeff
	form.range = p_range
	form.cooldown = p_cooldown
	if p_kind == TopdownAttackForm.Kind.PIERCE_BLAST:
		form.pierce = true
		form.splash_radius = 64.0
		form.projectile_speed = 340.0
	elif p_kind == TopdownAttackForm.Kind.SPREAD:
		form.count = 3
		form.spread_deg = 20.0
		form.projectile_speed = 320.0
	else:
		form.projectile_speed = 300.0
	return form

func _spawn_world() -> void:
	player = TopdownPlayer.new()
	player.name = "Player"
	add_child(player)
	var hero_attrs: Dictionary[StringName, float] = {
		&"Health": 100.0, &"MaxHealth": 100.0,
		&"Attack": 20.0, &"Defense": 3.0,
		&"MoveSpeed": 150.0, &"Level": 1.0, &"XP": 0.0,
	}
	var ability := GAPlayerAttack.new()
	ability.game = self
	ability.attack_ge = _attack_ge
	ability.cooldown_ge = _cooldown_ge
	var ability_tags := FGameplayTagContainer.new()
	ability_tags.add_tag(GameplayTags.request_gameplay_tag(TAG_ATTACK))
	ability.ability_tags = ability_tags
	var smite := GAPlayerSmite.new()
	smite.game = self
	var smite_tags := FGameplayTagContainer.new()
	smite_tags.add_tag(GameplayTags.request_gameplay_tag(TAG_SMITE))
	smite.ability_tags = smite_tags
	player.smite_ability = smite
	var combo := GAPlayerCombo.new()
	combo.game = self
	player.combo_ability = combo
	var berserk := GAPlayerBerserk.new()
	berserk.game = self
	var berserk_tags := FGameplayTagContainer.new()
	berserk_tags.add_tag(GameplayTags.request_gameplay_tag(TAG_BERSERK))
	berserk.ability_tags = berserk_tags
	var block_tags := FGameplayTagContainer.new()
	block_tags.add_tag(GameplayTags.request_gameplay_tag(TAG_SMITE))
	berserk.block_abilities_with_tags = block_tags
	var cancel_tags := FGameplayTagContainer.new()
	cancel_tags.add_tag(GameplayTags.request_gameplay_tag(TAG_SMITE))
	berserk.cancel_abilities_with_tags = cancel_tags
	player.berserk_ability = berserk
	player.setup_player(hero_attrs, ability)
	player.asc.give_ability(smite)
	player.asc.give_ability(combo)
	player.asc.give_ability(berserk)
	berserk_ge = GASGameplayEffect.new()
	berserk_ge.duration_policy = GASEnums.DurationPolicy.DURATION
	berserk_ge.duration = BERSERK_DURATION
	var berserk_granted := FGameplayTagContainer.new()
	berserk_granted.add_tag(GameplayTags.request_gameplay_tag(TAG_BERSERK))
	berserk_ge.granted_tag = berserk_granted
	var berserk_mod := GEModifier.new()
	berserk_mod.attr_name = &"Attack"
	berserk_mod.op = GASEnums.ModifierOp.MULTIPLY
	var berserk_mag := GASModifierMagnitudeScalableFloat.new()
	berserk_mag.value = 1.0
	berserk_mod.magnitude = berserk_mag
	berserk_ge.modifiers.append(berserk_mod)
	player.pos = _tile_to_world(_player_spawn)
	player.died.connect(_on_player_died)
	player.attr_set.leveled_up.connect(func(level: int) -> void:
		player_leveled_up.emit(level)
		message.emit("升级！Lv.%d —— 攻击形态：%s" % [level, get_current_attack_form().form_name]))
	player.equip_gear(_gear_catalog["sword"].ge, _gear_catalog["sword"].slot, _gear_catalog["sword"].name)

	var kind_index := 0
	for spawn in _monster_spawns:
		_spawn_monster(spawn, kind_index % TopdownMonster.KIND_COUNT)
		kind_index += 1
	for spawn in _chest_spawns:
		var chest := TopdownChest.new()
		chest.name = "Chest"
		add_child(chest)
		chest.setup_chest()
		chest.pos = _tile_to_world(spawn)
		chests.append(chest)

func _spawn_monster(spawn: Vector2i, kind_index: int = -1) -> TopdownMonster:
	var monster := TopdownMonster.new()
	monster.name = "Monster"
	add_child(monster)
	var cfg := TopdownMonster.get_kind_config(kind_index if kind_index >= 0 else _rng.randi_range(0, TopdownMonster.KIND_COUNT - 1))
	monster.setup_monster(cfg, _monster_growth_multiplier())
	monster.pos = _tile_to_world(spawn)
	monster.home_pos = monster.pos
	monster.died.connect(_on_monster_died)
	monsters.append(monster)
	return monster

func _monster_growth_multiplier() -> float:
	return 1.0 + MONSTER_GROWTH_PER_LEVEL * float(player.get_level() - 1)

## ---------------- 主循环（逻辑层唯一时钟） ----------------

func _process(delta: float) -> void:
	if not _running or not player:
		return
	_tick_player(delta)
	for monster in monsters:
		if monster.is_alive():
			monster.tick(delta, self)
	_tick_projectiles(delta)
	_tick_respawns(delta)

func start_game() -> void:
	_rng.randomize()
	_running = true
	message.emit("地城之光 —— WASD 移动，空格/左键攻击，E 开箱，R 重开")

func _tick_player(delta: float) -> void:
	if not player.is_alive():
		player.move_input = Vector2.ZERO
		return
	var input_dir := player.move_input
	if input_dir.length_squared() > 0.0:
		# 朝向由表现层控制（跟随鼠标），逻辑层只负责位移
		move_entity(player, delta, input_dir.normalized())

func _tick_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: TopdownProjectile = projectiles[i]
		p.traveled += p.speed * delta
		p.pos += p.dir * p.speed * delta
		if p.traveled >= p.form.range or _is_wall_at(p.pos):
			projectiles.remove_at(i)
			continue
		var target := _find_projectile_target(p)
		if target:
			if p.form.splash_radius > 0.0:
				_hit_blast(p, target)
			else:
				projectile_hit.emit(target.pos)
				_apply_damage(p.source, target, p.form)
			if not p.form.pierce:
				projectiles.remove_at(i)
			else:
				p.hit_targets.append(target)
				if p.hit_targets.size() >= 3:
					projectiles.remove_at(i)

func _tick_respawns(delta: float) -> void:
	for i in range(_respawn_queue.size() - 1, -1, -1):
		var entry: Dictionary = _respawn_queue[i]
		entry.timer = float(entry.timer) - delta
		if entry.timer <= 0.0:
			var monster := _spawn_monster(entry.tile, entry.kind)
			monster_respawned.emit(monster)
			message.emit("%s 从地底复活了！" % monster.display_name)
			_respawn_queue.remove_at(i)

## ---------------- 移动与碰撞 ----------------

func tile_to_world(tile: Vector2i) -> Vector2:
	return _tile_to_world(tile)

func _tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE + TILE_SIZE * 0.5, tile.y * TILE_SIZE + TILE_SIZE * 0.5)

func _world_to_tile(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / TILE_SIZE), floori(world.y / TILE_SIZE))

func is_wall_tile(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.y >= _grid.size() or tile.x >= _grid[tile.y].size():
		return true
	return _grid[tile.y][tile.x]

func _is_wall_at(pos: Vector2) -> bool:
	return is_wall_tile(_world_to_tile(pos))

func move_entity(e: TopdownEntity, delta: float, dir: Vector2) -> void:
	var speed := e.get_attr(&"MoveSpeed")
	if speed <= 0.0:
		return
	var step := dir * speed * delta
	var next_x := Vector2(e.pos.x + step.x, e.pos.y)
	if _can_occupy(e, next_x):
		e.pos.x = next_x.x
	var next_y := Vector2(e.pos.x, e.pos.y + step.y)
	if _can_occupy(e, next_y):
		e.pos.y = next_y.y

func _can_occupy(e: TopdownEntity, pos: Vector2) -> bool:
	if _is_wall_at(pos):
		return false
	for tile in _neighbor_wall_tiles(_world_to_tile(pos)):
		var rect := Rect2(tile.x * TILE_SIZE, tile.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		var clamped := Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.y, rect.position.y, rect.end.y))
		if pos.distance_to(clamped) < TopdownEntity.RADIUS:
			return false
	for other in get_all_entities():
		if other == e or not is_instance_valid(other):
			continue
		if pos.distance_to(other.pos) < TopdownEntity.RADIUS + other.RADIUS:
			return false
	return true

func _neighbor_wall_tiles(tile: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var t := tile + Vector2i(dx, dy)
			if is_wall_tile(t):
				result.append(t)
	return result

func get_all_entities() -> Array[TopdownEntity]:
	var result: Array[TopdownEntity] = [player]
	for monster in monsters:
		if monster.is_alive():
			result.append(monster)
	for chest in chests:
		result.append(chest)
	return result

## ---------------- 攻击 ----------------

func get_current_attack_form() -> TopdownAttackForm:
	var level := player.get_level()
	var current := attack_forms[0]
	for form in attack_forms:
		if level >= form.min_level:
			current = form
	return current

func do_entity_melee_attack(source: TopdownEntity, form: TopdownAttackForm, open_combo: bool = true) -> void:
	attack_performed.emit(form, source)
	if source is TopdownPlayer:
		var hit_count := 0
		for monster in monsters:
			if not monster.is_alive():
				continue
			var to_monster := monster.pos - source.pos
			if to_monster.length() > form.range + monster.RADIUS:
				continue
			var angle := rad_to_deg(to_monster.angle_to(source.facing))
			if absf(angle) > form.arc_half_angle_deg:
				continue
			_apply_damage(source, monster, form)
			hit_count += 1
		if hit_count > 0:
			message.emit("斩击命中 %d 个敌人" % hit_count)
		else:
			message.emit("斩击挥空……")
		if open_combo:
			player.open_combo_window()
	else:
		var to_player := player.pos - source.pos
		if to_player.length() <= form.range + player.RADIUS:
			_apply_damage(source, player, form)

func spawn_projectiles(form: TopdownAttackForm, count: int) -> void:
	attack_performed.emit(form, player)
	var dirs: Array[Vector2] = []
	if count == 1:
		dirs = [player.facing]
	else:
		for i in count:
			var offset := float(i) - float(count - 1) * 0.5
			dirs.append(player.facing.rotated(deg_to_rad(offset * form.spread_deg)))
	for dir in dirs:
		var projectile := TopdownProjectile.new()
		projectile.pos = player.pos + dir * 20.0
		projectile.dir = dir
		projectile.speed = form.projectile_speed
		projectile.form = form
		projectile.source = player
		projectiles.append(projectile)
	player.open_combo_window()

func do_combo_strike() -> void:
	var form := TopdownAttackForm.new()
	form.kind = TopdownAttackForm.Kind.MELEE_ARC
	form.form_name = "连击"
	form.damage_coefficient = COMBO_COEFF
	form.range = COMBO_RANGE
	form.arc_half_angle_deg = COMBO_ARC_DEG
	do_entity_melee_attack(player, form, false)

func spawn_monster_projectile(monster: TopdownMonster, dir: Vector2) -> void:
	var form := TopdownAttackForm.new()
	form.kind = TopdownAttackForm.Kind.PROJECTILE
	form.form_name = "骨箭"
	form.damage_coefficient = 1.0
	form.range = 420.0
	form.projectile_speed = 240.0
	form.splash_radius = 0.0
	form.pierce = false
	var projectile := TopdownProjectile.new()
	projectile.pos = monster.pos + dir * 22.0
	projectile.dir = dir
	projectile.speed = form.projectile_speed
	projectile.form = form
	projectile.source = monster
	projectiles.append(projectile)

func _find_projectile_target(p: TopdownProjectile) -> TopdownEntity:
	if p.source == player:
		for monster in monsters:
			if not monster.is_alive():
				continue
			if p.hit_targets.has(monster):
				continue
			if monster.pos.distance_to(p.pos) < monster.RADIUS + 6.0:
				return monster
	else:
		if p.source is TopdownMonster and player.is_alive() and p.hit_targets.is_empty():
			if player.pos.distance_to(p.pos) < player.RADIUS + 6.0:
				return player
	return null

func _hit_blast(p: TopdownProjectile, direct_target: TopdownEntity) -> void:
	_apply_damage(p.source, direct_target, p.form)
	var center: Vector2 = direct_target.pos if direct_target.is_alive() else p.pos
	blast_effect.emit(center, p.form.splash_radius)
	for monster in monsters:
		if not monster.is_alive() or monster == direct_target:
			continue
		if monster.pos.distance_to(center) <= p.form.splash_radius:
			_apply_damage(p.source, monster, p.form)

func _apply_damage(source: TopdownEntity, target: TopdownEntity, form: TopdownAttackForm) -> void:
	if not target.is_alive() or not source.is_alive():
		return
	var spec: GASEffectSpec = source.asc.make_effect_spec(_attack_ge)
	spec.set_setbycaller_magnitude(&"coeff", form.damage_coefficient)
	source.asc.apply_gameplay_effect_spec_to_target(spec, target.asc)
	var damage := maxf(1.0, source.get_attr(&"Attack") * form.damage_coefficient - target.get_attr(&"Defense"))
	damage_applied.emit(source.display_name, target.display_name, damage, target, source)

func do_smite(targets: Array[TopdownEntity], center: Vector2) -> void:
	if targets.is_empty():
		return
	var form := TopdownAttackForm.new()
	form.kind = TopdownAttackForm.Kind.PIERCE_BLAST
	form.form_name = "落雷"
	form.damage_coefficient = SMITE_COEFF
	form.splash_radius = SMITE_RADIUS
	for target in targets:
		_apply_damage(player, target, form)
	attack_performed.emit(form, player)
	blast_effect.emit(center, SMITE_RADIUS)
	message.emit("落雷！命中 %d 个敌人" % targets.size())

func start_smite_casting() -> void:
	smite_casting.emit()

func _on_monster_died(entity: TopdownEntity) -> void:
	var monster := entity as TopdownMonster
	monster_died.emit(monster)
	var xp_gain := 15.0 * float(monster.level) * float(player.get_level())
	_give_player_xp(xp_gain)
	message.emit("%s 被击败了！（经验 +%d）" % [monster.display_name, int(xp_gain)])
	monsters.erase(monster)
	_respawn_queue.append({"kind": monster.kind_index, "tile": _world_to_tile(monster.home_pos), "timer": RESPAWN_DELAY})
	monster.queue_free()

func _give_player_xp(amount: float) -> void:
	var spec: GASEffectSpec = player.asc.make_effect_spec(_xp_ge)
	spec.set_setbycaller_magnitude(&"xp", amount)
	player.asc.apply_gameplay_effect_spec_to_self(spec)

func _on_player_died(_entity: TopdownEntity) -> void:
	_running = false
	message.emit("勇者倒下了……按 R 重开")
	game_over.emit()

## ---------------- 宝箱交互 ----------------

func try_interact() -> void:
	if not _running or not player.is_alive():
		return
	for chest in chests:
		if chest.opened:
			continue
		if chest.pos.distance_to(player.pos) <= 56.0:
			_open_chest(chest)
			return

func _open_chest(chest: TopdownChest) -> void:
	chest.opened = true
	var roll := _rng.randi_range(0, 4)
	match roll:
		0, 1:
			var spec: GASEffectSpec = player.asc.make_effect_spec(_heal_potion_ge)
			player.asc.apply_gameplay_effect_spec_to_self(spec)
			chest_opened.emit(chest, "治疗药水（恢复 40 体力）")
		2:
			var xp_spec: GASEffectSpec = player.asc.make_effect_spec(_xp_potion_ge)
			player.asc.apply_gameplay_effect_spec_to_self(xp_spec)
			chest_opened.emit(chest, "经验药水（+35 XP）")
		3, 4:
			var gear_names: Array[String] = []
			for key in _gear_catalog.keys():
				gear_names.append(key)
			var key: String = gear_names[_rng.randi_range(0, gear_names.size() - 1)]
			var entry: Dictionary = _gear_catalog[key]
			player.equip_gear(entry.ge, entry.slot, entry.name)
			chest_opened.emit(chest, "装备「%s」（%s 槽）" % [entry.name, entry.slot])

## ---------------- 查询与测试辅助 ----------------

func get_alive_monsters() -> Array[TopdownMonster]:
	var alive: Array[TopdownMonster] = []
	for monster in monsters:
		if monster.is_alive():
			alive.append(monster)
	return alive

func get_chest_at(tile: Vector2i) -> TopdownChest:
	for chest in chests:
		if _world_to_tile(chest.pos) == tile:
			return chest
	return null

func get_monster_at(tile: Vector2i) -> TopdownMonster:
	for monster in monsters:
		if monster.is_alive() and _world_to_tile(monster.pos) == tile:
			return monster
	return null

func get_player() -> TopdownPlayer:
	return player

func get_gear_catalog() -> Dictionary:
	return _gear_catalog
