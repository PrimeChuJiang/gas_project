extends Node2D

## ---------------- 资源常量 ----------------

const TEX_DIR := "res://assets/dcss_tiles/"
const WORLD_SCALE: float = 2.0

const MONSTER_TEXTURES := {
	0: TEX_DIR + "monsters/goblin.png",
	1: TEX_DIR + "monsters/skeleton.png",
	2: TEX_DIR + "monsters/orc.png",
	3: TEX_DIR + "monsters/kobold.png",
}

const SLOT_LABELS := {
	"weapon": "武器", "armour": "护甲", "ring": "戒指", "boots": "靴子",
}

const WORLD_W: int = 20
const WORLD_H: int = 14

const FORM_COLORS := {
	TopdownAttackForm.Kind.MELEE_ARC: Color(0.9, 0.95, 1.0, 1.0),
	TopdownAttackForm.Kind.PROJECTILE: Color(1.0, 0.9, 0.5, 1.0),
	TopdownAttackForm.Kind.SPREAD: Color(0.7, 0.9, 1.0, 1.0),
	TopdownAttackForm.Kind.PIERCE_BLAST: Color(1.0, 0.75, 0.35, 1.0),
}

## ---------------- 状态 ----------------

var game: TopdownGame
var test_runner: TopdownGameTest

var _floor_sprites: Array[Sprite2D] = []
var _wall_sprites: Array[Sprite2D] = []
var _torch_sprites: Array[Sprite2D] = []
var _torch_lights: Array[PointLight2D] = []
var _entity_sprites: Dictionary = {}  # TopdownEntity -> Sprite2D
var _entity_shadows: Dictionary = {}  # TopdownEntity -> Polygon2D
var _entity_bars: Dictionary = {}     # TopdownEntity -> ColorRect
var _projectile_sprites: Dictionary = {}  # TopdownProjectile -> Sprite2D
var _projectile_trails: Dictionary = {}   # TopdownProjectile -> Array[Sprite2D]
var _flying_texts: Array = []
var _vfx: Array[Dictionary] = []      # 通用临时视觉节点（攻击/爆炸/粒子）
var _hit_anim: Dictionary = {}        # TopdownEntity -> {timer, offset}
var _lunge_anim: Dictionary = {}      # TopdownEntity -> {dir, timer, max}
var _death_anim: Dictionary = {}      # TopdownEntity -> {timer, sprite}
var _game_over_shown: bool = false
var _player_dead_anim: float = -1.0
var _player_dead_offset: float = 0.0

var _anim_time: float = 0.0
var _shake_timer: float = 0.0
var _shake_amount: float = 0.0
var _red_flash_timer: float = 0.0
var _gold_flash_timer: float = 0.0
var _gold_pulse_timer: float = 0.0
var _attack_slant: float = 0.0  # 玩家攻击前倾（scale 压缩）

var _red_overlay: ColorRect
var _gold_overlay: ColorRect
var _sfx: Dictionary = {}
var _sfx_player: AudioStreamPlayer
var _center_banner: Label

const SFX_RATE: int = 22050
var _vfx_layer: Node2D

@onready var world: Node2D = $World
@onready var camera: Camera2D = $Camera2D

var hp_bar: ProgressBar
var xp_bar: ProgressBar
var level_label: Label
var form_label: Label
var stats_label: Label
var log_label: RichTextLabel
var hint_label: Label
var gear_buttons: Dictionary = {}
var _log_lines: Array[String] = []

func _ready() -> void:
	# 相机：地图全览 + 居中 + 随窗口自适应（zoom 上限适配，下限保护避免角色过小）
	_apply_camera_fit()
	get_window().size_changed.connect(_apply_camera_fit)
	_vfx_layer = Node2D.new()
	_vfx_layer.z_index = 60
	add_child(_vfx_layer)
	_build_sfx()
	_build_world_visuals()
	_build_hud()
	game = TopdownGame.new()
	game.name = "Game"
	add_child(game)
	game.start_game()
	_connect_game_signals()
	_sync_all_sprites()
	if "--run-tests" in OS.get_cmdline_user_args():
		_run_regression()
	elif "--ui-check" in OS.get_cmdline_user_args():
		_run_ui_check()

func _apply_camera_fit() -> void:
	var win_size: Vector2 = get_window().size
	var map_size := Vector2(WORLD_W * 32.0 * WORLD_SCALE, WORLD_H * 32.0 * WORLD_SCALE)
	var fit := minf(win_size.x / map_size.x, win_size.y / map_size.y)
	camera.zoom = Vector2.ONE * maxf(fit, 0.5)
	camera.position = map_size * 0.5

## ---------------- 程序化音效（无外部素材，纯合成） ----------------

func _build_sfx() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.volume_db = -8.0
	add_child(_sfx_player)
	_sfx["slash"] = _make_noise_burst(0.12, 0.9, 600.0, 200.0)
	_sfx["shoot"] = _make_chirp(700.0, 1500.0, 0.1, 0.6)
	_sfx["hit"] = _make_tone(150.0, 0.09, 0.7, true)
	_sfx["hurt"] = _make_tone(110.0, 0.16, 0.8, true)
	_sfx["explode"] = _make_noise_burst(0.35, 1.0, 240.0, 90.0)
	_sfx["death"] = _make_tone(95.0, 0.28, 0.75, true)
	_sfx["levelup"] = _make_arpeggio([523.0, 659.0, 784.0, 1047.0], 0.09)
	_sfx["chest"] = _make_arpeggio([880.0, 1175.0], 0.05)
	_sfx["gameover"] = _make_tone(70.0, 0.9, 0.8, true)

