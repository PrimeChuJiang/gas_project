class_name GASAbilityTargetActor
extends Node

const ENTITY_META := &"entity"

signal selection_changed(old_data: GASAbilityTargetData, new_data: GASAbilityTargetData)

var filter: Callable = Callable() # func(node:Node) -> bool, true = 接受

var _current_selection: GASAbilityTargetData = null

func start_targeting() -> void:
	pass

func confirm_target() -> GASAbilityTargetData:
	if _current_selection :
		var target: GASAbilityTargetData = GASAbilityTargetData.new()
		target.actors = _current_selection.actors.duplicate()
		target.location = _current_selection.location
		target.has_location = _current_selection.has_location
		return target
	return null

func cancel_target() -> void:
	_update_selection(null)

func _update_selection(new_data: GASAbilityTargetData) -> void:
	var old_data := _current_selection
	_current_selection = new_data
	if old_data == null :
		if _current_selection == null:
			return
	elif old_data.is_same_as(new_data):
		return
	selection_changed.emit(old_data, new_data) 
