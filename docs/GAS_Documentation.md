# Gameplay Ability System (GAS) 系统设计文档

> 本文档基于 Unreal Engine 的 GameplayAbilitySystem 插件（参考 Tranek/GASDocumentation 及 Epic 官方文档），
> 总结了 GAS 核心概念和架构，作为 Godot 重写版本的参考。

---

## 1. 概述

Gameplay Ability System (GAS) 是 Epic Games 开发的高度灵活的框架，用于构建 RPG/MOBA 类型游戏中的能力和属性系统。它在 Fortnite、Paragon 等 AAA 商业游戏中经过了实战检验。

GAS 解决的场景：
- 基于等级的角色能力/技能（带消耗和冷却）
- 操控角色的数值属性（血量、攻击力等）
- 状态效果（Buff/Debuff）
- 用 GameplayTags 描述对象状态
- 生成视觉/音频效果（GameplayCues）
- 上述所有内容的网络复制和客户端预测

---

## 2. 核心架构全景图

```
┌──────────────────────────────────────────────────────────────┐
│                    AbilitySystemComponent (ASC)               │
│                        系统核心中枢                            │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ GameplayTags │  │  Attributes  │  │  GameplayEffects   │  │
│  │ (标签状态)   │  │  (数值属性)  │  │  (效果/Buff)       │  │
│  └──────────────┘  └──────────────┘  └────────────────────┘  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │  Abilities   │  │ AbilityTasks │  │   GameplayCues     │  │
│  │  (能力)      │  │ (异步任务)   │  │   (表现效果)       │  │
│  └──────────────┘  └──────────────┘  └────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. AbilitySystemComponent (ASC) - 系统核心

### 3.1 基本概念

ASC 是 GAS 的心脏，是挂载在 Actor 上的组件。任何想要使用 GAS 的对象都必须有一个 ASC。

- **OwnerActor**: 拥有 ASC 的 Actor（逻辑所有者）
- **AvatarActor**: ASC 的物理表现 Actor（动画/碰撞体）

两者可以是同一个 Actor（如小兵），也可以不同（如 MOBA 英雄：OwnerActor=PlayerState，AvatarActor=Character）。

如果 Actor 会重生且需要属性/效果持久化（如 MOBA 英雄），则 ASC 应放在 PlayerState 上。

### 3.2 ASC 内部结构

```
ASC
├── ActiveGameplayEffects (FActiveGameplayEffectsContainer)
│   └── 当前激活的所有 GameplayEffect 实例
└── ActivatableAbilities (FGameplayAbilitySpecContainer)
	└── 已授予的所有 GameplayAbility Spec
