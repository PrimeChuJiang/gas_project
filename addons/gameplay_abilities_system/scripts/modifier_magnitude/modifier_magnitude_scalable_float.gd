class_name GASModifierMagnitudeScalableFloat
extends GASModifierMagnitude

@export var value: float = 0.0

@export var level_curve: Curve = null

func _calculate(spec: GASEffectSpec) -> float:
	if level_curve:
		return level_curve.sample(spec.level)
	return value

func is_snapshot() -> bool:
	return true

## 安全建曲线（替代手工 Curve.add_point）：
## Godot 4.7 起 Curve.add_point 会把坐标钳制进 min/max 值域（默认 [0,1]），
## 手工建点超出范围会被静默钳制导致曲线失真。本方法先按传入点的实际范围
## 拓宽 domain/value limits 再逐点添加（.tres 序列化会自带 limits，不受影响）。
func set_level_curve_from_points(points: PackedVector2Array) -> void:
	if points.is_empty():
		level_curve = null
		return
	var curve := Curve.new()
	var min_x := points[0].x
	var max_x := points[0].x
	var min_y := points[0].y
	var max_y := points[0].y
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	curve.set_min_domain(min_x)
	curve.set_max_domain(max_x)
	curve.set_min_value(min_y)
	curve.set_max_value(max_y)
	for p in points:
		curve.add_point(p)
	level_curve = curve
