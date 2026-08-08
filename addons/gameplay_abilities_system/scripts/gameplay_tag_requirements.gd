class_name GASGameplayTagRequirements
extends Resource       # 定义层：@export、可进 .tres、_init 必须零参可调

@export var required_tags: FGameplayTagContainer = FGameplayTagContainer.new()
@export var blocked_tags: FGameplayTagContainer = FGameplayTagContainer.new()

# 判定：required 全有 且 blocked 全无；has_fn 由调用方决定查哪家
func requirements_met(has_fn: Callable) -> bool:
	for tag in required_tags._tags:
		if not has_fn.call(tag):
			return false
	for tag in blocked_tags._tags:
		if has_fn.call(tag):
			return false
	return true