```

### 3.3 复制模式 (Replication Mode)

| 模式     | 场景                         | 说明                                    |
| -------- | ---------------------------- | --------------------------------------- |
| `Full`   | 单机                         | 所有 GE 复制到所有客户端                |
| `Mixed`  | 多人，玩家控制的 Actor       | GE 只复制到拥有者客户端，Tags/Cues 全复制 |
| `Minimal`| 多人，AI 控制的 Actor        | GE 不复制，Tags/Cues 全复制             |

> 对于 Godot 单机场景，我们暂时只需要 "Full" 或类似模式。多人模式后续再考虑。

### 3.4 IAbilitySystemInterface 接口

任何拥有 ASC 的 Actor 都应实现此接口，提供 `get_ability_system_component()` 方法，方便其他 GAS 组件互相查找。

---

## 4. GameplayTags（已完成）

GameplayTags 是 `Parent.Child.Grandchild...` 形式的分层名称标签，用于描述对象状态。

例如: `State.Debuff.Stun` 表示眩晕状态。

项目已有完整实现，核心类：
- `FGameplayTag`（标签本体，享元模式）
- `FGameplayTagContainer`（标签容器）
- `FGameplayTagNode`（标签树节点）
- `MultiwayTree`（多叉树数据结构）

---

## 5. Attributes 与 AttributeSet - 属性系统

### 5.1 Attribute 定义

Attributes 是 `float` 类型的数值，代表角色的各种属性：血量、攻击力、移速、等级等。

**属性应只在 AttributeSet 中定义，并被 GameplayEffect 修改**，这样才能让 ASC 进行正确的预测和回滚。

### 5.2 BaseValue vs CurrentValue

每个属性有两个值：

| 值            | 含义                           | 修改方式                  |
| ------------- | ------------------------------ | ------------------------- |
| `BaseValue`   | 永久值（基础值）               | 瞬时 GE (Instant) 修改    |
| `CurrentValue`| 当前值（Base + 临时修改）      | 持续 GE (Duration/Infinite) 修改 |

```
CurrentValue = (BaseValue + Additive) * Multiplicative / Division
```

**重要**: BaseValue 不是最大值，最大值应作为单独的 Attribute 定义。

### 5.3 Meta Attributes（元属性）

Meta Attributes 是临时的占位属性，用于在效果间传递值。

典型的例子是 Damage（伤害）：
1. GE 计算出伤害值，写入 `Damage` 这个 Meta Attribute
2. AttributeSet 的 `PostGameplayEffectExecute` 读取 `Damage` 值
3. 执行护盾减伤、护甲减免等逻辑
4. 最终扣减 `Health` 属性

这样设计的好处是：伤害计算逻辑（GE/ExecutionCalc）不需要知道目标是否有护盾、护甲等。逻辑分离清晰。

### 5.4 AttributeSet 定义

`AttributeSet` 是属性的容器和复制单元，所有属性必须定义在 `AttributeSet` 子类中。

```gdscript
# 示例：基础属性集
class GASAttributeSet extends Resource:
	var health: float        # 生命值
	var max_health: float    # 最大生命值
	var mana: float          # 法力值
	var max_mana: float      # 最大法力值
	var attack_power: float  # 攻击力
	var defense: float       # 防御力
	var move_speed: float    # 移动速度
```

### 5.5 AttributeSet 设计原则

- 一个 ASC 可以有多个 AttributeSet
- 不应在同一个 ASC 上有多个同类的 AttributeSet
- 可按功能分组：HealthSet、ManaSet、CombatSet 等
- 支持运行时动态添加/移除（如 MOBA 英雄需要 Mana，小兵不需要）

### 5.6 AttributeSet 核心方法

#### PreAttributeChange
在属性值真正改变之前调用，用于 Clamp（钳制）值到合法范围。

```
PreAttributeChange(attribute, new_value) -> clamped_value
```

#### PostGameplayEffectExecute
在 GE 执行修改后调用，这是处理连锁反应的地方：
- 伤害扣血
- 死亡检测
- 属性联动（如护盾先扣）

### 5.7 属性变化监听

```gdscript
# 绑定属性变化回调
asc.get_gameplay_attribute_value_change_delegate(health_attr).connect(_on_health_changed)

func _on_health_changed(new_value: float, old_value: float):
	update_health_ui(new_value)
	if new_value <= 0:
		handle_death()
```

---

## 6. GameplayEffects (GE) - 效果系统

GameplayEffect 是 GAS 中修改属性的唯一合法方式，它是一个**数据定义对象**（而非有执行逻辑的类）。

### 6.1 GE 策略 (Duration Policy)

| 类型       | 含义                       | 对属性的影响                  |
| ---------- | -------------------------- | ----------------------------- |
| `Instant`  | 立即执行一次               | 修改 BaseValue                |
| `Duration` | 持续一段时间               | 修改 CurrentValue，过期回退   |
| `Infinite` | 永久持续，直到手动移除     | 修改 CurrentValue             |

### 6.2 GE 配置内容

```
GameplayEffect 定义
├── Duration Policy (Instant/Duration/Infinite)
├── Duration Magnitude (持续期间的倍率策略)
├── Modifiers (修改器列表)
│   ├── Attribute (目标属性)
│   ├── Modifier Op (Add/Multiply/Divide/Override)
│   ├── Magnitude Calculation Type (ScalableFloat/AttributeBased/CustomCalc/SetByCaller)
│   └── Tags (修改器生效所需的标签条件)
├── Application Tag Requirements (应用条件)
├── Stacking (堆叠配置)
│   ├── Stack Limit Count / Duration Refresh Policy / Expiration Policy
├── Granted Abilities (授予的能力)
├── Gameplay Effect Tags
│   ├── Asset Tags (GE 资产自身的标签)
│   └── Granted Tags (给予目标的标签)
├── Immunity (免疫配置)
├── Gameplay Cues (触发的表现效果)
├── Period (周期性执行间隔，0=非周期性)
└── Executions (执行器)
	└── ExecutionCalculations (自定义计算类)
