class_name GASAbilityTaskWaitGameplayEvent
extends GASAbilityTask

var _event_tag: FGameplayTag = null
var _event_data: GASGameplayEventData
var _timeout: float = -1.0
var _timer: float = 0.0

static func create(ability: GASGameplayAbility, event_tag: FGameplayTag, timeout: float = -1.0) -> GASAbilityTaskWaitGameplayEvent:
	var task := GASAbilityTaskWaitGameplayEvent.new()
	task._event_tag = event_tag
	task._timeout = timeout
	task._spawn(ability)
	return task

func activate() -> void:
	_timer = 0.0
	ability.asc.gameplay_event_received.connect(_on_event)
	super.activate()
	set_process(true)

func _process(delta):
	_timer += delta
	if _timeout > 0.0 and _timer >= _timeout:
		end_task(true)

func _on_event(event_tag: FGameplayTag, event_data: GASGameplayEventData):
	if not is_running:
		return
	if event_tag.matches_tag(_event_tag):
		_event_data = event_data
		end_task(false)

func get_event_data() -> GASGameplayEventData:
	return _event_data
