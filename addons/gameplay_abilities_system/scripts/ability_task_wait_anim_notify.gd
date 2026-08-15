class_name GASAbilityTaskWaitAnimNotify
extends GASAbilityTask

var notify_source: Object = null
var notify_signal: StringName = &""
var notify_name: StringName = &""

static func create(ability: GASGameplayAbility, notify_source: Object, notify_signal: StringName, notify_name: StringName) -> GASAbilityTaskWaitAnimNotify:
	var task := GASAbilityTaskWaitAnimNotify.new()
	task.notify_source = notify_source
	task.notify_signal = notify_signal
	task.notify_name = notify_name
	task._spawn(ability)
	return task

func activate() -> void:
	notify_source.connect(notify_signal, _on_notify)
	super.activate()

func _on_notify(name: StringName) -> void:
	if not is_running:
		return
	if name == notify_name:
		end_task(false)