```

### 6.3 Modifiers (修改器)

修改器定义了"修改哪个属性、改多少、怎么改"。

#### 修改器操作类型 (Modifier Op)

| 操作     | 公式                      |
| -------- | ------------------------- |
| `Add`    | +Value                    |
| `Multiply`| * (1 + Value)            |
| `Divide` | / (1 + Value)             |
| `Override`| = Value                  |

#### 数值计算类型 (Magnitude Calculation)

| 类型                  | 说明                                    |
| --------------------- | --------------------------------------- |
| `ScalableFloat`       | 直接配置 float 值（支持等级曲线）       |
| `AttributeBased`      | 基于某属性的值计算                      |
| `CustomCalculationClass` | 使用 MMC 自定义计算类               |
| `SetByCaller`         | 运行时由调用者传入值                    |

### 6.4 Execution Calculation (执行器)

`GameplayEffectExecutionCalculation` 是 GE 中最强大（也最复杂）的修改方式，用于处理复杂的属性计算，如伤害公式：

```
实际伤害 = (攻击力 * 技能倍率 - 防御力 * 穿透系数) * 暴击倍率
```

ExecutionCalculation 可以：
- 读取 Source 和 Target 的任意属性
- 应用复杂的自定义公式
- 输出多个属性的修改值
- 一次修改多个属性

### 6.5 MMC (Modifier Magnitude Calculation)

MMC 是介于 ScalableFloat 和 ExecutionCalculation 之间的计算方式。它可以：
- 读取 Source 或 Target 的任意属性
- 返回一个 float 值作为修改器的数值

与 ExecutionCalculation 的区别：MMC 只能返回一个 float，不能直接修改属性。

### 6.6 Stacking (堆叠)

GE 支持堆叠机制：

| 配置项                | 说明                         |
| --------------------- | ---------------------------- |
| `Stack Limit Count`   | 最大堆叠层数                 |
| `Stack Duration Refresh Policy` | 新层是重置还是独立计时 |
| `Stack Expiration Policy`       | 过期是清空全部还是一层层移除 |

### 6.7 周期执行 (Period)

如果 GE 的 `Period` > 0，它会周期性执行修改。例如每秒回血 10 点：
- Period = 1.0 秒
- Modifier: Add +10 to Health

### 6.8 Granted Tags (授予标签)

GE 可以授予目标 GameplayTags，这些标签在 GE 存在期间有效，GE 移除时自动撤销。

这是实现状态效果（眩晕、减速、无敌等）的核心机制：

```
眩晕 GE:
  ├── Duration: 3 秒
  ├── Granted Tags: [State.Debuff.Stun]
  └── 角色输入系统检测到 State.Debuff.Stun → 禁用移动
