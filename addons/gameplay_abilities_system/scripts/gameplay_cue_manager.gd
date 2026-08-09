class_name GASGameplayCueManager
extends Node

# 管理器内嵌小类
class HandlerList extends RefCounted:
	var _items: Array[Callable] = []
	func register(handler: Callable) -> void:
		if not _items.has(handler):
			_items.append(handler)
		else:
			GameLogger.warn("GameplayCueManager", "manager already have the handler")
	func unregister(handler: Callable) -> void:
		if not _items.has(handler):
			GameLogger.error("GameplayCueManager", "handler is not existed")
			return
		for i in range(_items.size()-1, -1, -1):
			if _items[i] == handler:
				_items.remove_at(i)
	func broadcast(tag: FGameplayTag, event: GASEnums.GameplayCueEvent, cue_parameter: GASGameplayCueParameters) -> void:
		for handler in _items.duplicate():
			handler.call(tag, event, cue_parameter)

class ActiveCue extends RefCounted:
	var tag: FGameplayTag
	var target: Node
	var node: Node
	var count: int = 0

var _handlers: Dictionary[FGameplayTag, HandlerList] = {}

var _cue_instances: Dictionary[int, ActiveCue] = {} # handle -> ActiveCue实例
var _active_cues: Dictionary = {} # [tag, target] → ActiveCue实例（存在性计数）
var _cue_factories: Dictionary[FGameplayTag, Callable] = {} # tag → 工厂
var _next_handle: int = 1

func register(tag: FGameplayTag, handler: Callable) -> void:
	if not _handlers.has(tag):
		_handlers[tag] = HandlerList.new()
	_handlers[tag].register(handler)

func unregister(tag: FGameplayTag, handler: Callable) -> void:
	if not _handlers.has(tag):
		GameLogger.error("GameplayCueManager", "handler list is not existed")
		return
	_handlers[tag].unregister(handler)

func broadcast(tag: FGameplayTag, event: GASEnums.GameplayCueEvent, cue_parameter: GASGameplayCueParameters) -> void:
	if not _handlers.has(tag):
		return
	_handlers[tag].broadcast(tag, event, cue_parameter)

func register_factory(tag: FGameplayTag, factory: Callable) -> void:
	if not _cue_factories.has(tag):
		_cue_factories[tag] = factory
	else:
		GameLogger.warn("GameplayCueManager", "factory already registered for tag")

func add_cue(tag: FGameplayTag, target: Node, params: GASGameplayCueParameters) -> int:
	var key: Array = [tag, target]
	var cue: ActiveCue = _active_cues.get(key)
	
	if cue == null:
		cue = ActiveCue.new()
		cue.tag = tag
		cue.target = target
		var factory: Callable = _cue_factories.get(tag, Callable())
		if factory.is_valid():
			var node: Node = factory.call(params)
			if node:
				target.add_child(node)
				cue.node = node
		_active_cues[key] = cue
	
	cue.count += 1
	var handle := _next_handle
	_next_handle += 1
	_cue_instances[handle] = cue
	
	return handle
