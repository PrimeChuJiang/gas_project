# Gameplay Abilities System (GAS) — Godot 实现

基于 UE GameplayAbilitySystem 插件的 Godot 重写版本。

---

## 各模块一句话

| 模块 | 说明 |
|------|------|
| `enums.gd` | 枚举常量：DurationPolicy、ModifierOp |
| `attribute_data.gd` | 单个属性值，BaseValue + 临时 Modifier = CurrentValue |
| `attribute_set.gd` | 属性容器（Health、Mana...），提供 Pre 钳制和 Post 连锁 |
| `gameplay_effect_modifier.gd` | 一条修改指令：改哪个属性、什么操作、改多少 |
| `gameplay_effect.gd` | 效果配方（Resource）：瞬时伤血 / 持续Buff / 周期性Dot |
| `gameplay_effect_spec.gd` | GE 的运行时实例，拷贝定义层数据 + 携带 Context |
| `gameplay_effect_context.gd` | 效果来源信息：谁打的、用什么打的、打在哪 |
| `ability_system_component.gd` | **大脑**。执行 GE、管理 Tag、管理 Ability 生命周期 |
| `gameplay_ability.gd` | 技能配方（Resource）：冷却、消耗、标签限制、行为逻辑 |
| `ability_task.gd` | 异步节点（Node），_process 驱动，Ability 用它做延时/等待 |
| `ability_task_delay.gd` | 具体 Task 示例：等待 N 秒后触发回调 |

层次关系：

```
Resource 层（编辑器配置）:     GE, Ability
实例层（运行时拷贝）:           EffectSpec
执行层（驱动计算）:             ASC, AttributeSet, AttributeDATA
异步层（等待/延时）:            Task
通信层（跨系统标识）:            Tag
```

---

## 架构概览

```
编辑器 (.tres 资源)
  GASGameplayEffect (定义层, Resource)
    duration_policy (INSTANT / DURATION / INFINITE)
    duration / period
    modifiers: [GEModifier {attr_name, op(ADD/MUL/DIV/OVERRIDE), magnitude}]
    granted_tag (授予目标的标签)
    gameplay_cue_tags

  GASGameplayAbility (定义层, Resource)
    activation_required_tags / activation_blocked_tags (标签门禁)
    cost_ge (消耗 GE)
    cooldown_ge (冷却 GE，用 granted_tag 标记冷却状态)

运行时
  GASEffectSpec (实例层, RefCounted)
    引用定义、携带 Context
    提交给 ASC

  ASC.ApplyGameplayEffectSpecToSelf(spec)
    INSTANT: apply_base_value_change -> PostGameplayEffectExecute -> 结束
    DURATION:
        注册 modifier -> 写入 granted_tag -> 加入 _active_effects
        _process 倒计时 -> 到期 -> remove_modifier + 移除 tag
    INFINITE: 同上但不自动到期
              _process 处理周期性触发

  ASC.try_activate_ability(ability)
    can_activate() → 检查冷却/阻止/消耗
    activate() → 子类覆写行为
    commit_ability() → 应用 cost_ge + cooldown_ge
    end_ability() → 清理 Task、发信号

  GASAbilityTask (Node, 异步操作)
    _spawn(ability): 注入 ability 引用 + 挂场景树 + activate()
    _process 驱动具体逻辑（倒计时 / 等待输入 / 等动画）
    end_task(): 发 task_finished 信号 + queue_free()

  GASAttributeSet
    _attributes: {attr_name -> GASAttributeDATA}
    apply_base_value_change: Pre 门禁 -> 写 BaseValue -> 发信号
    apply_modifier / remove_modifier: 注册/移除 Modifier -> 发信号
    pre_attribute_change:   子类覆写，钳制 BaseValue
    post_gameplay_effect_execute: 子类覆写，连锁反应

  GASAttributeDATA (单个属性)
    base_value (永久值)
    _modifiers: [{handle, op, magnitude}] (临时修改器)
    current_value (只读计算: base + modifiers 按 ADD->MUL->DIV->OVERRIDE 聚合)
```

---

## Modifier 聚合公式

```
if override 存在 -> 直接返回 override 的值

result = base_value
result += 所有 ADD 修改器的 magnitude
for each MULTIPLY: result *= (1.0 + magnitude)
for each DIVIDE:    result /= (1.0 + magnitude)
```

---

## 完整链路：1.5秒延迟后造成 50 点火焰伤害

### 准备

```
策划在编辑器创建资源:
  ge_damage.tres      → INSTANT, Health ADD -50
  ge_cooldown.tres    → DURATION 3秒, granted_tag: Ability.Fire.Cooldown

运行时:
  hero 节点
    └─ ASC
         ├─ AttrSet (Health=500, Attack=100)
         └─ _abilities: [FireBoltAbility]
```