```

### 6.9 Granted Abilities (授予能力)

GE 可以在其持续期间授予目标临时能力。例如"获得火球术"Buff。

### 6.10 Immunity (免疫)

GE 可以配置免疫规则：当目标拥有某些 Tag 时，阻止此 GE 的某些 Tag 被授予。

### 6.11 Gameplay Effect Spec (GE 实例)

`GameplayEffectSpec` 是 GE 定义的应用实例，保存了运行时上下文：
- Source (来源)
- Target (目标)
- Level (等级)
- Duration (持续时长)
- Period (周期)
- SetByCaller 数据
- EffectContext

### 6.12 Gameplay Effect Context

`GameplayEffectContext` 包含 GE 实例的额外上下文信息：
- Instigator (发起者)
- Causer (物理原因对象，如投射物)
- HitResult (碰撞结果)
- Origin (效果起始位置)

### 6.13 Cost GE 和 Cooldown GE

- **Cost GE**: 技能释放时消耗资源的 GE（消耗 50 法力）
- **Cooldown GE**: 技能释放后进入冷却的 GE（冷却 10 秒）

它们是普通 GE 的特殊应用：在技能 `Commit` 时执行。冷却 GE 附加的标签（如 `Ability.Skill.Fireball.Cooldown`）会阻止技能再次激活。

### 6.14 GE 生命周期

```
[GE 定义] 
	→ 创建 FGameplayEffectSpec (实例化)
	→ ASC.ApplyGameplayEffectSpecToSelf/Target()
	→ ASC.ApplyGE_Internal()
	→ PreAttributeChange() (钳制)
	→ ExecutionCalculation (如果配置)
	→ Modifiers 逐个应用
	→ PostGameplayEffectExecute() (连锁反应)
	→ 添加 Granted Tags
	→ 触发 GameplayCues
	
[Duration/Infinite GE]
	→ 加入 ActiveGameplayEffects 容器
	→ 开始计时 → (Period 周期性执行)
	→ 到期 → 回退 CurrentValue → 移除 Granted Tags → 移除
```

---

## 7. Gameplay Abilities (GA) - 能力系统

### 7.1 能力定义

`GameplayAbility` 定义了角色可以执行的动作：
- 攻击（近战/远程/技能）
- 跳跃
- 冲刺
- 使用物品
- 施法
- 任何由玩家/AI 触发的 Gameplay 行为

### 7.2 能力核心方法

```gdscript
class GameplayAbility:
	func can_activate(ability_spec, asc) -> bool:
		# 检查：Cost 是否够、Cooldown 是否结束、Tag 条件是否满足
		pass
	
	func activate(ability_spec, asc):
		# 1. Commit (消耗资源、启动冷却)
		# 2. 执行能力逻辑（通过 AbilityTasks）
		pass
	
	func end_ability(ability_spec, asc):
		# 结束能力，清理资源
		pass
	
	func cancel_ability(ability_spec, asc):
		# 取消能力
		pass
```

### 7.3 实例化策略 (Instancing Policy)

| 策略                | 说明                                    | 适用场景          |
| ------------------- | --------------------------------------- | ----------------- |
| `InstancedPerActor` | 每个 Actor 拥有独立的 GA 实例           | 大多数情况        |
| `InstancedPerExecution` | 每次激活都创建新 GA 实例            | 需要每次独立状态  |
| `NonInstanced`      | 所有 Actor 共享同一个 GA 实例（无状态）  | 跳跃等简单动作    |

### 7.4 网络执行策略 (Net Execution Policy)

| 策略             | 说明                               |
| ---------------- | ---------------------------------- |
| `LocalOnly`      | 只在本地执行                       |
| `LocalPredicted` | 本地预测 + 服务器验证             |
| `ServerOnly`     | 只在服务器执行                     |
| `ServerInitiated`| 服务器发起，复制到客户端           |

> 对于 Godot 单机版本，我们主要使用 LocalOnly。

### 7.5 能力标签 (Ability Tags)

每个 GA 可以配置三组标签：

- **Ability Tags**: 能力拥有的标签（激活期间附加给 Owner）
- **Cancel Abilities with Tag**: 激活时取消拥有特定标签的其他能力
- **Block Abilities with Tag**: 该能力激活时阻止拥有特定标签的能力激活
- **Activation Owned Tags**: 激活时授予 Owner 的标签
- **Activation Required/Optional Tags**: 激活所需的/可选的目标标签条件
- **Source Required/Optional Tags**: 来源需要的/可选的标签条件
- **Target Required/Optional Tags**: 目标需要的/可选的标签条件

这构成了能力之间的"冲突/取消/阻挡"关系网络。

### 7.6 能力授权 (Granting Abilities)

能力通过 `AbilitySpec` 授权给 ASC：
```gdscript
asc.grant_ability(ability_class, level, source_object)
```

能力可以在角色初始化时授予（固有技能），也可以通过 GE 临时授予（如拾取道具获得技能）。

### 7.7 能力的 Commit 流程

```gdscript
# Activate 中的典型流程
func activate(ability_spec, asc):
	# Commit: 检查并应用 Cost 和 Cooldown
	if not commit_ability(ability_spec, asc):
		return  # Cost 不够或 Cooldown 中
	
	# 执行能力逻辑...