func _make_noise_burst(duration: float, volume: float, cutoff_hz: float, decay_hz: float) -> AudioStreamWAV:
	var n := int(duration * SFX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		phase += TAU * (cutoff_hz - decay_hz * float(i) / n) / SFX_RATE
		phase = fmod(phase, TAU)
		var noise := randf_range(-1.0, 1.0)
		var env := 1.0 - float(i) / n
		samples[i] = (noise * 0.6 + sin(phase) * 0.4) * env * env * volume
	return _samples_to_wav(samples)

func _make_tone(freq: float, duration: float, volume: float, square: bool) -> AudioStreamWAV:
	var n := int(duration * SFX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		phase += TAU * freq * (1.0 - 0.25 * float(i) / n) / SFX_RATE
		phase = fmod(phase, TAU)
		var wave := sin(phase)
		if square:
			wave = 1.0 if sin(phase) > 0.0 else -1.0
		var env := 1.0 - float(i) / n
		samples[i] = wave * env * env * volume
	return _samples_to_wav(samples)

func _make_chirp(freq_from: float, freq_to: float, duration: float, volume: float) -> AudioStreamWAV:
	var n := int(duration * SFX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var f := lerpf(freq_from, freq_to, float(i) / n)
		phase += TAU * f / SFX_RATE
		phase = fmod(phase, TAU)
		var env := 1.0 - float(i) / n
		samples[i] = sin(phase) * env * env * volume
	return _samples_to_wav(samples)

func _make_arpeggio(freqs: Array, note_dur: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for freq in freqs:
		var n := int(note_dur * SFX_RATE)
		var phase := 0.0
		for i in n:
			phase += TAU * freq / SFX_RATE
			phase = fmod(phase, TAU)
			var env := 1.0 - float(i) / n
			samples.append(sin(phase) * env * env * 0.7)
	return _samples_to_wav(samples)

func _samples_to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SFX_RATE
	stream.stereo = false
	var data := PackedByteArray()
	for s in samples:
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data.append(v & 0xFF)
		data.append((v >> 8) & 0xFF)
	stream.data = data
	return stream

func _play_sfx(key: String, volume_db: float = 0.0) -> void:
	if not _sfx.has(key):
		return
	var player := AudioStreamPlayer.new()
	player.stream = _sfx[key]
	player.volume_db = -8.0 + volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

## ---------------- 世界渲染 ----------------

func _build_world_visuals() -> void:
	var floor_variants := [_load_tex("dungeon/floor0.png"), _load_tex("dungeon/floor1.png"),
		_load_tex("dungeon/floor2.png"), _load_tex("dungeon/floor3.png")]
	var wall_variants := [_load_tex("dungeon/wall0.png"), _load_tex("dungeon/wall1.png"),
		_load_tex("dungeon/wall2.png"), _load_tex("dungeon/wall3.png")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in TopdownGame.MAP.size():
		var row: String = TopdownGame.MAP[y]
		for x in row.length():
			var c: String = row[x]
			if c == "#":
				_wall_sprites.append(_make_sprite(wall_variants[rng.randi_range(0, wall_variants.size() - 1)], x, y))
			else:
				_floor_sprites.append(_make_sprite(floor_variants[rng.randi_range(0, floor_variants.size() - 1)], x, y))
	var torch_tiles := [Vector2i(5, 1), Vector2i(14, 1), Vector2i(5, 12), Vector2i(11, 12),
		Vector2i(10, 3), Vector2i(10, 10)]
	for tile in torch_tiles:
		var sprite := _make_sprite(_load_tex("dungeon/torch0.png"), tile.x, tile.y)
		sprite.z_index = 5
		_torch_sprites.append(sprite)
		var light := PointLight2D.new()
		light.position = Vector2(tile.x * 64 + 32, tile.y * 64 + 32)
		light.energy = 0.9
		light.texture_scale = 2.2
		world.add_child(light)
		_torch_lights.append(light)
	var blood := _load_tex("effects/blood.png")
	var blood_spots := [Vector2i(3, 4), Vector2i(15, 8), Vector2i(7, 6), Vector2i(12, 11)]
	for spot in blood_spots:
		var sprite := _make_sprite(blood, spot.x, spot.y)
		sprite.modulate.a = 0.55
		sprite.z_index = 2

func _load_tex(rel_path: String) -> Texture2D:
	return load(TEX_DIR + rel_path)

func _make_sprite(tex: Texture2D, tile_x: int, tile_y: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2.ONE * WORLD_SCALE
	sprite.position = Vector2(tile_x * 64 + 32, tile_y * 64 + 32)
	world.add_child(sprite)
	return sprite

func _world_pos(entity: TopdownEntity) -> Vector2:
	return entity.pos * WORLD_SCALE

func _build_player_light() -> void:
	var light := PointLight2D.new()
	light.name = "PlayerLight"
	light.energy = 1.15
	light.texture_scale = 3.0
	world.add_child(light)

## ---------------- 实体渲染 ----------------

func _sync_all_sprites() -> void:
	for monster in game.monsters:
		_ensure_entity_sprite(monster)
	_ensure_entity_sprite(game.player)
	for chest in game.chests:
		_ensure_entity_sprite(chest)

func _make_shadow(parent: Node2D) -> Polygon2D:
	var shadow := Polygon2D.new()
	shadow.color = Color(0, 0, 0, 0.35)
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * float(i) / 18.0
		pts.append(Vector2(cos(a) * 22.0, sin(a) * 7.0))
	shadow.polygon = pts
	shadow.position = Vector2(0, 16)
	shadow.z_index = -1
	parent.add_child(shadow)
	return shadow

func _ensure_entity_sprite(entity: TopdownEntity) -> Sprite2D:
	if _entity_sprites.has(entity):
		return _entity_sprites[entity]
	var sprite := Sprite2D.new()
	var tex_path := ""
	if entity is TopdownPlayer:
		tex_path = TEX_DIR + "player/hero.png"
		sprite.z_index = 20
	elif entity is TopdownMonster:
		tex_path = MONSTER_TEXTURES[entity.kind_index]
		sprite.z_index = 10
	elif entity is TopdownChest:
		tex_path = TEX_DIR + "items/chest.png"
		sprite.z_index = 15
	sprite.texture = load(tex_path)
	sprite.scale = Vector2.ONE * WORLD_SCALE
	world.add_child(sprite)
	_entity_sprites[entity] = sprite
	_entity_shadows[entity] = _make_shadow(sprite)
	if entity is TopdownMonster:
		var bar := ColorRect.new()
		bar.size = Vector2(48, 5)
		bar.position = Vector2(-24, -44)
		bar.color = Color(0.8, 0.2, 0.2, 0.9)
		sprite.add_child(bar)
		_entity_bars[entity] = bar
	if entity is TopdownPlayer:
		_build_player_light()
		entity.health_changed.connect(_on_entity_health_changed.bind(entity))
	if entity is TopdownMonster:
		entity.health_changed.connect(_on_entity_health_changed.bind(entity))
	return sprite

func _remove_entity_sprite(entity: TopdownEntity) -> void:
	if _entity_sprites.has(entity):
		_entity_sprites[entity].queue_free()
		_entity_sprites.erase(entity)
	_entity_bars.erase(entity)
	_entity_shadows.erase(entity)

## 实体已被逻辑层释放（freed）时的清理：按引用 key 清表现层账本，不传类型化参数
func _purge_entity_sprites(entity_key: Variant) -> void:
	if _entity_sprites.has(entity_key):
		_entity_sprites[entity_key].queue_free()
		_entity_sprites.erase(entity_key)
	_entity_bars.erase(entity_key)
	_entity_shadows.erase(entity_key)
	_hit_anim.erase(entity_key)
	_lunge_anim.erase(entity_key)

func _on_entity_health_changed(current: float, max_value: float, entity: TopdownEntity) -> void:
	if _entity_bars.has(entity):
		var bar: ColorRect = _entity_bars[entity]
		bar.size.x = 48.0 * clampf(current / max_value, 0.0, 1.0)
	if current <= 0.0:
		_start_death_anim(entity)
	elif _entity_sprites.has(entity):
		_start_hit_anim(entity)

## ---------------- HUD ----------------

func _make_panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	style.bg_color = bg
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	return style

func _make_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := _make_panel_style(bg, border)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style

func _build_hud() -> void:
	var root: Control = $CanvasLayer/Root
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 10.0
	margin.offset_top = 8.0
	margin.offset_right = -10.0
	margin.offset_bottom = -8.0
	root.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	vbox.add_child(top_bar)

	var hero_panel := PanelContainer.new()
	hero_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.1, 0.12, 0.16, 0.95), Color(0.3, 0.35, 0.45, 1)))
	top_bar.add_child(hero_panel)
	var hero_vbox := VBoxContainer.new()
	hero_vbox.add_theme_constant_override("separation", 4)
	hero_panel.add_child(hero_vbox)

	var name_row := HBoxContainer.new()
	hero_vbox.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "勇者"
	name_label.add_theme_font_size_override("font_size", 17)
	name_row.add_child(name_label)
	level_label = Label.new()
	level_label.text = "Lv.1"
	level_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.3, 1))
	level_label.add_theme_font_size_override("font_size", 15)
	name_row.add_child(level_label)
	form_label = Label.new()
	form_label.text = "形态：斩击"
	form_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.95, 1))
	form_label.add_theme_font_size_override("font_size", 13)
	name_row.add_child(form_label)

	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(220, 14)
	hp_bar.show_percentage = false
	hp_bar.max_value = 1.0
	hp_bar.value = 1.0
	hp_bar.add_theme_stylebox_override("fill", _make_panel_style(Color(0.75, 0.2, 0.2, 1), Color(0, 0, 0, 0)))
	hero_vbox.add_child(hp_bar)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(220, 8)
	xp_bar.show_percentage = false
	xp_bar.max_value = 1.0
	xp_bar.value = 0.0
	xp_bar.add_theme_stylebox_override("fill", _make_panel_style(Color(0.35, 0.45, 0.85, 1), Color(0, 0, 0, 0)))
	hero_vbox.add_child(xp_bar)

	stats_label = Label.new()
	stats_label.text = ""
	stats_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 1))
	stats_label.add_theme_font_size_override("font_size", 12)
	hero_vbox.add_child(stats_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var gear_row := HBoxContainer.new()
	gear_row.add_theme_constant_override("separation", 6)
	top_bar.add_child(gear_row)
	for slot in TopdownPlayer.ALL_SLOTS:
		var button := Button.new()
		button.text = "%s：空" % SLOT_LABELS[slot]
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_stylebox_override("normal", _make_button_style(Color(0.2, 0.24, 0.3, 0.95), Color(0.5, 0.58, 0.7, 1)))
		button.add_theme_stylebox_override("hover", _make_button_style(Color(0.28, 0.34, 0.42, 0.95), Color(0.7, 0.8, 0.95, 1)))
		button.pressed.connect(_on_gear_button.bind(slot))
		gear_row.add_child(button)
		gear_buttons[slot] = button

	var mid_spacer := Control.new()
	mid_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(mid_spacer)

	var log_panel := PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.09, 0.1, 0.13, 0.95), Color(0.28, 0.32, 0.38, 1)))
	vbox.add_child(log_panel)
	log_label = RichTextLabel.new()
	log_label.custom_minimum_size = Vector2(0, 96)
	log_label.bbcode_enabled = true
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_panel.add_child(log_label)

	hint_label = Label.new()
	hint_label.text = "WASD 移动 · 空格/左键 攻击 · E 开箱 · R 重开（攻击形态随等级进化）"
	hint_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68, 1))
	hint_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint_label)

	_red_overlay = ColorRect.new()
	_red_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_red_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_red_overlay.color = Color(0.8, 0.1, 0.08, 0)
	root.add_child(_red_overlay)
	_gold_overlay = ColorRect.new()
	_gold_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gold_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_overlay.color = Color(1.0, 0.9, 0.5, 0)
	root.add_child(_gold_overlay)
	_center_banner = Label.new()
	_center_banner.set_anchors_preset(Control.PRESET_CENTER)
	_center_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center_banner.text = ""
	_center_banner.add_theme_font_size_override("font_size", 30)
	_center_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0))
	_center_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_center_banner.add_theme_constant_override("outline_size", 8)
	_center_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_center_banner)