### 激活（按键 → 开始蓄力）

```
玩家按键
    │
    ▼
ASC.try_activate_ability(fire_bolt)
    │
    ├─► fire_bolt.can_activate()
    │      ├─ is_active? → false ✓
    │      ├─ cooldown tag 在 ASC 上? → 不在 ✓
    │      ├─ activation_blocked_tags 有命中? → 没配 ✓
    │      └─ cost 够? → 没配 ✓
    │      return true
    │
    ├─► fire_bolt.activate()
    │      is_active = true
    │      ability_activated.emit()
    │
    │   【子类 FireBoltAbility.activate() 内部】
    │      commit_ability()                 ← 扣蓝 + 打冷却标签
    │
    │      var task = GASAbilityTaskDelay.create(self, 1.5)
    │         │
    │         ├─► new() → 设 _duration=1.5
    │         ├─► _spawn(self)
    │         │      task.ability = fire_bolt
    │         │      ASC.add_child(task)     ← 挂场景树，_process 能跑了
    │         │      task.activate()         ← is_running=true, set_process(true)
    │         │      ability._active_task.append(task)
    │         └─ return task
    │
    │      task.task_finished.connect(_on_charge_done)
    │
    └─► ASC._active_abilities.append(fire_bolt)
```

### 倒计时 → 伤害落地

```
每帧 task._process(delta):      ← task 是 ASC 的子节点，和 GE 倒计时并行跑
    _timer += delta
    if _timer >= 1.5:
        set_process(false)       ← 停止无效帧调用
        end_task()
           is_running = false
           task_finished.emit()  ← 触发 FireBoltAbility._on_charge_done
           queue_free()          ← 从场景树自删

_on_charge_done(_task):
    ASC.apply_gameplay_effect_spec_to_self(ASC.make_effect_spec(ge_damage))
       │
       └─► INSTANT 路径:
              AttrSet.apply_base_value_change("Health", -50)
                 PreAttributeChange: clamp(450, 0, MaxHealth) → 450
                 set_base_value(450)
                 _evaluate() → 450
                 attribute_changed.emit("Health", 450, 500)
                    │
                    └─► UI 刷新: "生命：450"

              AttrSet.post_gameplay_effect_execute(spec)
                 （子类可覆写，处理死亡检测等）

    end_ability(false)
       │
       ├─► 遍历 _active_task → 无残留
       ├─► _active_task.clear()
       ├─► is_active = false
       └─► ability_ended.emit(false)
              │
              └─► ASC._on_ability_ended → 清理 _active_abilities
```

### 中断（蓄力中被取消）

```
ASC.cancel_ability(fire_bolt)
    │
    └─► fire_bolt.end_ability(true)
           │
           ├─► 遍历 _active_task
           │      task.is_running → true
           │      task.end_task()
           │         set_process(false)
           │         task_finished.emit()
           │         queue_free()
           │
           ├─► _active_task.clear()
           ├─► is_active = false
           └─► ability_ended.emit(true)
                  │
                  └─► ASC._on_ability_ended → 清理 _active_abilities

结果: 火球没放出来，冷却/消耗已扣（因为 commit_ability 在 Task 创建前就执行了）
```

---

## 最小示例

### 1. 创建属性集子类

```gdscript
class_name MyAttributeSet
extends GASAttributeSet

func pre_attribute_change(attr_name: StringName, new_value: float) -> float:
    match attr_name:
        &"Health":
            return clamp(new_value, 0.0, _attributes[&"MaxHealth"].base_value)
    return new_value
```

### 2. 初始化角色

```gdscript
var character = Node.new()
add_child(character)

var asc = GASAbilitySystemComponent.new()
character.add_child(asc)

var attr_set = MyAttributeSet.new()
attr_set.attributes = {&"Health": 500.0, &"MaxHealth": 500.0}
attr_set.initialize_attributes(asc)
asc.add_attribute_set(attr_set)
```

### 3. 在编辑器里创建 GE 资源

右键目录 -> New Resource -> 搜索 GASGameplayEffect，配置：

Duration Policy:  INSTANT
Duration:         0.0
Period:           0.0
Modifiers:
  - Attr Name: Health, Op: ADD, Magnitude: -50

保存为 ge_damage.tres。

### 4. 应用效果

```gdscript
var ge = load("res://ge_damage.tres")
var spec = asc.make_effect_spec(ge)  # 工厂造 spec：context 与 source_asc 自动填好
asc.apply_gameplay_effect_spec_to_self(spec)  # apply 时填 target_asc

print(attr_set.get_attribute_value(&"Health"))  # 450
```

### 5. DURATION 效果（Buff）

编辑器中配置：