```

### 7.8 Ability Spec (能力规格)

`FGameplayAbilitySpec` 包含运行时信息：
- Ability Class
- Level
- SourceObject (来源对象)
- ActiveCount (激活次数)
- InputID (输入绑定的 ID)
- ActivationInfo (最近激活信息)

### 7.9 能力等级

能力可以有等级（Level 1, 2, 3...），等级会影响：
- 伤害数值（通过 ScalableFloat 的等级曲线）
- Cooldown 时长
- Cost 消耗
- 解锁新的效果

### 7.10 输入绑定

UE 中将输入 Action 绑定到 AbilityTag，通过 ASC 的输入处理函数触发能力。

Godot 中我们可以利用 InputMap 实现类似机制：
```gdscript
# 将 "jump" 输入绑定到 Ability.Jump 标签对应的能力
asc.bind_ability_activation(input_name, ability_tag)
```

---

## 8. Ability Tasks - 异步任务系统

### 8.1 基本概念

Ability Tasks 是 GA 中执行异步操作的专用类。能力激活后，往往需要"等一会"、"等动画播完"、"等玩家释放按键"等异步操作。

AbilityTask 继承自 GameplayTask，提供：
- 异步操作的启动和结束
- 通过信号/回调通知 GA 状态变化
- 自动在能力结束时清理

### 8.2 内置 Ability Tasks

| Task                        | 功能                           |
| --------------------------- | ------------------------------ |
| `PlayMontageAndWait`       | 播放动画蒙太奇并等待           |
| `WaitTargetData`           | 等待目标选择数据               |
| `WaitGameplayEvent`        | 等待 Gameplay 事件             |
| `WaitDelay`                | 等待指定时间                   |
| `WaitAttributeChange`      | 等待属性变化                   |
| `WaitGameplayTagAdd/Remove`| 等待标签添加/移除              |
| `WaitInputPress/Release`   | 等待输入按下/释放              |
| `WaitOverlap`              | 等待碰撞重叠                   |

### 8.3 Godot 中的实现思路

利用 Godot 的 `signal` + `await`/`tween` 机制：

```gdscript
class AbilityTask extends RefCounted:
	signal finished()
	signal ready()
	
	var ability: GameplayAbility
	var asc: AbilitySystemComponent
	
	func activate():
		pass
	
	func end_task():
		finished.emit()
```

```gdscript
# 使用示例：在 GA 中
func activate(...):
	# 播放动画并等待
	var task = PlayAnimationTask.new(animation_player, "attack")
	task.finished.connect(_on_animation_finished)
	task.activate()

func _on_animation_finished():
	# 动画结束，继续后续逻辑
	apply_damage()
	end_ability()