func _on_gear_button(slot: String) -> void:
	if not game or not game.player:
		return
	game.player.unequip_gear(slot)

## ---------------- 信号桥 ----------------

func _connect_game_signals() -> void:
	game.message.connect(_on_message)
	game.damage_applied.connect(_on_damage_applied)
	game.attack_performed.connect(_on_attack_performed)
	game.projectile_hit.connect(_on_projectile_hit)
	game.blast_effect.connect(_on_blast_effect)
	game.player_leveled_up.connect(_on_leveled_up)
	game.monster_died.connect(_on_monster_died)
	game.monster_respawned.connect(_on_monster_respawned)
	game.chest_opened.connect(_on_chest_opened)
	game.game_over.connect(_on_game_over)
	game.player.gear_changed.connect(_on_gear_changed)

func _on_message(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > 6:
		_log_lines.pop_front()
	log_label.clear()
	log_label.push_color(Color(0.75, 0.8, 0.88, 1))
	log_label.append_text("\n".join(_log_lines))
	log_label.pop()

func _on_damage_applied(source_name: String, target_name: String, amount: float, target: TopdownEntity, source: TopdownEntity) -> void:
	_spawn_flying_text(target, "-%d" % int(round(amount)), Color(1.0, 0.55, 0.35, 1))
	if target == game.player:
		_shake_camera(5.0, 0.25)
		_red_flash_timer = 0.25
		_play_sfx("hurt", 2.0)
		_spawn_hit_spark(_world_pos(target), Color(0.9, 0.3, 0.25, 1))
	elif source == game.player:
		_play_sfx("hit")
		_spawn_hit_spark(_world_pos(target), Color(1.0, 0.85, 0.4, 1))
	if source is TopdownMonster and target == game.player:
		_lunge_entity(source, 10.0)

func _on_attack_performed(form: TopdownAttackForm, from: TopdownEntity) -> void:
	var pos := _world_pos(from)
	var dir: Vector2 = from.facing if from is TopdownPlayer else (game.player.pos - from.pos).normalized()
	var color: Color = FORM_COLORS.get(form.kind, Color.WHITE)
	if form.kind == TopdownAttackForm.Kind.MELEE_ARC:
		_spawn_slash(pos, dir, form.range, color)
		_play_sfx("slash")
	else:
		_spawn_muzzle_flash(pos + dir * 36.0, dir, color)
		_play_sfx("shoot")
	if from == game.player:
		_attack_slant = 0.18

func _on_projectile_hit(pos: Vector2) -> void:
	_spawn_hit_spark(pos * WORLD_SCALE, Color(1.0, 0.9, 0.5, 1))

func _on_blast_effect(pos: Vector2, radius: float) -> void:
	_spawn_blast(pos * WORLD_SCALE, radius * WORLD_SCALE)
	_play_sfx("explode")
	_shake_camera(7.0, 0.3)

func _on_leveled_up(level: int) -> void:
	level_label.text = "Lv.%d" % level
	form_label.text = "形态：%s" % game.get_current_attack_form().form_name
	_spawn_flying_text(game.player, "升级！Lv.%d" % level, Color(1.0, 0.85, 0.3, 1))
	_show_center_banner("升级！ Lv.%d —— 攻击形态进化！" % level)
	_play_sfx("levelup")
	_gold_flash_timer = 0.5
	_gold_pulse_timer = 0.6
	if _entity_sprites.has(game.player):
		_entity_sprites[game.player].modulate = Color(1.6, 1.4, 0.8, 1.0)

func _on_monster_died(monster: TopdownMonster) -> void:
	pass

func _on_monster_respawned(monster: TopdownMonster) -> void:
	_ensure_entity_sprite(monster)
	_on_entity_health_changed(monster.get_attr(&"Health"), monster.get_attr(&"MaxHealth"), monster)
	var sprite: Sprite2D = _entity_sprites[monster]
	sprite.modulate = Color(0.4, 0.4, 0.4, 0.0)
	sprite.scale = Vector2(0.3, 0.3) * WORLD_SCALE
	_vfx.append({"kind": "respawn", "sprite": sprite, "life": 0.5, "max": 0.5})

func _on_chest_opened(chest: TopdownChest, loot_name: String) -> void:
	if _entity_sprites.has(chest):
		_entity_sprites[chest].texture = load(TEX_DIR + "items/gold.png")
	_spawn_flying_text(chest, loot_name, Color(0.95, 0.85, 0.4, 1))
	_spawn_hit_spark(_world_pos(chest) + Vector2(0, -16), Color(0.95, 0.85, 0.4, 1))
	_play_sfx("chest")

func _on_gear_changed(slot: String, gear_name: String) -> void:
	if gear_buttons.has(slot):
		gear_buttons[slot].text = "%s：%s" % [SLOT_LABELS[slot], gear_name if gear_name != "" else "空"]

func _on_game_over() -> void:
	_game_over_shown = true
	_player_dead_anim = 0.0
	_red_flash_timer = 0.5
	_shake_camera(8.0, 0.4)
	_play_sfx("gameover")
	_on_message("[color=#ff7777]你倒下了……按 R 重开[/color]")

func _show_center_banner(text: String) -> void:
	_center_banner.text = text
	_center_banner.modulate.a = 1.0
	_vfx.append({"kind": "banner", "node": _center_banner, "life": 1.4, "max": 1.4})

func _spawn_flying_text(entity: TopdownEntity, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 50
	_vfx_layer.add_child(label)
	label.position = _world_pos(entity) + Vector2(-20, -40)
	_flying_texts.append({"label": label, "life": 0.9, "max": 0.9})

## ---------------- 攻击动画（斩击弧光 / 枪口闪光 / 爆炸 / 火花） ----------------

func _build_arc_points(radius: float, half_angle: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in segments + 1:
		var a := lerpf(-half_angle, half_angle, float(i) / float(segments))
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

func _spawn_slash(pos: Vector2, dir: Vector2, range_px: float, color: Color) -> void:
	var node := Node2D.new()
	node.position = pos
	node.rotation = dir.angle() - 0.35
	node.z_index = 40
	var fill := Polygon2D.new()
	fill.polygon = _build_arc_points(range_px * WORLD_SCALE, 0.61, 10)
	fill.color = Color(color.r, color.g, color.b, 0.45)
	node.add_child(fill)
	var edge := Line2D.new()
	edge.points = _build_arc_points(range_px * WORLD_SCALE, 0.61, 10)
	edge.width = 4.0
	edge.default_color = Color(color.r, color.g, color.b, 0.95)
	node.add_child(edge)
	var tip := Sprite2D.new()
	tip.texture = _load_tex("effects/cloud_magic_trail0.png")
	tip.position = Vector2(range_px * WORLD_SCALE * 0.55, 0)
	tip.scale = Vector2.ONE * 1.2
	tip.modulate = Color(color.r, color.g, color.b, 0.9)
	node.add_child(tip)
	_vfx_layer.add_child(node)
	_vfx.append({"kind": "slash", "node": node, "edge": edge, "fill": fill, "tip": tip,
		"from": dir.angle() - 0.35, "to": dir.angle() + 0.35, "life": 0.18, "max": 0.18})

func _spawn_muzzle_flash(pos: Vector2, dir: Vector2, color: Color) -> void:
	var ring := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * float(i) / 14.0
		pts.append(Vector2(cos(a), sin(a)) * 14.0)
	ring.polygon = pts
	ring.color = Color(color.r, color.g, color.b, 0.8)
	ring.position = pos
	ring.z_index = 40
	_vfx_layer.add_child(ring)
	_vfx.append({"kind": "muzzle", "node": ring, "life": 0.16, "max": 0.16})

func _spawn_hit_spark(pos: Vector2, color: Color) -> void:
	var node := Node2D.new()
	node.position = pos
	node.z_index = 45
	for i in 5:
		var part := Polygon2D.new()
		var a := TAU * float(i) / 5.0 + 0.4
		part.polygon = PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(0, 5)])
		part.color = color
		part.rotation = a
		node.add_child(part)
	_vfx_layer.add_child(node)
	_vfx.append({"kind": "spark", "node": node, "life": 0.3, "max": 0.3})

func _spawn_blast(pos: Vector2, radius: float) -> void:
	var node := Node2D.new()
	node.position = pos
	node.z_index = 45
	var fire := Sprite2D.new()
	fire.texture = _load_tex("effects/fireball.png")
	fire.scale = Vector2.ONE * 1.6
	node.add_child(fire)
	var cloud := Sprite2D.new()
	cloud.texture = _load_tex("effects/cloud_fire0.png")
	cloud.scale = Vector2.ONE * 2.0
	cloud.position = Vector2(0, -12)
	cloud.modulate = Color(1.0, 0.7, 0.4, 0.85)
	node.add_child(cloud)
	var ring := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * float(i) / 18.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	ring.polygon = pts
	ring.color = Color(1.0, 0.75, 0.35, 0.5)
	node.add_child(ring)
	_vfx_layer.add_child(node)
	_vfx.append({"kind": "blast", "node": node, "ring": ring, "fire": fire, "cloud": cloud,
		"life": 0.4, "max": 0.4})

func _spawn_death_burst(pos: Vector2, color: Color) -> void:
	var node := Node2D.new()
	node.position = pos
	node.z_index = 45
	for i in 7:
		var part := Polygon2D.new()
		part.polygon = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(0, 6)])
		part.color = color
		part.rotation = randf() * TAU
		node.add_child(part)
	_vfx_layer.add_child(node)
	_vfx.append({"kind": "death", "node": node, "life": 0.55, "max": 0.55})

