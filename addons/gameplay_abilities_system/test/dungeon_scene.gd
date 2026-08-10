extends Node2D

const ICON_DIR := "res://assets/game-icons.net/icons/"

const HAND_CARDS: Array[Dictionary] = [
	{"key": "melee", "name": "攻击", "icon": "swords-power", "cost": "—", "need_target": true,
		"desc": "近战攻击：伤害 = 攻击 − 防御（需相邻）"},
	{"key": "fireball", "name": "火球术", "icon": "fire-spell-cast", "cost": "15", "need_target": true,
		"desc": "蓄力 0.6s 后对目标造成 30+等级×10 伤害"},
	{"key": "heal", "name": "治疗术", "icon": "healing", "cost": "10", "need_target": false,
		"desc": "恢复 40 点体力"},
	{"key": "poison", "name": "毒雾术", "icon": "poison-cloud", "cost": "20", "need_target": true,
		"desc": "目标中毒：6s 内每秒扣 6 点体力"},
	{"key": "frost", "name": "冰霜新星", "icon": "ice-spell-cast", "cost": "15", "need_target": true,
		"desc": "目标减速 6s（Move -2，无法接近你）"},
	{"key": "shield", "name": "护盾术", "icon": "healing-shield", "cost": "10", "need_target": false,
		"desc": "6s 内防御 +15"},
	{"key": "potion_heal", "name": "治疗药水", "icon": "health-potion", "cost": "行动", "need_target": false,
		"desc": "恢复 30 点体力"},
	{"key": "potion_mana", "name": "法力药水", "icon": "magic-potion", "cost": "行动", "need_target": false,
		"desc": "恢复 30 点魔力"},
]

const GEAR_SLOTS: Array[Dictionary] = [
	{"slot": "weapon", "name": "武器", "options": [
		{"ge": "ge_sword", "icon": "ancient-sword", "label": "铁剑"},
		{"ge": "ge_great_sword", "icon": "rune-sword", "label": "大剑"}]},
	{"slot": "shield", "name": "盾牌", "options": [
		{"ge": "ge_wooden_shield", "icon": "shield", "label": "木盾"},
		{"ge": "ge_iron_shield", "icon": "attached-shield", "label": "铁盾"},
		{"ge": "ge_holy_shield", "icon": "spiked-shield", "label": "圣盾"}]},
	{"slot": "boots", "name": "疾风靴", "options": [{"ge": "ge_boots_of_wind", "icon": "metal-boot", "label": "疾风靴"}]},
	{"slot": "ring", "name": "疾风戒指", "options": [{"ge": "ge_ring_of_wind", "icon": "power-ring", "label": "疾风戒"}]},
	{"slot": "belt", "name": "巨人腰带", "options": [{"ge": "ge_giant_belt", "icon": "belt", "label": "巨人腰"}]},
	{"slot": "crystal", "name": "法力水晶", "options": [{"ge": "ge_mana_crystal", "icon": "crystal-cluster", "label": "水晶"}]},
]

const STATUS_ICONS := {
	&"State.Debuff.Stun": {"icon": "knocked-out-stars", "label": "眩晕"},
	&"State.Debuff.Poison": {"icon": "poison", "label": "中毒"},
	&"State.Debuff.Slow": {"icon": "snowflake-1", "label": "减速"},
	&"State.Buff.Shield": {"icon": "shield", "label": "护盾"},
}

const CUE_STUN_TAG := &"GameplayCue.Status.Stun"
const CUE_HIT_TAG := &"GameplayCue.Damage.Hit"
const STUN_CUE_SCRIPT := preload("res://addons/gameplay_abilities_system/test/cues/stun_cue.gd")

const TILE_ICONS := {
	"TRAP": "spiked-wall", "TREASURE": "open-chest", "EXIT": "dungeon-gate",
}

const MONSTER_ICONS := {
	"哥布林": "goblin-head", "骷髅兵": "skull-crack", "兽人": "orc-head",
	"毒蛇": "snake", "屠夫": "bone-mace",
}

var game: DungeonGame
var test_runner: DungeonGameTest

