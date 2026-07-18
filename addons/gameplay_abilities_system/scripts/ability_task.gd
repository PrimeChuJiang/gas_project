class_name GASAbilityTask
## 工厂方法设计说明：
##   GDScript 不支持泛型，因此基类无法提供一个通用的 static func create()。
##   每个子类需要自己实现 static func create()，内部完成：
##     1. new() 创建自身实例
##     2. 设置子类特有的参数（如 _duration）
##     3. 调用基类的 _spawn(ability) —— 统一处理 ability 赋值、挂场景树、activate
##
## 示例（GASAbilityTaskDelay）：
##   static func create(ability: GASGameplayAbility, duration: float) -> GASAbilityTaskDelay:
##       var task = GASAbilityTaskDelay.new()
##       task._duration = duration
##       task._spawn(ability)
##       return task
##
## 调用侧只需一行：
##   GASAbilityTaskDelay.create(self, 1.5).task_finished.connect(func(_t): end_ability(false))
extends Node

signal task_finished()
signal task_canceled()

# Task所属的Ability组件
var ability: GASGameplayAbility

# 当前Task是否正在运作
var is_running: bool = false

# 
func _spawn(owner_ability: GASGameplayAbility) -> void:
	if owner_ability.is_active == false: 
		GameLogger.warn("AbilityTask", "能力已结束，可此时还在试图启动task")
		free()
		return
	ability = owner_ability
	owner_ability.asc.add_child(self)
	activate()
	owner_ability._active_task.append(self)
	GameLogger.info("AbilityTask", "task spawned, ability = ["+ get_class() +"]")

# 激活task，子类重写需要调用super.activate()
func activate():
	is_running = true
	GameLogger.info("AbilityTask", "Task activated, is_running=true")

# 结束task，子类重写需要调用end_task()
func end_task(canceled: bool):
	set_process(false)
	is_running = false
	ability._active_task.erase(self)
	GameLogger.info("AbilityTask", "Task ended, queue_free")
	if not canceled:
		task_finished.emit()
	else :
		task_canceled.emit()
	queue_free()
