class_name GASGameplayEffect
extends Resource

# 持续策略
@export var duration_policy : GASEnums.DurationPolicy = GASEnums.DurationPolicy.INSTANT

# 持续时长 (INSTANT 忽略)
@export var duration: float = 0.0

# 周期性间隔 (0.0 = 不周期)
@export var period: float = 0.0

# 首跳立即执行（UE bExecutePeriodicEffectOnApplication）：apply 时立即跳第一次，
# 之后仍按完整周期；关闭则等第一个 period 才跳
@export var execute_periodic_effect_on_application: bool = false

# 堆叠策略
@export var stack_policy: GASEnums.StackingPolicy = GASEnums.StackingPolicy.NONE

# 堆叠数量限制，仅当堆叠策略为LIMITED的时候生效
@export var stack_limit: int = 1

# 堆叠类型
@export var stack_type: GASEnums.StackType = GASEnums.StackType.AGGREGATE

# 堆叠消除策略
@export var expiration_policy: GASEnums.StackingExpirationPolicy = GASEnums.StackingExpirationPolicy.REMOVE_SINGLE

# 叠层/刷新时是否重置周期计时
@export var reset_period_on_stack: bool = false

@export var relevant_attributes: Array[GASCaptureDefinition] = []

@export var custom_application_requirements: Array[GASCustomApplicationRequirement] = []

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

# 目标身上满足这些标签条件，GE 才被允许部署上去；不满足直接拒绝，GE 根本不会挂到目标身上
@export var application_tag_requirements: GASGameplayTagRequirements = GASGameplayTagRequirements.new()

# GE 已部署后，每帧/每次标签变化时检查目标身上的标签；不满足时 GE 被挂起（suspended）
@export var ongoing_tag_requirements: GASGameplayTagRequirements = GASGameplayTagRequirements.new()

# 随GE部署的Ability
@export var granted_abilities: Array[GASGameplayAbility] = []

# 是否在GE部署的时候触发Ability
@export var activate_abilities_on_grant: bool = false

# GE描述
@export_multiline var comment: String = "注释，用于描述GE内容"