```

---

## 9. Gameplay Cues - 表现效果系统

### 9.1 基本概念

Gameplay Cues 是 GAS 提供的视觉效果和音频系统，与游戏逻辑分离。

当一个 GE 被应用时，如果它配置了 GameplayCues，系统会通过 `GameplayCue` + `Tag` 的方式触发表现效果。

### 9.2 GameplayCue 的两种类型

| 类型           | 说明                                    | 示例             |
| -------------- | --------------------------------------- | ---------------- |
| `Static`       | 一次性效果（无生命周期）                | 子弹命中火花特效 |
| `Actor`        | 持续效果（随 GE/能力生命周期存在/销毁） | 眩晕的旋转星星   |

### 9.3 触发方式（✅ 已实现）

```gdscript
# GE 自动触发：在 GE 配置中指定 GameplayCue Tags
#   INSTANT GE 应用 → EXECUTED（一次性）
#   DURATION/INFINITE GE 挂账 → ON_ACTIVE，移除 → ON_REMOVED
#   周期 GE 每跳 → EXECUTED（对齐 UE：周期执行 = 一次 Execute）
# WHILE_ACTIVE 有意不做：持续表现由凭票节点自身 _process 承担（枚举保留对齐 UE）
# 手动触发：
asc.execute_gameplay_cue(tag, params)     # Static：广播 EXECUTED 给 handler
asc.add_gameplay_cue(tag, params)         # Actor (持续)：凭票制，返回 handle（target 取自 params.target）
asc.remove_gameplay_cue(handle)           # 凭票移除 Actor Cue（无效票返回 false）
```

### 9.4 Tag 命名规范

GameplayCue 通过 GameplayTag 映射到具体实现：
```
GameplayCue.Weapon.Gun.Impact  → GunImpactCue (播放枪击特效+音效)
GameplayCue.Status.Stun        → StunCue (播放眩晕光环)
```

### 9.5 Godot 中的实现思路

```gdscript
class GameplayCueManager:
	var _cue_handlers: Dictionary = {}  # tag -> handler callback
	
	func handle_gameplay_cue(tag: FGameplayTag, source: Node, params: Dictionary):
		var handler = _cue_handlers.get(tag.tag_name)
		if handler:
			handler.call(source, params)
	
	func add_gameplay_cue(tag: FGameplayTag, source: Node, params: Dictionary):
		# 创建持续表现，记录以便后续移除
		pass
```

---

## 10. Prediction - 客户端预测（仅多人）

### 10.1 概述

GAS 支持客户端预测以下内容：
- 能力激活
- 动画播放
- 属性变化
- GameplayTags 添加
- GameplayCues 触发

预测的基本流程是：
1. 客户端立即执行（预测）
2. 同时发送 RPC 到服务器
3. 服务器验证并执行
4. 服务器结果复制回客户端
5. 客户端比对，必要时回滚

> 对于 Godot 单机版本，预测不是必需的。但在设计架构时保留这种可能性。

---

## 11. Targeting - 目标系统

### 11.1 Target Data

`FGameplayAbilityTargetData` 包含目标选择的结果：
- 单个目标/多个目标
- 目标位置
- 目标 Actor
- Hit Result

### 11.2 Target Actor

`GameplayAbilityTargetActor` 是执行目标选择的游戏对象：
- 鼠标射线检测
- 范围 AOE 检测
- 锁定目标

### 11.3 Godot 中的实现

可以利用 Godot 的物理碰撞检测 + Area 节点：
```gdscript
# 鼠标点击目标选择
func get_target_data_from_mouse():
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(...)
	var result = space_state.intersect_ray(query)
	return GameplayAbilityTargetData.from_hit_result(result)

# AOE 范围目标选择
func get_target_data_in_radius(center, radius):
	var targets = area.overlapping_bodies
	return GameplayAbilityTargetData.from_targets(targets)
```

---

## 12. 数据流全链路示例

以"战士释放烈火斩"为例，展示 GAS 中各组件的协作：

```
1. 玩家按下 Q 键
   → ASC 收到 InputID
   → ASC 查找该 InputID 绑定的 Ability (烈火斩 GA)

2. GA.CanActivate() 检查
   → 是否有 Cooldown Tag "Ability.Warrior.FireStrike.Cooldown"？没有 → 通过
   → Cost 检查：法力是否 >= 30？ 50 >= 30 → 通过
   → 阻塞标签检查：是否被沉默？没有 → 通过
   