## ---------------- 受击 / 前扑 / 死亡动画 ----------------

func _start_hit_anim(entity: TopdownEntity) -> void:
	if not _entity_sprites.has(entity) or _death_anim.has(entity):
		return
	_hit_anim[entity] = {"timer": 0.22}
	_entity_sprites[entity].modulate = Color(1.0, 0.45, 0.45, 1.0)

func _lunge_entity(entity: TopdownEntity, distance: float) -> void:
	if not _entity_sprites.has(entity):
		return
	var dir := (game.player.pos - entity.pos).normalized()
	_lunge_anim[entity] = {"dir": dir * distance * WORLD_SCALE, "timer": 0.16, "max": 0.16}

func _start_death_anim(entity: TopdownEntity) -> void:
	if not _entity_sprites.has(entity):
		return
	_death_anim[entity] = {"timer": 0.35, "sprite": _entity_sprites[entity]}
	_hit_anim.erase(entity)
	_spawn_death_burst(_world_pos(entity), Color(0.55, 0.15, 0.12, 1))
	if entity is TopdownMonster:
		_play_sfx("death")

## ---------------- 每帧驱动 ----------------

func _process(delta: float) -> void:
	_anim_time += delta
	_tick_overlays(delta)
	_tick_vfx(delta)
	_tick_lunge_anims(delta)
	_tick_death_anims(delta)
	_tick_hit_anims(delta)
	_tick_torches()
	if not game:
		return
	if _game_over_shown:
		_tick_player_death_anim(delta)
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	game.player.move_input = input_dir
	_update_player_facing()
	if Input.is_action_just_pressed("attack"):
		game.player.try_attack()
	if Input.is_action_just_pressed("interact"):
		game.try_interact()
	_sync_rendering(delta)

