extends Node2D
## 眩晕 GameplayCue 表现节点：旋转星星，挂在目标所在棋盘格上
## 由表现层工厂产出，生命周期归 GameplayCueManager 凭票制管理（逻辑层零感知）

var _sprite: Sprite2D

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/game-icons.net/icons/knocked-out-stars.svg")
	_sprite.position = Vector2(20, 20)
	_sprite.scale = Vector2(1.3, 1.3)
	add_child(_sprite)

func _process(delta: float) -> void:
	_sprite.rotation += delta * 2.5