3. GA.Activate()
   → 1) CommitAbility:
		 → 应用 Cost GE: -30 法力
		 → 应用 Cooldown GE: 添加 "Ability.Warrior.FireStrike.Cooldown" Tag (8秒)
   → 2) WaitTargetData Task: 等待玩家选定目标
   
4. 玩家选中目标
   → TargetData 包含目标敌人信息返回给 GA

5. GA 继续执行：
   → 播放攻击动画 (PlayMontageAndWait Task)
   → 动画到达"造成伤害"帧
   
6. 创建 Damage GE Spec：
   → ScalableFloat Modifier: Damage.Add = 100 * LevelCurve
   → 加上攻击力的 AttributeBased 加成
   → 填充 EffectContext (来源、目标、HitResult)

7. ASC.ApplyGameplayEffectSpecToTarget(damage_spec, target_asc)
   → target_asc 开始处理 Damage GE
   
8. Target 的属性处理链：
   → PreAttributeChange: 钳制伤害值
   → ExecutionCalculation: 实际伤害 = (攻击力 * 1.5 - 防御力 * 0.7) * (暴击? 2: 1)
   → Modifiers 应用
   → PostGameplayEffectExecute:
		→ 先扣护盾 Shield，再扣 Health
		→ Health <= 0? → 触发死亡流程

9. 激活 GameplayCue：
   → GE 中配置的 GameplayCue.Weapon.FireStrike.Impact 触发
   → 播放火焰特效 + 受击音效
```

---

## 13. Godot 重写的架构建议

### 13.1 核心类映射

| UE 类                        | Godot 类                        | 基础类型     |
| ---------------------------- | ------------------------------- | ------------ |
| `UAbilitySystemComponent`    | `GASAbilitySystemComponent`     | Node         |
| `UAttributeSet`              | `GASAttributeSet`               | Resource     |
| `FGameplayAttributeData`     | `GASAttributeData`              | RefCounted   |
| `UGameplayEffect`            | `GASGameplayEffect`             | Resource     |
| `FGameplayEffectSpec`        | `GASEffectSpec`                 | Resource     |
| `FGameplayEffectContext`     | `GASEffectContext`              | RefCounted   |
| `UGameplayAbility`           | `GASGameplayAbility`            | Resource     |
| `FGameplayAbilitySpec`       | `GASAbilitySpec`                | Resource     |
| `UAbilityTask`               | `GASAbilityTask`                | RefCounted   |
| `UGameplayCueManager`        | `GASGameplayCueManager`         | Autoload     |
| `FGameplayAbilityTargetData` | `GASAbilityTargetData`          | RefCounted   |
| `IAbilitySystemInterface`    | （Duck typing，非必须）          | -            |

### 13.2 文件结构（当前实际）

```
addons/gameplay_tags/                    # Tag 插件（独立）
├── gameplay_tags.gd                     # EditorPlugin：注册 autoload / 底部面板 / Inspector
└── scripts/
	├── gameplay_tag_manager.gd          # 单例：双轨索引（哈希 + 多叉树）+ 享元池
	├── structure/                       # f_gameplay_tag / f_gameplay_tag_container
	│                                    # / f_gameplay_tag_node / multi_way_tree
	└── resources/gameplay_tag_list.gd   # cfg 文件读写

