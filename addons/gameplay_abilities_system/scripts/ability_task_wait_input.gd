class_name GASAbilityTaskWaitInput
extends GASAbilityTask

var _input_action: StringName = &""
var _timeout: float = -1.0
var _timer: float = 0.0

static func create(ability: GASGameplayAbility, input_action: StringName, timeout:float = -1.0) -> GASAbilityTaskWaitInput:
	var task := GASAbilityTaskWaitInput.new()
	task._input_action = input_action
	task._timeout = timeout
	task._spawn(ability)
	return task

func activate() -> void:
	_timer = 0.0
	super.activate()
	set_process(true)

func _process(delta: float) -> void:
	_timer += delta
	if _timeout > 0.0 and _timer >= _timeout:
		end_task(true)
		return
	if Input.is_action_just_pressed(_input_action):
		end_task(false)
		return
