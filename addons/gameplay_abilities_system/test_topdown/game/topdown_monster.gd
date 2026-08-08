class_name TopdownMonster
extends TopdownEntity

const KIND_COUNT: int = 4

var kind_index: int = 0
var kind_name: String = ""
var ranged: bool = false
var aggro_range: float = 240.0
var attack_range: float = 44.0
var attack_cooldown: float = 1.2
var level: int = 1
var home_pos: Vector2 = Vector2.ZERO

var _attack_timer: float = 0.0

static func get_kind_config(index: int) -> Dictionary:
	match index:
		0:
			return {"index": 0, "name": "哥布林", "ranged": false,
				"hp": 40.0, "attack": 10.0, "defense": 1.0, "speed": 80.0,
				"aggro": 280.0, "range": 46.0, "cd": 1.0}
		1:
			return {"index": 1, "name": "骷髅兵", "ranged": false,
				"hp": 70.0, "attack": 14.0, "defense": 5.0, "speed": 55.0,
				"aggro": 240.0, "range": 46.0, "cd": 1.4}
		2:
			return {"index": 2, "name": "兽人", "ranged": false,
				"hp": 95.0, "attack": 19.0, "defense": 4.0, "speed": 60.0,
				"aggro": 260.0, "range": 50.0, "cd": 1.6}
		3:
			return {"index": 3, "name": "狗头人弓手", "ranged": true,
				"hp": 45.0, "attack": 12.0, "defense": 1.0, "speed": 70.0,
				"aggro": 340.0, "range": 230.0, "cd": 2.2}
	return {}

func setup_monster(cfg: Dictionary, growth: float) -> void:
	kind_index = cfg.index
	kind_name = cfg.name
	ranged = cfg.ranged
	aggro_range = cfg.aggro
	attack_range = cfg.range
	attack_cooldown = cfg.cd
	level = 1
	var hp: float = cfg.hp * growth
	var attrs: Dictionary[StringName, float] = {
		&"Health": hp, &"MaxHealth": hp,
		&"Attack": cfg.attack * growth, &"Defense": cfg.defense * growth,
		&"MoveSpeed": cfg.speed, &"Level": 1.0, &"XP": 0.0,
	}
	setup_entity(cfg.name, attrs)

## 每帧 AI：索敌 → 追击 → 攻击（近战或远程弹道）
func tick(delta: float, game: TopdownGame) -> void:
	_attack_timer -= delta
	var player := game.player
	if not player.is_alive():
		return
	var dist := pos.distance_to(player.pos)
	if dist > aggro_range:
		return
	if ranged:
		if dist <= attack_range:
			_try_ranged_attack(game, player)
		else:
			game.move_entity(self, delta, (player.pos - pos).normalized())
	else:
		if dist <= attack_range + player.RADIUS:
			_try_melee_attack(game, player)
		else:
			game.move_entity(self, delta, (player.pos - pos).normalized())

func _try_melee_attack(game: TopdownGame, player: TopdownPlayer) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	var form := TopdownAttackForm.new()
	form.kind = TopdownAttackForm.Kind.MELEE_ARC
	form.damage_coefficient = 1.0
	game.do_entity_melee_attack(self, form)

func _try_ranged_attack(game: TopdownGame, player: TopdownPlayer) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	game.spawn_monster_projectile(self, (player.pos - pos).normalized())