## 攻击朝向跟随鼠标（世界坐标），鼠标未动时退回移动方向
func _update_player_facing() -> void:
	var mouse_world := get_global_mouse_position()
	var to_mouse := mouse_world - _world_pos(game.player)
	if to_mouse.length() > 12.0:
		game.player.facing = to_mouse.normalized()
	elif game.player.move_input.length_squared() > 0.0:
		game.player.facing = game.player.move_input.normalized()

func _tick_overlays(delta: float) -> void:
	if _red_flash_timer > 0.0:
		_red_flash_timer -= delta
	_red_overlay.color.a = clampf(_red_flash_timer * 1.8, 0.0, 0.45)
	if _gold_flash_timer > 0.0:
		_gold_flash_timer -= delta
	_gold_overlay.color.a = clampf(_gold_flash_timer / 0.5, 0.0, 1.0) * 0.4
	if _gold_pulse_timer > 0.0:
		_gold_pulse_timer -= delta
		if _gold_pulse_timer <= 0.0 and _entity_sprites.has(game.player):
			_entity_sprites[game.player].modulate = Color(1, 1, 1, 1)
	if _shake_timer > 0.0:
		_shake_timer -= delta
		camera.offset = Vector2(randf_range(-_shake_amount, _shake_amount), randf_range(-_shake_amount, _shake_amount))
	else:
		camera.offset = Vector2.ZERO
	if _attack_slant > 0.0:
		_attack_slant -= delta