var _selected_monster: DungeonMonster = null
var _tile_buttons: Array[Button] = []
var _tile_icon_rects: Array[TextureRect] = []
var _tile_occupant_rects: Array[TextureRect] = []
var _monster_buttons: Dictionary = {}
var _monster_body_bars: Dictionary = {}
var _hand_buttons: Dictionary = {}
var _hand_cd_labels: Dictionary = {}
var _gear_buttons: Dictionary = {}
var _status_icons: Dictionary = {}
var _overlay: VBoxContainer = null
var _overlay_title: Label = null
var _ui_timer: float = 0.0
var _log_lines: Array[String] = []
# GameplayCue 消费者：实体 → 其上的眩晕凭票根数组（表现层只管表现，逻辑层零感知）
var _stun_tickets: Dictionary = {}

@onready var phase_label: Label = $CanvasLayer/Root/MainVBox/TopBar/PhaseBadge/PhaseLabel
@onready var turn_info_label: Label = $CanvasLayer/Root/MainVBox/TopBar/TurnInfoLabel
@onready var end_turn_button: Button = $CanvasLayer/Root/MainVBox/TopBar/EndTurnButton
@onready var portrait: TextureRect = $CanvasLayer/Root/MainVBox/PlayArea/PanelHero/HeroVBox/HeroHeader/Portrait
@onready var hero_name_label: Label = $CanvasLayer/Root/MainVBox/PlayArea/PanelHero/HeroVBox/HeroHeader/HeroNameBox/HeroNameLabel
@onready var level_label: Label = $CanvasLayer/Root/MainVBox/PlayArea/PanelHero/HeroVBox/HeroHeader/HeroNameBox/LevelLabel
@onready var body_bar: ProgressBar = $CanvasLayer/Root/MainVBox/PlayArea/PanelHero/HeroVBox/BodyBar
@onready var mind_bar: ProgressBar = $CanvasLayer/Root/MainVBox/PlayArea/PanelHero/HeroVBox/MindBar
@onready var stats_label: Label = $CanvasLayer/Root/MainVBox/PlayArea/PanelHero/HeroVBox/StatsLabel
@onready var gear_label: Label = $CanvasLayer/Root/MainVBox/PlayArea/PanelHero/HeroVBox/GearLabel
@onready var status_row: HBoxContainer = $CanvasLayer/Root/MainVBox/PlayArea/PanelHero/HeroVBox/StatusRow
@onready var monster_title: Label = $CanvasLayer/Root/MainVBox/PlayArea/PanelMonsters/MonsterVBox/MonsterTitle
@onready var monster_vbox: VBoxContainer = $CanvasLayer/Root/MainVBox/PlayArea/PanelMonsters/MonsterVBox
@onready var board_row: HBoxContainer = $CanvasLayer/Root/MainVBox/PlayArea/PanelBoard/BoardVBox/BoardRow
@onready var board_hint_label: Label = $CanvasLayer/Root/MainVBox/PlayArea/PanelBoard/BoardVBox/BoardHintLabel
@onready var board_vbox: VBoxContainer = $CanvasLayer/Root/MainVBox/PlayArea/PanelBoard/BoardVBox
@onready var log_label: RichTextLabel = $CanvasLayer/Root/MainVBox/PlayArea/PanelLog/LogLabel
@onready var hand_row: HBoxContainer = $CanvasLayer/Root/MainVBox/HandPanel/HandRow

