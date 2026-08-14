class_name GASAbilityTargetActor2D
extends GASAbilityTargetActor

@export var collision_mask: int = 1

func select_at(world_pos: Vector2) -> bool:
	var viewport := get_viewport()
	if viewport == null:
		GameLogger.error("GASAbilityTargetActor2D", "no viewport exist!")
		return false
	var space := viewport.world_2d.direct_space_state
	var physics_params : PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	physics_params.position = world_pos
	physics_params.collision_mask = collision_mask
	var results := space.intersect_point(physics_params)
	results.sort_custom(_sort_result)
	for result in results:
		var entity := _resolve_entity(result)
		if entity == null:
			continue
		var data := GASAbilityTargetData.from_actor(entity)
		if entity is Node2D:
			data.location = Vector3(entity.global_position.x, entity.global_position.y, 0.0)
			data.has_location = true
		_update_selection(data)
		return true
	_update_selection(null)
	return false

func select_area(center: Vector2, radius: float) -> bool:
	var viewport := get_viewport()
	if viewport == null:
		GameLogger.error("GASAbilityTargetActor2D", "no viewport exist!")
		return false
	var space := viewport.world_2d.direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = radius
	var physics_params := PhysicsShapeQueryParameters2D.new()
	physics_params.shape = circle
	physics_params.transform = Transform2D(0, center)  # 无旋转 + 圆心在 center
	physics_params.collision_mask = collision_mask
	var results := space.intersect_shape(physics_params)
	var actors: Array[Node] = []
	for result in results:
		var entity := _resolve_entity(result)
		if entity != null:
			actors.append(entity)
	if actors.is_empty():
		_update_selection(null)
		return false
	_update_selection(GASAbilityTargetData.from_actors(actors))
	return true

func _resolve_entity(result: Dictionary) -> Node:
	var collider: CollisionObject2D = result.get("collider") as CollisionObject2D
	if collider == null or not collider.has_meta(ENTITY_META):
		return null
	var entity: Node = collider.get_meta(ENTITY_META)
	if entity == null:
		return null
	if filter.is_valid() and not filter.call(entity):
		return null
	return entity

## 只按自身 z_index 排序，不沿父链累加 z_as_relative（有父级层叠时以父节点为准即可）
func _sort_result(r1: Dictionary, r2: Dictionary) -> bool:
	var collider1: CollisionObject2D = r1.get("collider") as CollisionObject2D
	var collider2: CollisionObject2D = r2.get("collider") as CollisionObject2D
	if collider1 == null or collider2 == null:
		return false
	if collider1.z_index != collider2.z_index:
		return collider1.z_index > collider2.z_index
	return collider1.global_position.y > collider2.global_position.y
