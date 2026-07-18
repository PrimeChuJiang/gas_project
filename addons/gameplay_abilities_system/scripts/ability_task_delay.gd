class_name GASAbilityTaskDelay
extends GASAbilityTask

var _timer: float = 0.0
var _duration: float = 0.0

static func create(ability: GASGameplayAbility, duration: float) -> GASAbilityTaskDelay:
	var task = GASAbilityTaskDelay.new()
	task._duration = duration
	task._spawn(ability)
	return task

func setup(duration: float):
	_duration = duration

func activate():
	_timer = 0.0
	super.activate()
	set_process(true)

func _process(delta: float):
	_timer += delta
	if _timer >= _duration:
		end_task(false)
		GameLogger.info("AbilityTaskDelay", "Delay timer reached, end_task")
		set_process(false)