func _ready() -> void:
	_build_board_tiles()
	_build_hand()
	_build_gear_row()
	_build_status_icons()
	_register_cue_consumers()
	_new_game()
	if "--run-tests" in OS.get_cmdline_user_args():
		await _run_regression()
		game.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(0 if test_runner.is_pass() else 1)
	elif "--ui-check" in OS.get_cmdline_user_args():
		get_window().size = Vector2i(1152, 648)
		await get_tree().process_frame
		await get_tree().process_frame
		var vp_size := get_window().size
		print("UI_CHECK window=", vp_size)
		var root := $CanvasLayer/Root as Control
		print("UI_CHECK root anchors=", root.anchor_left, ",", root.anchor_top, ",", root.anchor_right, ",", root.anchor_bottom, " offsets=", root.offset_left, ",", root.offset_top, ",", root.offset_right, ",", root.offset_bottom)
		print("UI_CHECK vp_rect=", get_viewport().get_visible_rect())
		var issues := 0
		var controls := $CanvasLayer.find_children("*", "Control", true, false)
		for node in controls:
			var c := node as Control
			var rect := c.get_global_rect()
			if rect.position.x < -1.0 or rect.position.y < -1.0 or rect.end.x > vp_size.x + 1.0 or rect.end.y > vp_size.y + 1.0:
				print("UI_CHECK OVERFLOW: ", node.get_path(), " rect=", rect)
				issues += 1
		print("UI_CHECK issues=", issues)
		get_tree().quit(0 if issues == 0 else 1)
	elif "--screenshot" in OS.get_cmdline_user_args():
		var shot_path: String = ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screenshot="):
				shot_path = arg.trim_prefix("--screenshot=")
		await get_tree().create_timer(1.5).timeout
		print("SHOT: capturing viewport")
		var img := get_viewport().get_texture().get_image()
		print("SHOT: image size ", img.get_size())
		img.save_png(shot_path)
		print("SHOT: saved")
		get_tree().quit(0)

func _new_game() -> void:
	_clear_selection()
	_clear_cue_markers()
	_hide_overlay()
	for btn in _monster_buttons.values():
		btn.queue_free()
	_monster_buttons.clear()
	_monster_body_bars.clear()
	if game:
		game.queue_free()
	game = DungeonGame.new()
	game.name = "Game"
	add_child(game)
	game.turn_delay = 0.45
	game.rng.seed = 20260809
	game.setup_default_game()
	_connect_game()
	game.start_game()
	_refresh_all()

func _connect_game() -> void:
	game.phase_changed.connect(func(_p): _refresh_all())
	game.hero_moved.connect(func(_h, _f, _t): _refresh_all())
	game.monster_moved.connect(func(_m, _f, _t): _refresh_all())
	game.damage_applied.connect(func(s, _t, d): _push_log("%s 造成 %d 点伤害" % [s, int(d)]))
	game.effect_applied.connect(func(t, e): _push_log("%s 获得效果：%s" % [t, e]))
	game.message.connect(_push_log)
	game.game_over.connect(_on_game_over)
	game.hero.attr_set.attribute_changed.connect(func(_a, _n, _o): _refresh_all())
	game.hero.gear_changed.connect(func(_s, _n): _refresh_all())
	game.hero.ability_result.connect(_on_ability_result)

func _on_ability_result(label: String, success: bool) -> void:
	if not success:
		_push_log("【%s】被拒绝（冷却/法力不足/眩晕/行动次数）" % label)

# —— GameplayCue 消费者（表现层）：只消费事件做表现，逻辑层零感知 ——

func _register_cue_consumers() -> void:
	var stun_tag: FGameplayTag = GameplayTags.request_gameplay_tag(CUE_STUN_TAG)
	var hit_tag: FGameplayTag = GameplayTags.request_gameplay_tag(CUE_HIT_TAG)
	GameplayCueManager.register_factory(stun_tag, _cue_factory_stun)
	GameplayCueManager.register(stun_tag, _on_cue_event)
	GameplayCueManager.register(hit_tag, _on_cue_event)

func _cue_factory_stun(_params: GASGameplayCueParameters) -> Node:
	return STUN_CUE_SCRIPT.new()

func _on_cue_event(tag: FGameplayTag, event: GASEnums.GameplayCueEvent, params: GASGameplayCueParameters) -> void:
	var entity := params.target as DungeonEntity
	if entity == null or entity.board_index < 0 or entity.board_index >= _tile_buttons.size():
		return
	match event:
		GASEnums.GameplayCueEvent.ON_ACTIVE:
			var handle := GameplayCueManager.add_cue(tag, _tile_buttons[entity.board_index], params)
			if not _stun_tickets.has(entity):
				_stun_tickets[entity] = []
			_stun_tickets[entity].append(handle)
		GASEnums.GameplayCueEvent.ON_REMOVED:
			if _stun_tickets.has(entity):
				for handle in _stun_tickets[entity]:
					GameplayCueManager.remove_cue(handle)
				_stun_tickets.erase(entity)
		GASEnums.GameplayCueEvent.EXECUTED:
			_spawn_damage_text(entity, params.magnitude)

