class_name GASGameplayEffect
extends Resource

# 持续策略
@export var duration_policy : GASEnums.DurationPolicy = GASEnums.DurationPolicy.INSTANT

# 持续时长 (INSTANT 忽略)
@export var duration: float = 0.0

# 周期性间隔 (0.0 = 不周期)
@export var period: float = 0.0

# 堆叠策略
@export var stack_policy: GASEnums.StackingPolicy = GASEnums.StackingPolicy.NONE

# 堆叠数量限制，仅当堆叠策略为LIMITED的时候生效
@export var stack_limit: int = 1

# GEModifier修改器列表
@export var modifiers: Array[GEModifier] = []

# GASExecutionCalculation执行器
@export var executions: Array[GASExecutionCalculation] = []

# 效果自身标签
@export var asset_tags: FGameplayTagContainer = FGameplayTagContainer.new()

# 授予目标的标签 (效果存在时持续，效果移除时自动撤销)
@export var granted_tag: FGameplayTagContainer = FGameplayTagContainer.new()

# 触发的表现效果标签
@export var gameplay_cue_tags: FGameplayTagContainer = FGameplayTagContainer.new()

# GE描述
@export_multiline var comment: String = "注释，用于描述GE内容"