func _shake_camera(amount: float, duration: float) -> void:
	_shake_amount = amount
	_shake_timer = maxf(_shake_timer, duration)

func _tick_vfx(delta: float) -> void:
	for i in range(_vfx.size() - 1, -1, -1):
		var v: Dictionary = _vfx[i]
		v.life -= delta
		var t: float = clampf(v.life / v.max, 0.0, 1.0)
		match v.kind:
			"slash":
				var node: Node2D = v.node
				node.rotation = lerpf(v.from, v.to, 1.0 - t)
				node.scale = Vector2.ONE * lerpf(1.2, 0.75, t)
				var edge: Line2D = v.edge
				edge.default_color.a = t
				var fill: Polygon2D = v.fill
				fill.color.a = t * 0.45
				var tip: Sprite2D = v.tip
				tip.modulate.a = t
				tip.rotation += delta * 6.0
			"muzzle":
				var ring: Polygon2D = v.node
				ring.scale = Vector2.ONE * lerpf(0.4, 2.4, 1.0 - t)
				ring.color.a = t
			"spark":
				var node2: Node2D = v.node
				node2.rotation += delta * 8.0
				for part in node2.get_children():
					var p := part as Polygon2D
					p.position += Vector2.from_angle(p.rotation) * 90.0 * delta
					p.modulate.a = t
			"blast":
				var node3: Node2D = v.node
				node3.scale = Vector2.ONE * lerpf(0.7, 2.2, 1.0 - t)
				var ring2: Polygon2D = v.ring
				ring2.color.a = t * 0.55
				var fire: Sprite2D = v.fire
				fire.modulate.a = t
				var cloud: Sprite2D = v.cloud
				cloud.modulate.a = t * 0.8
				cloud.texture = _load_tex("effects/cloud_fire%d.png" % (int((1.0 - t) * 3.0) % 3))
			"death":
				var node4: Node2D = v.node
				for part in node4.get_children():
					var p := part as Polygon2D
					p.position += Vector2.from_angle(p.rotation) * 60.0 * delta
					p.position.y += 40.0 * delta
					p.modulate.a = t
					p.rotation += delta * 3.0
			"respawn":
				var rsprite: Sprite2D = v.sprite
				rsprite.modulate = Color(1.0, 1.0, 1.0, 1.0 - t)
				rsprite.scale = Vector2.ONE * lerpf(1.0, 0.3, t) * WORLD_SCALE
			"banner":
				var banner: Label = v.node
				if t > 0.6:
					banner.modulate.a = 1.0
				else:
					banner.modulate.a = clampf(t / 0.6, 0.0, 1.0)
				banner.position.y = lerpf(0.0, -40.0, 1.0 - t)
		if v.life <= 0.0:
			if v.kind == "banner":
				var banner: Label = v.node
				banner.modulate.a = 0.0
				_vfx.remove_at(i)
			elif v.kind == "respawn":
				# respawn 的 sprite 由实体渲染系统管理（_entity_sprites），此处只摘条目不删节点
				_vfx.remove_at(i)
			else:
				v.node.queue_free()
				_vfx.remove_at(i)
	for i in range(_flying_texts.size() - 1, -1, -1):
		var entry: Dictionary = _flying_texts[i]
		entry.life -= delta
		var label: Label = entry.label
		label.position.y -= 26.0 * delta
		label.modulate.a = clampf(entry.life / entry.max, 0.0, 1.0)
		if entry.life <= 0.0:
			label.queue_free()
			_flying_texts.remove_at(i)