func _clear_cue_markers() -> void:
	for entity in _stun_tickets:
		for handle in _stun_tickets[entity]:
			GameplayCueManager.remove_cue(handle)
	_stun_tickets.clear()

func _spawn_damage_text(entity: DungeonEntity, magnitude: float) -> void:
	var label := Label.new()
	var has_value := not is_zero_approx(magnitude)
	label.text = str(int(magnitude)) if has_value else "受击"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if has_value else Color(1, 0.65, 0.35))
	label.set_position(Vector2(14, 4))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tile_buttons[entity.board_index].add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", 4.0 - 26.0, 0.7)
	tw.tween_property(label, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(label.queue_free)

func _load_icon(name: String) -> Texture2D:
	return load(ICON_DIR + name + ".svg")

func _make_stylebox(bg: Color, border: Color, border_w: int = 1, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_right = radius
	sb.corner_radius_bottom_left = radius
	return sb

func _build_board_tiles() -> void:
	for i in 9:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(40, 40)
		btn.tooltip_text = "第 %d 格" % i
		btn.pressed.connect(_on_tile_pressed.bind(i))
		board_row.add_child(btn)
		_tile_buttons.append(btn)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)
		_tile_icon_rects.append(icon)
		var occupant := TextureRect.new()
		occupant.custom_minimum_size = Vector2(20, 20)
		occupant.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		occupant.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		occupant.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(occupant)
		_tile_occupant_rects.append(occupant)

func _build_hand() -> void:
	for i in HAND_CARDS.size():
		var cfg: Dictionary = HAND_CARDS[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(96, 86)
		btn.tooltip_text = cfg.desc
		btn.pressed.connect(_on_hand_card_pressed.bind(cfg))
		hand_row.add_child(btn)
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.offset_left = 6.0
		vbox.offset_right = -6.0
		vbox.offset_top = 4.0
		vbox.offset_bottom = -4.0
		btn.add_child(vbox)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _load_icon(cfg.icon)
		vbox.add_child(icon)
		var name_label := Label.new()
		name_label.text = cfg.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 12)
		vbox.add_child(name_label)
		var cost_label := Label.new()
		cost_label.text = "消耗 " + cfg.cost
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.add_theme_color_override("font_color", Color(0.6, 0.68, 0.85))
		cost_label.add_theme_font_size_override("font_size", 11)
		vbox.add_child(cost_label)
		_hand_buttons[cfg.key] = btn
		_hand_cd_labels[cfg.key] = cost_label

func _build_gear_row() -> void:
	var row := HBoxContainer.new()
	row.name = "GearRow"
	row.add_theme_constant_override("separation", 4)
	stats_label.get_parent().add_child(row)
	stats_label.get_parent().move_child(row, stats_label.get_index() + 1)
	for cfg in GEAR_SLOTS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(36, 36)
		btn.tooltip_text = cfg.name
		btn.pressed.connect(_on_gear_pressed.bind(cfg))
		row.add_child(btn)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _load_icon(cfg.options[0].icon)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)
		_gear_buttons[cfg.slot] = btn

func _build_status_icons() -> void:
	for tag_name in STATUS_ICONS:
		var info: Dictionary = STATUS_ICONS[tag_name]
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _load_icon(info.icon)
		icon.tooltip_text = info.label
		icon.visible = false
		status_row.add_child(icon)
		_status_icons[tag_name] = icon