addons/gameplay_abilities_system/
├── plugin.cfg
├── gameplay_abilities_system.gd         # EditorPlugin 入口
└── scripts/
	├── enums.gd                         # DurationPolicy / ModifierOp / Stacking...
	├── attribute_data.gd                # 单个属性（evaluate 聚合权威）
	├── attribute_set.gd                 # 属性集（Pre 钳制 / Post 连锁钩子）
	├── gameplay_effect.gd               # GE 配方
	├── gameplay_effect_modifier.gd      # 一条修改指令
	├── gameplay_effect_spec.gd          # GE 实例
	├── gameplay_effect_context.gd       # 效果上下文
	├── gameplay_effect_capture_definition.gd  # 捕获声明
	├── gameplay_tag_requirements.gd     # 门禁条件（application / ongoing）
	├── ability_system_component.gd      # ASC 核心（大脑）
	├── gameplay_ability.gd              # 能力类
	├── ability_task.gd                  # 异步任务基类
	├── ability_task_delay.gd            # 延时任务
	├── modifier_pile.gd                 # 租约账页条目（op/magnitude/handle/层数/挂起）
	├── modifier_bucket.gd               # 装配分组容器
	├── modifier_spec.gd                 # modifier 运行时账页（resolved/value）
	├── modifier_evaluated_data.gd       # execution 输出小票
	├── modifier_magnitude/              # magnitude 家族（4 个子类）
	├── execution_calculation/           # 执行器基类
	└── test/                            # TestScene + 测试 GE/能力 + 一键回归
```

### 13.3 实现状态（2026-08 更新）

> 原"实现优先级"清单已全部推进完毕，按现状重排为状态表。
> 完整架构讲解见 [System_Architecture.md](System_Architecture.md)。

| # | 模块 | 状态 | 说明 |
| --- | --- | --- | --- |
| 1 | GASAttributeDATA | ✅ 完成 | Base/Current 双值 + 租约账页 + `evaluate()` 聚合权威 + 懒重算缓存 |
| 2 | GASAttributeSet | ✅ 完成 | `pre_attribute_change`（钳制）/ `post_gameplay_effect_execute`（连锁）/ 双信号 |
| 3 | GASAbilitySystemComponent | ✅ 完成 | 标签计数、效果账本（handle 门票）、能力管理、`_process` 心跳、依赖登记簿 |
| 4 | GASGameplayEffect + GASEffectSpec | ✅ 完成 | 三策略 + 周期 DoT + granted_tag + 两道门禁 + 捕获声明 + Stacking 全家桶 |
| 5 | GASGameplayAbility | ✅ 完成 | can_activate 四查 / activate + commit 分离 / push+pull 打断 / give_ability 校验站 |
| 6 | GASAbilitySpec | ❌ 有意不做 | 每个 `give_ability` 直接 `new()` 独立实例，状态挂资源实例上，不需要 Spec 层 |
| 7 | GASAbilityTask | ✅ 完成 | 基类 + Delay；WaitInput / WaitAnimNotify / WaitTargetData 排队中 |
| 8 | 执行器 / MMC | ✅ 完成 | magnitude 四类（ScalableFloat / AttributeBased / SetByCaller / SetByCaller×Attr）+ ExecutionCalculation + 双桶落账 |
| 9 | 依赖登记簿 | ✅ 完成 | 非快照属性依赖实时重算（簿挂被读属性的家，跨墙免拉线，环保护） |
| 10 | GameplayCue | ✅ 完成 | 第 21 节：事件流（邮局广播 + 小票 + ASC 三时刻钩子）、凭票制 Actor Cue（工厂 + add/remove + 存在性计数）、周期 GE 每跳 EXECUTED、手动 API 全部落地；WHILE_ACTIVE 有意不做（持续表现由凭票节点自身 _process 承担）；桌游演示：眩晕星星（凭票工厂）+ 伤害飘字（GE 自动 / 手动 API 双链） |
| 11 | TargetData | ⏳ 未开始 | 测试中目标仍是写死的引用 |
| 12 | 网络同步 / 预测 | ❌ 明确不做 | 单机项目，Godot 网络模型与 UE 差异过大 |

> 除了上表，还额外完成了：GameplayTags 插件（享元 + 多叉树 + 引用计数）、
> 测试场景 + F 键一键自动化回归。DEVLOG.md 记录了完整开发历程。

---

## 14. 参考资源

- [Tranek/GASDocumentation](https://github.com/tranek/GASDocumentation) - 最全面的第三方 GAS 文档
- [Epic 官方 GAS 文档](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-ability-system-for-unreal-engine)
- [GASShooter](https://github.com/tranek/GASShooter) - GAS 高级示例项目
- UE 源码: `Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/`