func _tick_lunge_anims(delta: float) -> void:
	for entity in _lunge_anim.keys():
		var entry: Dictionary = _lunge_anim[entity]
		entry.timer -= delta
		if entry.timer <= 0.0:
			_lunge_anim.erase(entity)

func _tick_death_anims(delta: float) -> void:
	for entity in _death_anim.keys():
		var entry: Dictionary = _death_anim[entity]
		entry.timer -= delta
		var t: float = clampf(entry.timer / 0.35, 0.0, 1.0)
		var sprite: Sprite2D = entry.sprite
		sprite.scale = Vector2.ONE * lerpf(0.15, 1.0, t) * WORLD_SCALE
		sprite.modulate.a = t
		if entry.timer <= 0.0:
			if is_instance_valid(entity):
				_remove_entity_sprite(entity)
			else:
				_purge_entity_sprites(entity)
			_death_anim.erase(entity)

func _tick_hit_anims(delta: float) -> void:
	for entity in _hit_anim.keys():
		var entry: Dictionary = _hit_anim[entity]
		entry.timer -= delta
		var sprite: Sprite2D = _entity_sprites.get(entity)
		if not sprite:
			_hit_anim.erase(entity)
			continue
		sprite.offset = Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		if entry.timer <= 0.0:
			sprite.offset = Vector2.ZERO
			sprite.modulate = Color(1, 1, 1, 1)
			_hit_anim.erase(entity)

func _tick_torches() -> void:
	var frame := int(_anim_time * 4.0) % 2
	for i in _torch_sprites.size():
		_torch_sprites[i].texture = _load_tex("dungeon/torch%d.png" % frame)
		if i < _torch_lights.size():
			_torch_lights[i].energy = 0.8 + sin(_anim_time * 7.0 + float(i)) * 0.18 + sin(_anim_time * 23.0 + float(i) * 2.0) * 0.07

func _tick_player_death_anim(delta: float) -> void:
	if _player_dead_anim < 0.0:
		return
	_player_dead_anim += delta
	if _entity_sprites.has(game.player):
		var sprite: Sprite2D = _entity_sprites[game.player]
		sprite.rotation = lerpf(0.0, 1.57, clampf(_player_dead_anim / 0.5, 0.0, 1.0))
		_player_dead_offset += 30.0 * delta
		sprite.offset = Vector2(0, _player_dead_offset)
		sprite.modulate.a = clampf(1.0 - (_player_dead_anim - 0.5) / 0.3, 0.0, 1.0)
		sprite.scale = Vector2.ONE * (1.0 + _player_dead_anim * 0.1) * WORLD_SCALE
	else:
		_sync_all_sprites()

func _sync_rendering(delta: float) -> void:
	_sync_world_sprites(delta, _entity_sprites.keys())
	_sync_projectiles()
	_update_hud()

