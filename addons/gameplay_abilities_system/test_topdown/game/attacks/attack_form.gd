class_name TopdownAttackForm
extends Resource

enum Kind { MELEE_ARC, PROJECTILE, SPREAD, PIERCE_BLAST }

## 形态名称（HUD 展示）
@export var form_name: String = ""

## 解锁所需等级（升到该级自动切换）
@export var min_level: int = 1

## 形态类别：决定攻击行为
@export var kind: Kind = Kind.MELEE_ARC

## 伤害系数：伤害 = max(1, Attack × 系数 − Defense)
@export var damage_coefficient: float = 1.0

## 近战：扇形半径（像素）/ 弹道：最大射程（像素）
@export var range: float = 80.0

## 近战扇形半角（度）
@export var arc_half_angle_deg: float = 35.0

## 弹速（像素/秒）
@export var projectile_speed: float = 300.0

## 弹数（SPREAD 三连发为 3）
@export var count: int = 1

## 多弹夹角（度，SPREAD 扇形展开）
@export var spread_deg: float = 18.0

## 冷却时间（秒）
@export var cooldown: float = 0.6

## 穿透（PIERCE_BLAST 弹道穿过第一个目标）
@export var pierce: bool = false

## 命中爆炸半径（PIERCE_BLAST 对周围溅射，0 表示不溅射）
@export var splash_radius: float = 0.0

func get_attack_kind_name() -> String:
	match kind:
		Kind.MELEE_ARC:
			return "近战斩击"
		Kind.PROJECTILE:
			return "圣光飞弹"
		Kind.SPREAD:
			return "三连圣光"
		Kind.PIERCE_BLAST:
			return "圣光裁决"
	return "未知"
