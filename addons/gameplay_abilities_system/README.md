# Gameplay Abilities System (GAS) — Godot 实现

基于 UE GameplayAbilitySystem 插件的 Godot 重写版本。

---

## 已实现的功能

| 模块 | 文件 | 说明 |
|------|------|------|
| 枚举定义 | `scripts/enums.gd` | DurationPolicy、ModifierOp |
| 属性单元 | `scripts/attribute_data.gd` | Base/Current 分离、Modifier 聚合、dirty 缓存 |
| 属性集 | `scripts/attribute_set.gd` | 属性容器、Pre/Post 回调、attribute_changed 信号 |
| 效果上下文 | `scripts/gameplay_effect_context.gd` | Instigator、EffectCauser、Origin、TargetData |
| 效果定义 | `scripts/gameplay_effect.gd` | Resource，策划可在编辑器内配置 |
| 效果修饰器 | `scripts/gameplay_effect_modifier.gd` | 单条 modifier：属性名、操作、数值 |
| 效果实例 | `scripts/gameplay_effect_spec.gd` | 运行时实例，携带定义 + 上下文 |
| ASC 核心 | `scripts/ability_system_component.gd` | 效果应用、Modifier 注册/移除、Tag 管理、周期/到期计时 |

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
var spec = GASEffectSpec.new(ge)
asc.apply_gameplay_effect_spec_to_self(spec)

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
asc.apply_gameplay_effect_spec_to_self(GASEffectSpec.new(ge))

print(attr_set.get_attribute_value(&"Attack"))  # 比基础值 +30
# ...5 秒后...
print(attr_set.get_attribute_value(&"Attack"))  # 回退到基础值
```

---

## 数据流全链路示例

以"收到 50 点火焰伤害"为例：

```
1. 策划创建 ge_fire_damage.tres (INSTANT, Health ADD -50)
2. 运行时: var spec = GASEffectSpec.new(load("res://ge_fire_damage.tres"))
3. asc.apply_gameplay_effect_spec_to_self(spec)
4. INSTANT 路径:
   - _find_attribute_set("Health") -> 找到 MyAttributeSet
   - attr_set.apply_base_value_change("Health", -50)
   - PreAttributeChange: clamp(500 - 50, 0, MaxHealth) -> 450, 合法
   - set_base_value(450)
   - _evaluate() -> 450
   - attribute_changed.emit("Health", 450, 500)
   - UI 刷新显示 450
   - post_gameplay_effect_execute(spec)
5. 结束
```

## 下一步

- [ ] GameplayAbilities (能力系统)
- [ ] AbilityTasks (异步任务)
- [ ] GameplayCues (表现效果)
- [ ] ExecutionCalculation (执行器，复杂伤害公式)
- [ ] 引用计数的 TagContainer (多效果 Tag 叠加)