func _sync_world_sprites(delta: float, entities: Array) -> void:
	for entity in entities:
		var sprite: Sprite2D = _entity_sprites.get(entity)
		if not sprite:
			continue
		if not is_instance_valid(entity):
			if not _death_anim.has(entity):
				_purge_entity_sprites(entity)
			continue
		sprite.position = _world_pos(entity)
		if _lunge_anim.has(entity):
			var entry: Dictionary = _lunge_anim[entity]
			var t: float = entry.timer / entry.max
			sprite.position += entry.dir * t
		if entity is TopdownPlayer:
			var hero := entity as TopdownPlayer
			sprite.flip_h = hero.facing.x < 0.0
			if hero.facing.length() > 0.1 and _attack_slant <= 0.0:
				sprite.position.y += sin(_anim_time * 12.0) * 2.0
			if _attack_slant > 0.0:
				var p := _attack_slant / 0.18
				sprite.scale = Vector2.ONE * WORLD_SCALE
				sprite.scale.x *= 1.0 + p * 0.2
				sprite.scale.y *= 1.0 - p * 0.25
			else:
				sprite.scale = Vector2.ONE * WORLD_SCALE
			var light := world.get_node_or_null("PlayerLight")
			if light:
				light.position = _world_pos(hero)
				light.energy = 1.15 + sin(_anim_time * 5.0) * 0.08
		elif entity is TopdownMonster and entity.is_alive():
			var monster := entity as TopdownMonster
			sprite.flip_h = (monster.pos - game.player.pos).x < 0.0 if game.player.is_alive() else false
			if not _hit_anim.has(entity) and not _lunge_anim.has(entity):
				sprite.position.y += sin(_anim_time * 10.0) * 1.5

func _sync_projectiles() -> void:
	for p in _projectile_sprites.keys():
		if not game.projectiles.has(p):
			_projectile_sprites[p].queue_free()
			_projectile_sprites.erase(p)
			if _projectile_trails.has(p):
				for trail in _projectile_trails[p]:
					trail.queue_free()
				_projectile_trails.erase(p)
	for p in game.projectiles:
		if not _projectile_sprites.has(p):
			var sprite := Sprite2D.new()
			sprite.texture = load(TEX_DIR + "effects/magic_dart.png")
			sprite.scale = Vector2.ONE * WORLD_SCALE * 0.8
			sprite.modulate = Color(1.6, 1.4, 0.8, 1.0)
			sprite.z_index = 30
			world.add_child(sprite)
			_projectile_sprites[p] = sprite
			_projectile_trails[p] = []
		var sprite: Sprite2D = _projectile_sprites[p]
		sprite.position = p.pos * WORLD_SCALE
		sprite.rotation = p.dir.angle()
		sprite.texture = load(TEX_DIR + ("effects/bolt1.png" if int(_anim_time * 16.0) % 2 == 0 else "effects/bolt0.png"))
		sprite.scale = Vector2.ONE * (0.9 + sin(_anim_time * 30.0) * 0.15) * WORLD_SCALE
		_spawn_projectile_trail(p)

func _spawn_projectile_trail(p: TopdownProjectile) -> void:
	var trails: Array = _projectile_trails[p]
	if trails.size() > 0 and trails.back().position.distance_to(p.pos * WORLD_SCALE) < 10.0:
		return
	var trail := Sprite2D.new()
	trail.texture = _load_tex("effects/cloud_magic_trail%d.png" % (int(_anim_time * 8.0) % 4))
	trail.position = p.pos * WORLD_SCALE
	trail.scale = Vector2.ONE * (0.7 + randf() * 0.4) * WORLD_SCALE
	trail.modulate = Color(1.0, 0.9, 0.6, 0.7)
	trail.z_index = 28
	world.add_child(trail)
	trails.append(trail)
	if trails.size() > 4:
		trails.pop_front().queue_free()

func _update_hud() -> void:
	if not game or not game.player:
		return
	var player := game.player
	var max_hp := player.get_attr(&"MaxHealth")
	hp_bar.max_value = max_hp
	hp_bar.value = player.get_attr(&"Health")
	var xp_max := player.xp_to_next()
	xp_bar.max_value = xp_max
	xp_bar.value = player.get_xp()
	level_label.text = "Lv.%d" % player.get_level()
	form_label.text = "形态：%s" % game.get_current_attack_form().form_name
	stats_label.text = "攻击 %d · 防御 %d · 移速 %d · 经验 %d/%d · 怪物 %d 只" % [
		int(player.get_attr(&"Attack")), int(player.get_attr(&"Defense")),
		int(player.get_attr(&"MoveSpeed")), int(player.get_xp()), int(xp_max),
		game.monsters.size()]
	for slot in TopdownPlayer.ALL_SLOTS:
		if gear_buttons.has(slot):
			var gear_name := player.get_gear_name(slot)
			gear_buttons[slot].text = "%s：%s" % [SLOT_LABELS[slot], gear_name if gear_name != "" else "空"]

## ---------------- 回归 / UI 检查 ----------------

func _run_regression() -> void:
	test_runner = TopdownGameTest.new()
	test_runner.name = "TestRunner"
	add_child(test_runner)
	await test_runner.run_all()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if test_runner.is_pass() else 1)

func _run_ui_check() -> void:
	get_window().size = Vector2i(1152, 648)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp_size := get_window().size
	print("UI_CHECK window=", vp_size)
	var root: Control = $CanvasLayer/Root
	var issues := 0
	var controls := root.find_children("*", "Control", true, false)
	for node in controls:
		var c := node as Control
		var rect := c.get_global_rect()
		if rect.position.x < -1.0 or rect.position.y < -1.0 or rect.end.x > vp_size.x + 1.0 or rect.end.y > vp_size.y + 1.0:
			print("UI_CHECK OVERFLOW: ", node.get_path(), " rect=", rect)
			issues += 1
	print("UI_CHECK issues=", issues)
	get_tree().quit(0 if issues == 0 else 1)
