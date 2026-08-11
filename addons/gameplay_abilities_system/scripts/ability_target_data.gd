class_name GASAbilityTargetData
extends RefCounted

## 目标 Actors 集合
var actors: Array[Node] = []
## 目标位置
var location: Vector3 = Vector3.ZERO
## 目标位置是否有效
var has_location: bool = false 

static func from_actor(actor: Node) -> GASAbilityTargetData:
	var target_data = GASAbilityTargetData.new()
	target_data.actors.append(actor)
	return target_data

static func from_actors(actors: Array[Node]) -> GASAbilityTargetData:
	var target_data = GASAbilityTargetData.new()
	target_data.actors = actors.duplicate(true)
	return target_data

static func from_location(pos: Vector3) -> GASAbilityTargetData:
	var target_data = GASAbilityTargetData.new()
	target_data.location = pos
	target_data.has_location = true
	return target_data

func get_actor() -> Node:
	if actors.is_empty():
		return null
	else:
		return actors[0]

func get_actors() -> Array[Node]:
	return actors

func get_location() -> Vector3:
	return location

func is_same_as(other: GASAbilityTargetData) -> bool:
	if other == null:
		return false
	if has_location != other.has_location:
		return false
	if has_location and location != other.location:
		return false
	return actors == other.actors