func _on_tile_pressed(index: int) -> void:
	if not game or not game.hero or not game.hero.is_alive():
		return
	if game.phase != DungeonGame.Phase.HERO_TURN:
		return
	var monster: DungeonMonster = game.get_monster_at(index)
	if monster:
		_select_target(monster)
		return
	if index == game.hero.board_index:
		return
	var steps := 0
	while game.hero.board_index != index and game.moves_left > 0:
		var dir := signi(index - game.hero.board_index)
		if not game.hero_move(dir):
			if game.get_monster_at(game.hero.board_index + dir) != null:
				board_hint_label.text = "怪物挡住了去路——先击败它，或选择其他目标"
			break
		steps += 1
	if steps > 0:
		_refresh_all()

func _on_monster_pressed(monster: DungeonMonster) -> void:
	_select_target(monster)

func _on_hand_card_pressed(cfg: Dictionary) -> void:
	if not game or not game.hero:
		return
	match cfg.key:
		"melee":
			var target := _selected_monster if _selected_monster and _selected_monster.is_alive() else game.get_adjacent_monster()
			if target:
				if not game.hero_attack(target):
					board_hint_label.text = "攻击被拒绝（距离/冷却/眩晕/行动次数）"
			else:
				board_hint_label.text = "没有可攻击的相邻怪物"
		"fireball", "poison", "frost":
			var spell: GASGameplayAbility = game.hero.spells[HAND_SPELL_TAG[cfg.key]]
			if cfg.need_target and not (_selected_monster and _selected_monster.is_alive()):
				board_hint_label.text = "请先点击怪物选择目标，再点技能卡"
				return
			if not game.hero_cast(spell, _selected_monster):
				board_hint_label.text = "施法被拒绝（法力不足/冷却/眩晕/行动次数）"
		"heal", "shield":
			var heal_spell: GASGameplayAbility = game.hero.spells[HAND_SPELL_TAG[cfg.key]]
			if not game.hero_cast(heal_spell):
				board_hint_label.text = "施法被拒绝（法力不足/冷却/眩晕/行动次数）"
		"potion_heal":
			if not game.hero_use_potion("healing"):
				board_hint_label.text = "无法使用药水（行动次数或阶段限制）"
		"potion_mana":
			if not game.hero_use_potion("mana"):
				board_hint_label.text = "无法使用药水（行动次数或阶段限制）"
	_refresh_all()

const HAND_SPELL_TAG := {
	"fireball": &"Ability.Spell.Fireball", "heal": &"Ability.Spell.Heal",
	"poison": &"Ability.Spell.PoisonCloud", "frost": &"Ability.Spell.FrostNova",
	"shield": &"Ability.Spell.Shield",
}

func _on_gear_pressed(cfg: Dictionary) -> void:
	var hero := game.hero
	if hero.get_gear_name(cfg.slot).is_empty():
		var first: Dictionary = cfg.options[0]
		hero.equip_gear(game.gear_catalog[first.ge].ge, cfg.slot, first.ge)
	else:
		var current := hero.get_gear_name(cfg.slot)
		var found := false
		for i in cfg.options.size():
			if cfg.options[i].ge == current:
				var next_opt: Dictionary = cfg.options[(i + 1) % cfg.options.size()]
				hero.equip_gear(game.gear_catalog[next_opt.ge].ge, cfg.slot, next_opt.ge)
				found = true
				break
		if not found:
			hero.unequip_gear(cfg.slot)
	_refresh_all()

func _select_target(monster: DungeonMonster) -> void:
	_clear_selection()
	_selected_monster = monster
	if monster and not monster.is_alive():
		_selected_monster = null
	_refresh_all()

func _clear_selection() -> void:
	_selected_monster = null

func _on_game_over(won: bool) -> void:
	_push_log("游戏结束：" + ("胜利！" if won else "失败……"))
	_show_overlay(won)

func _show_overlay(won: bool) -> void:
	if _overlay:
		return
	_overlay = VBoxContainer.new()
	_overlay.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_theme_constant_override("separation", 10)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.offset_top = 60.0
	_overlay.offset_bottom = -60.0
	board_vbox.add_child(_overlay)
	board_vbox.move_child(_overlay, 0)
	_overlay_title = Label.new()
	_overlay_title.text = "🏆 胜利！全歼怪物/抵达出口" if won else "💀 勇者倒下了……"
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 26)
	_overlay_title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35) if won else Color(0.9, 0.4, 0.4))
	_overlay.add_child(_overlay_title)
	var sub := Label.new()
	sub.text = "按 R 或点击下方按钮重新开始"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	_overlay.add_child(sub)
	var btn := Button.new()
	btn.text = "重新开始"
	btn.pressed.connect(_new_game)
	btn.add_theme_font_size_override("font_size", 15)
	btn.custom_minimum_size = Vector2(140, 40)
	_overlay.add_child(btn)