Duration Policy:  DURATION
Duration:         5.0
Period:           0.0
Modifiers:
  - Attr Name: Attack, Op: ADD, Magnitude: 30

```gdscript
var ge = load("res://ge_buff.tres")
asc.apply_gameplay_effect_spec_to_self(asc.make_effect_spec(ge))

print(attr_set.get_attribute_value(&"Attack"))  # 比基础值 +30
# ...5 秒后...
print(attr_set.get_attribute_value(&"Attack"))  # 回退到基础值
```

---

## 设计与实现笔记

### 实现路径

```
第1阶段: 属性系统
    enums.gd → attribute_data.gd → attribute_set.gd
    验证: 修改 BaseValue → CurrentValue 自动重算 → 信号通知 UI

第2阶段: 效果系统
    gameplay_effect_modifier.gd → gameplay_effect.gd
    → gameplay_effect_context.gd → gameplay_effect_spec.gd
    验证: INSTANT 伤害、DURATION Buff、周期 Dot、Tag 授予/撤销

第3阶段: 能力系统
    gameplay_ability.gd → ability_task.gd → ability_task_delay.gd
    → ASC 新增 give_ability / try_activate_ability / cancel_ability
    验证: 瞬发伤害能力、延迟蓄力能力、冷却禁用、眩晕阻止激活

第4阶段: 测试与文档
    TestScene.tscn → 按键测试全部 GE 和能力
    README.md → 完整链路文档
```

### 为什么 Ability 不需要 Spec 层？

GE 的 Modifier 数值可能在运行时计算（如"造成 30% 攻击力的伤害"），需要 Spec 预先算出最终值再提交给 ASC。Ability 没有这个需求——它的行为写在子类的 `activate()` 覆写里，状态（`is_active`、`_active_task`）直接挂在 Resource 上。每个角色 `give_ability` 时都是 `new()` 出来的独立实例，不会共享。

### 为什么 activate 和 commit_ability 是分开的？

考虑一个蓄力技能：

```
按下按钮 → activate (开始蓄力动画)
           ↓
        如果中途被眩晕打断 → end_ability(true) → 没扣蓝、没进冷却
           ↓
        蓄力完成 → commit_ability (扣蓝 + 进冷却) → 放出火球
```

合在一起的话，按下去就扣蓝，蓄力被打断时玩家会骂"我都还没放出来凭什么扣我蓝"。简单技能（瞬发）在 `activate` 里紧接着调 `commit_ability` 即可。

### 为什么 Task 是 Node 而不是 Resource？

Task 需要 `_process` 来驱动倒计时、等待输入等异步逻辑，Resource 没有 `_process`。但它又不能由 Ability 直接 `add_child`（Ability 是 Resource），所以 Task 挂在 ASC 节点上，由 ASC 托管生命周期。

### 为什么不直接用 Timer 代替 Task？

Timer 只能等 N 秒。但技能需要的异步操作远不止计时：等待玩家再按一次攻击键（连招）、播放动画到第 N 帧触发伤害判定、等待目标进入攻击范围、以上任意步骤被打断时统一取消所有等待。Task 是一个统一的"异步操作"基类框架，Timer 只是其中一种子类。

### 为什么每个 Task 子类都要写 static create()？

GDScript 不支持泛型，基类无法提供一个通用的 `static func create()` 来 `new()` 正确的子类型。所以基类提供 `_spawn()` 承载通用逻辑（赋值 ability、挂场景树、activate），各子类的 `static create()` 只做两件事：`new()` 自己的类型 + 设自己的参数 + 调 `_spawn()`。

### Task 是按"异步模式"分类，不是按技能分类

```
GASAbilityTask (基类)
    ├─ GASAbilityTaskDelay        ← 所有"等 N 秒"的技能共用
    ├─ GASAbilityTask_WaitInput   ← 所有"等按键"的技能共用（未来）
    └─ GASAbilityTask_WaitAnim    ← 所有"等动画帧"的技能共用（未来）
```

不是每个技能写一个新 Task——大部分技能组合已有的 Task 就行，跟搭积木一样。

### 核心流转关系

**Tag 是神经系统**（跨模块标识：冷却、眩晕、Buff），**ASC 是大脑**（执行 GE、管理 Ability 生命周期），**GE 是激素信号**（修改属性 + 打标签），**Ability 是动作命令**（什么时候放什么效果），**Task 是时钟**（管"等多久"）。

---

## 下一步

- [ ] GameplayAbilities 测试（FireBolt 等具体能力类，接入 TestScene）
- [ ] GameplayCues (表现效果)
- [ ] ExecutionCalculation (执行器，复杂伤害公式)
- [ ] 引用计数的 TagContainer (多效果 Tag 叠加)
- [ ] 更多 Task 子类：WaitInput、WaitAnimNotify、WaitTargetData