func _hide_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
		_overlay_title = null

func _process(delta: float) -> void:
	_ui_timer += delta
	if _ui_timer >= 0.25:
		_ui_timer = 0.0
		if game and game.hero:
			_refresh_cards()
			_refresh_tiles()
			_refresh_turn_info()

func _refresh_all() -> void:
	if not game or not game.hero:
		return
	_refresh_hero()
	_refresh_cards()
	_refresh_tiles()
	_refresh_monsters()
	_refresh_turn_info()
	_refresh_log()

func _refresh_hero() -> void:
	var hero := game.hero
	if not portrait.texture:
		portrait.texture = _load_icon("swordman")
	hero_name_label.text = hero.display_name
	level_label.text = "等级 %d" % int(hero.get_attr(&"Level"))
	body_bar.max_value = maxf(1.0, hero.get_attr(&"MaxBody"))
	body_bar.value = hero.get_attr(&"Body")
	body_bar.tooltip_text = "体力 %d / %d" % [int(hero.get_attr(&"Body")), int(hero.get_attr(&"MaxBody"))]
	mind_bar.max_value = maxf(1.0, hero.get_attr(&"MaxMind"))
	mind_bar.value = hero.get_attr(&"Mind")
	mind_bar.tooltip_text = "魔力 %d / %d" % [int(hero.get_attr(&"Mind")), int(hero.get_attr(&"MaxMind"))]
	stats_label.text = "攻击 %d · 防御 %d · 移动 %d · 冷却缩减 %d%%" % [
		int(hero.get_attr(&"Attack")), int(hero.get_attr(&"Defense")),
		int(hero.get_attr(&"Move")), int(hero.get_attr(&"CooldownReduction") * 100.0)]
	var gear_parts: Array[String] = []
	for cfg in GEAR_SLOTS:
		var name := hero.get_gear_name(cfg.slot)
		if not name.is_empty():
			for opt in cfg.options:
				if opt.ge == name:
					gear_parts.append(opt.label)
	gear_label.text = "装备：" + ("、".join(gear_parts) if not gear_parts.is_empty() else "无")
	for tag_name in _status_icons:
		var icon: TextureRect = _status_icons[tag_name]
		var has := hero.asc.has_tag(GameplayTags.request_gameplay_tag(tag_name))
		icon.visible = has
		if has:
			var info: Dictionary = STATUS_ICONS[tag_name]
			icon.tooltip_text = info.label
	for slot in _gear_buttons:
		var btn: Button = _gear_buttons[slot]
		var equipped := not hero.get_gear_name(slot).is_empty()
		if equipped:
			btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.22, 0.3, 0.25), Color(0.6, 0.85, 0.5), 2))
			btn.modulate = Color(1, 1, 1)
		else:
			btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.14, 0.16, 0.2), Color(0.35, 0.4, 0.5)))
			btn.modulate = Color(0.7, 0.7, 0.7)

func _card_ability(cfg: Dictionary) -> GASGameplayAbility:
	if cfg.key == "melee":
		return game.hero.melee_strike
	return game.hero.spells[HAND_SPELL_TAG[cfg.key]]

func _refresh_cards() -> void:
	var hero := game.hero
	for cfg in HAND_CARDS:
		var btn: Button = _hand_buttons[cfg.key]
		var cd_label: Label = _hand_cd_labels[cfg.key]
		var disabled := false
		var cd_text := ""
		if game.phase != DungeonGame.Phase.HERO_TURN or not hero.is_alive():
			disabled = true
			cd_text = "等待回合"
		elif hero.is_stunned():
			disabled = true
			cd_text = "眩晕中"
		elif game.action_used:
			disabled = true
			cd_text = "行动已用"
		elif not cfg.key.begins_with("potion"):
			var spell := _card_ability(cfg)
			if not spell.can_activate():
				var cd_remaining := _get_cooldown_remaining(spell)
				if cd_remaining > 0.0:
					disabled = true
					cd_text = "冷却 %0.1fs" % cd_remaining
				else:
					disabled = true
					cd_text = "法力不足"
		btn.disabled = disabled
		btn.modulate = Color(0.45, 0.45, 0.5) if disabled else Color(1, 1, 1)
		if not cd_text.is_empty():
			cd_label.text = cd_text
			cd_label.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
		else:
			cd_label.text = "消耗 " + cfg.cost
			cd_label.add_theme_color_override("font_color", Color(0.6, 0.68, 0.85))
		var tip: String = cfg.desc
		if not cd_text.is_empty() and cd_text != "等待回合":
			tip += "\n[%s]" % cd_text
		if cfg.need_target:
			tip += "\n" + ("目标：" + (_selected_monster.display_name if _selected_monster else "未选择（先点怪物）"))
		btn.tooltip_text = tip

func _get_cooldown_remaining(spell: GASGameplayAbility) -> float:
	if not spell.cooldown_ge or spell.cooldown_ge.granted_tag._tags.is_empty():
		return 0.0
	var cd_tag: FGameplayTag = spell.cooldown_ge.granted_tag._tags.keys()[0]
	for entry in game.hero.asc._active_effects:
		if entry.granted_tags._tags.has(cd_tag):
			return entry.remaining_time
	return 0.0

func _refresh_tiles() -> void:
	for i in _tile_buttons.size():
		var btn: Button = _tile_buttons[i]
		var icon: TextureRect = _tile_icon_rects[i]
		var occupant: TextureRect = _tile_occupant_rects[i]
		var tile_type: int = game.board.get_tile_type(i)
		var bg := Color(0.13, 0.15, 0.19)
		var border := Color(0.32, 0.36, 0.44)
		icon.visible = false
		occupant.visible = false
		match tile_type:
			DungeonBoard.TileType.TRAP:
				icon.texture = _load_icon(TILE_ICONS.TRAP)
				icon.visible = true
				bg = Color(0.16, 0.1, 0.09)
				border = Color(0.5, 0.25, 0.2)
			DungeonBoard.TileType.TREASURE:
				icon.texture = _load_icon(TILE_ICONS.TREASURE)
				icon.visible = true
				bg = Color(0.14, 0.13, 0.08)
				border = Color(0.55, 0.5, 0.2)
			DungeonBoard.TileType.EXIT:
				icon.texture = _load_icon(TILE_ICONS.EXIT)
				icon.visible = true
				bg = Color(0.08, 0.12, 0.15)
				border = Color(0.3, 0.55, 0.65)
		var monster: DungeonMonster = game.get_monster_at(i)
		if monster:
			occupant.texture = _load_icon(MONSTER_ICONS.get(monster.display_name, "skull-crack"))
			occupant.visible = true
			bg = Color(0.2, 0.09, 0.1)
			border = Color(0.75, 0.3, 0.3)
		if game.hero.board_index == i:
			occupant.texture = _load_icon("swordman")
			occupant.visible = true
			bg = Color(0.12, 0.2, 0.14)
			border = Color(0.5, 0.85, 0.55)
			btn.tooltip_text = "勇者所在格"
		elif game.phase == DungeonGame.Phase.HERO_TURN and _is_reachable(i):
			bg = Color(0.12, 0.19, 0.12)
			border = Color(0.4, 0.7, 0.4)
			btn.tooltip_text = "点击移动到此格"
		elif btn.tooltip_text.is_empty():
			btn.tooltip_text = "第 %d 格" % i
		btn.add_theme_stylebox_override("normal", _make_stylebox(bg, border))
		btn.add_theme_stylebox_override("hover", _make_stylebox(bg.lightened(0.15), border.lightened(0.3)))

func _is_reachable(index: int) -> bool:
	if game.moves_left <= 0:
		return false
	if absi(index - game.hero.board_index) != 1:
		return false
	return game.get_monster_at(index) == null

func _refresh_monsters() -> void:
	for monster in game.monsters:
		if not _monster_buttons.has(monster):
			_build_monster_card(monster)
		var btn: Button = _monster_buttons[monster]
		var bar: ProgressBar = _monster_body_bars[monster]
		if monster.is_alive():
			btn.visible = true
			bar.max_value = maxf(1.0, monster.get_attr(&"MaxBody"))
			bar.value = monster.get_attr(&"Body")
			bar.tooltip_text = "体力 %d / %d" % [int(monster.get_attr(&"Body")), int(monster.get_attr(&"MaxBody"))]
			var selected := _selected_monster == monster
			if selected:
				btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.28, 0.16, 0.16), Color(1, 0.7, 0.3), 2))
			else:
				btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.2, 0.12, 0.14), Color(0.55, 0.3, 0.32)))
			btn.tooltip_text = "%s：位置 %d · 攻击 %d · 防御 %d%s" % [
				monster.display_name, monster.board_index,
				int(monster.get_attr(&"Attack")), int(monster.get_attr(&"Defense")),
				" · 减速" if monster.get_attr(&"Move") <= 0.0 else ""]
		else:
			btn.visible = false

func _build_monster_card(monster: DungeonMonster) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 56)
	btn.pressed.connect(_on_monster_pressed.bind(monster))
	monster_vbox.add_child(btn)
	_monster_buttons[monster] = btn
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 8.0
	hbox.offset_right = -8.0
	hbox.offset_top = 6.0
	hbox.offset_bottom = -6.0
	hbox.add_theme_constant_override("separation", 8)
	btn.add_child(hbox)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_icon(MONSTER_ICONS.get(monster.display_name, "skull-crack"))
	hbox.add_child(icon)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)
	var name_label := Label.new()
	name_label.text = monster.display_name + ("（%d格）" % monster.board_index)
	name_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(name_label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", _make_stylebox(Color(0.6, 0.2, 0.2), Color(0.75, 0.35, 0.3)))
	vbox.add_child(bar)
	_monster_body_bars[monster] = bar
	var status_label := Label.new()
	status_label.name = "Status"
	status_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(status_label)

func _refresh_turn_info() -> void:
	phase_label.text = game.get_phase_name()
	var parts: Array[String] = ["移动 %d 步" % game.moves_left, "行动 %s" % ("已用" if game.action_used else "可用")]
	if _selected_monster and _selected_monster.is_alive():
		parts.append("目标：" + _selected_monster.display_name)
	turn_info_label.text = " · ".join(parts)
	end_turn_button.text = "重新开始 (R)" if game.phase == DungeonGame.Phase.VICTORY or game.phase == DungeonGame.Phase.DEFEAT else "结束回合 (T)"

func _push_log(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > 60:
		_log_lines.pop_front()
	_refresh_log()

func _refresh_log() -> void:
	log_label.text = "\n".join(_log_lines)

func _input(event: InputEvent) -> void:
	if not event.is_pressed() or not game or not game.hero:
		return
	if event is InputEventKey:
		var text := event.as_text()
		match text:
			"A", "Left":
				game.hero_move(-1)
				_refresh_all()
			"D", "Right":
				game.hero_move(1)
				_refresh_all()
			"T":
				game.hero_end_turn()
			"R":
				_hide_overlay()
				_new_game()
			"F":
				await _run_regression()
		for i in HAND_CARDS.size():
			if text == String.num(i + 1):
				_on_hand_card_pressed(HAND_CARDS[i])
				break

func _run_regression() -> void:
	_push_log("=== 自动化回归开始 ===")
	test_runner = DungeonGameTest.new()
	test_runner.name = "TestRunner"
	add_child(test_runner)
	await test_runner.run_all()
	_push_log("=== 回归结束：%s（通过 %d / 失败 %d）===" % ["ALL PASS" if test_runner.is_pass() else "HAS FAILURE", test_runner.get_pass_count(), test_runner.get_fail_count()])
	_clear_cue_markers()
	_refresh_all()
