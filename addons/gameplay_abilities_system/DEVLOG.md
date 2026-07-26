# GAS 开发日志 · 调试与重构专场（2026-07-18 ~ 07-22）

> 本文档记录一轮完整的 debug 之旅：三个被掩盖的真 bug、六个顺手根治的设计问题、
> 以及沉淀下来的九条框架设计原则。用于温故，也是后续开发的基线。

---

## 0. 这一轮的前后对比

| | 开始前 | 结束后 |
|---|---|---|
| Ability 登记 | activate 后才 append，瞬发技能留幽灵 | 先记账再放权 |
| Task 生命周期 | 自然结束不注销，跨帧访问尸体崩溃 | 唯一收尾漏斗 + 双信号 |
| INFINITE GE | 施加后永远无法移除 | handle 门票 + `remove_active_effect` |
| commit | activate 开头无脑扣费，取消照样进 CD | 蓄力后 commit，二次检查，可失败 |
| cost 检查 | 查无属性 = 免费放行（fail-open） | fail-closed + 报错 |
| 配置校验 | 无，错误配置静默失效 | `_can_give_ability` 检查站 |
| Tag | 布尔集合，两面盾退一面全没 | 引用计数 + 跳变沿信号 |
| 封装 | 外部直接摸 `asc._owned_tags` | 一律走 `asc.has_tag()` |

---

## 1. 三大 bug 修复记录

### Bug 1：幽灵条目（登记时序）

- **现象**：瞬发技能（activate 里同步 end_ability）结束后，`_active_abilities` 里永远留着它。
- **根因**：`try_activate_ability` 的顺序是 `activate()` → `append()`。activate 是用户代码，
  内部可以同步走完 end_ability → 信号触发 `_on_ability_ended` → 此时账本上还没这个人，删除失败 →
  随后 append 留下幽灵。
- **狡猾之处**：单技能反复测试时 size 恒为 1 —— 每次激活都在"清理上一个幽灵、制造一个新幽灵"，
  数字稳定得像正常值。换成两个瞬发技能交替激活，账本才真正开始增长。
- **修法**：`append` 提前到 `activate()` 之前。
- **原则**：★先记账，再放权 —— 框架自身的状态登记必须发生在调用用户代码之前，
  因为用户代码随时可能重入框架（UE：InternalTryActivateAbility 先标记激活再调 ActivateAbility）。

### Bug 2：Task 尸体（生命周期不变量）

- **现象**：一个能力开两个 Delay（0.5s / 10s），短的先自然死亡，之后 cancel 能力 →
  `Invalid access ... previously freed instance`。
- **根因**：`end_task()` 调了 `queue_free()`（拆房子）但没把自己从 `ability._active_task` 摘除（没撕纸条）。
  数组里的引用指向已释放节点，下一次遍历就撞上。
- **FireBolt 为什么从来没炸**：它唯一的 task 死亡瞬间能力也跟着死（同一调用栈内 clear 列表），
  尸体在列表里的时间不足一帧。
- **修法**：
  - `end_task(canceled: bool)` 成为唯一收尾漏斗：`set_process(false)` → `is_running=false` →
    **erase 自己** → emit（`task_finished` / `task_canceled` 二选一）→ `queue_free()`；
  - erase 必须在 emit 之前（信号回调可能调 end_ability 读列表 —— 原则★又来一次）；
  - `end_ability` 倒序遍历取消 task；末尾 `assert(_active_task.is_empty())` ——
    把静默兜底（clear）换成大声验尸；
  - `_spawn` 门禁：`ability.is_active == false` 时拒绝挂载并 `free()` 自己（拒绝入场要负责销毁，
    否则不挂树不释放 = 泄漏）。
- **原则**：★生命周期不变量 —— 登记列表里躺着的必须恰好是活着的对象；
  任何死亡路径都要维护它；N 条死亡路径 → 1 个清理漏斗。
- **额外收获**：取消不发"完成"信号（否则被打断的火球照样掉血）。
  `task_finished` / `task_canceled` 对应 UE 的 OnFinish / OnCancelled 双委托。

### Bug 3：Effect Handle（门票机制）

- **现象**：`apply_gameplay_effect_spec_to_self` 返回 void，INFINITE GE（装备、光环）施加后永远无法移除。
- **设计推导**：
  1. 按 GE 资源移除是伪需求 —— GE 是**定义**（配方），`_active_effects` 里是**施加实例**（菜）。
     两枚同款戒指 = 同一配方两盘菜，"脱左手"要移除的是那一次施加；
  2. 不返回 entry/spec 引用 —— Bug 2 的教训：外部持有生命周期不归自己管的引用 = 尸体风险。
     handle 是**门票**：账本独占数据，外人持票查询，查不到优雅返回 false；
  3. 旧票 false 不是错误 —— buff 自然到期后装备才被脱下，拿旧票来退是正常业务
     （**双重移除无害化**）。持票方可以完全不关心票的死活，系统因此解耦；
  4. INSTANT 返回 `INVALID_HANDLE (-1)` —— 打完即散，无票可发。
     UE 对照：`FActiveGameplayEffectHandle`（包装 int 求类型安全；GDScript 务实用裸 int + 常量）。
- **修法**：
  - apply 的 DURATION/INFINITE 分支开头取号并立刻递增（"使用"和"递增"不分离）；
  - `remove_active_effect(handle) -> bool`：**先验票**（找 entry，找不到 return false 零副作用）→
    erase → `_cleanup_effect(entry)` → true；
  - `_cleanup_effect(entry)` 独揽全部清理（modifier + tag + 信号），到期路径与主动移除共用。
- **踩过的坑（回归 bug）**：第一版 erase 之后调 `_remove_effect(handle)` 回账本查条目 ——
  刚删掉的条目当然查不到，**tag 泄漏**（眩晕标签永不消失）。
  **原则**：★数据当参数传，不要删了账再回账本查（use-after-remove）。
- **测试为什么当时没抓到**：只盯了攻击力数字（modifier 按 handle 扫属性集，不依赖条目），
  tag 状态在 UI 里不可见。→ 补了 TagsLabel。★不可观察的状态等于没测。

---

## 2. 顺手根治的设计问题

### 2.1 commit 时机 + CQS 拆分

- FireBolt 原来 activate 开头就 commit，取消蓄力照样进 CD —— 和自己 README 里的设计论证矛盾。
- commit 挪到蓄力完成（`_on_charge_down` 开头），失败则 `end_ability(true)` + return，伤害不落地。
- `can_activate` 拆成四块积木谓词：`_check_cooldown` / `_check_cost` / `_check_block` / `_check_required`。
  `can_activate` = `!is_active` + 全部四块；`commit_ability` = cooldown + cost 两块 + 付费，返回 bool。
- **为什么 commit 不能直接调 can_activate**：第一条 `if is_active: return false` 在 commit 时刻必然为
  true —— 永远付不了费。硬证据：两个函数问的不是同一个问题。
- **原则**：★查询与命令分离（CQS）—— 检查是只读幂等的，随时可查；付费是命令，只做一次且
  必须基于当下状态。"1.5 秒前查过了"对命令没有意义。
- **为什么 commit 不查 blocked tags**：眩晕该在发生瞬间**主动打断**技能（push），
  而不是在付费关口被动等着被查到（pull）。资源类条件（蓝/CD）只能 pull → 归 commit；
  状态类条件（眩晕/沉默）是事件 → 归 tag + cancel 机制。（"眩晕打断进行中技能"已列入 TODO）

### 2.2 fail-open vs fail-closed

- cost 检查查无属性（角色没有 Mana）时原来静默放行 → 技能永久免费，配置错误隐形。
- **原则**：★区分"查询返回否定答案"（tag 不在容器里 = 没被眩晕，是答案）和
  "查询本身无法成立"（属性不存在，是事故）。只有后者需要 fail-open/closed 抉择；
  付费/权限关口一律 fail-closed + 大声报告。
- ASC 的 apply 路径对无属性目标保持宽容（合法场景存在）但要留日志痕迹 —— 付费从严，施加从宽。

### 2.3 give_ability 检查站

- `_can_give_ability`：cooldown_ge 必须有 granted_tag 且必须是 DURATION；cost_ge 必须是 INSTANT；
  拒绝重复 give。give_ability 返回 bool。
- **为什么冷却必须 DURATION**：冷却靠 granted_tag 存在一段时间来工作，而 INSTANT 路径根本不处理
  granted_tag → INSTANT 冷却 = 永远无冷却。
- **为什么消耗必须 INSTANT**：消耗是永久性支付（改 BaseValue）；DURATION 的 cost 是临时
  modifier，到期蓝自动回来 = "借蓝放技能"。
- **原则**：★duration_policy 是 GE 语义的载体，不是随便选的；
  ★配置校验压在装载边界一次做完，运行时检查只回答"现在能不能"。
- **教训**：第一版把规则写反了（要求冷却是 INSTANT），会当场拒绝自己的 FireBolt ——
  ★改完门禁代码必须立刻跑正常流程，门禁最容易犯的错是把好人拦在门外。

### 2.4 Tag 引用计数

- **现象**：两面风暴之盾，脱一面 tag 全没；双眩晕，第一个到期提前解控。
- **根因**：`_owned_tags` 是布尔集合，"被授予 2 次"在写入时被压扁成"在"，删除时无从恢复。
- **修法**：ASC 内 `_tag_counts: Dictionary {FGameplayTag: int}`（享元唯一实例可安全做键）：
  - `_add_owned_tag`：0→1 时 emit(added)，否则只 +1 不发信号；
  - `_remove_owned_tag`：-1 后归零才 erase + emit(removed)；超还（还不存在的 tag）= 不变量被
    破坏，error 大声报告；
  - `has_tag` 保持**层级匹配**（遍历键 `matches_tag`）——
    精确查找会丢掉"持有 State.Debuff.Stun 时查询 State.Debuff 应命中"的语义。
    （UE 的 FGameplayTagCountContainer 把祖先计数一并维护实现 O(1)，留作日后优化）
- **决策**：不改 `FGameplayTagContainer` —— 它是配置容器（@export + 序列化桥接），集合语义正确；
  计数是 ASC 的运行时状态。两种身份不混进一个类。
- **原则**：★多方共享的状态要计数（借出 2 次，还回 2 次才归零）；
  ★信号只在 0↔1 跳变沿发 —— 订阅者要的是"存在性变了"，不是"有人动了它"。

### 2.5 封装

- `gameplay_ability.gd` 三处直接 `asc._owned_tags.has_matching_tag(...)`，
  内部结构一换全部编译失败 —— 全部改走 `asc.has_tag(tag)`。
- UI 不摸 `_tag_counts`，只靠 `gameplay_tag_changed` 信号维护自己的副本。
- **原则**：★外部代码只走公共 API；内部换实现，外部无感知。

---

## 3. 九条原则速查（背下来）

1. **先记账，再放权** —— 框架状态更新先于用户代码；emit 前完成 erase。
2. **唯一收尾漏斗 + 漏斗幂等** —— N 条退出路径汇入 1 个清理函数（end_ability / end_task / _cleanup_effect）；
   漏斗自身必须经得起被走两次，重复调用安静滑过（end_ability 开头的 is_active 闸，2026-07-22 补全）。
3. **生命周期不变量 + 配对** —— 谁登记谁注销；所有 Ability 路径的终点必须是 end_ability。
4. **门票代替引用** —— 跨系统持有的凭据用 ID，不用对象引用；旧票优雅 false。
5. **fail-open vs fail-closed** —— "查询无法成立"才需要抉择；付费关口从严 + 大声报告。
6. **查询与命令分离（CQS）** —— 检查随时做，命令只做一次且基于当下。
7. **校验压在边界** —— 配置合法性在装载时查一次；被复用的谓词里不写调用方视角的日志。
8. **计数 + 跳变沿** —— 多方共享的状态用引用计数；信号只在存在性真正改变时发。
9. **数据当参数传** —— 清理函数吃 entry，不删后回查；遍历中会被回调修改的集合：
   只删当前元素时倒序够用；回调可能任意增删时用快照 + 点名前查活（2026-07-22 补全）。

---

## 4. 测试基建现状

场景：`test/TestScene.tscn` + `test_gameplay_effect.gd`（手动按键驱动）

| 按键 | 用例 |
|---|---|
| 1 | INSTANT 伤害 -50 |
| 2 | DURATION 攻击 buff（自然到期回退） |
| 3 | DoT 中毒（周期触发） |
| 4 | 大额伤害（Pre 钳制到 0） |
| 5 | 眩晕（tag 授予/到期撤销；连按两次 = 双眩晕计数用例） |
| 6 | 火球全流程 / 蓄力中再按 = 取消（不进 CD 不扣蓝） |
| 7 | 瞬发 GA（Bug 1 幽灵条目回归） |
| 8 / 9 | 多 task 能力 / 取消（Bug 2 尸体回归） |
| 0 / Minus | 风暴之盾 apply（存 handle）/ 按票移除（连按 0 两次 = 双实例用例） |
| Equal | 旧票重试（期望 false） |

UI：HealthLabel / AttackLabel / StatusLabel / **TagsLabel**（信号驱动，tag 状态可视化）。

已知的测试债：`assert(true, ...)` 无意义断言未清；自动化断言路径（原 test_instant/test_duration
函数）被注释，长期应恢复为可一键回归。

---

## 5. 明天的任务：火系技能冷却缩短 30%

### 先解开"套了好多层"的晕

睡前的直觉是"在 GE 上又加 modifier"—— **不对，而且好消息是：不需要任何新机制**。
把三个角色摆开，每个都是你已有的积木：

```
┌─ 装备"疾风戒指"（普通的 INFINITE GE）
│    modifier: CooldownReduction  ADD  +0.3     ← 就是最普通的属性 modifier！
│    （给 AttributeSet 新增一个 CooldownReduction 属性，初始 0）
│
├─ 火球的 cooldown_ge（不变，还是 DURATION 3 秒）——这是"配方上的标准冷却"
│
└─ commit_ability 里创建冷却 spec 的那一刻：
     spec.duration = cooldown_ge.duration * (1.0 - asc读到的CooldownReduction)
     = 3.0 * (1 - 0.3) = 2.1 秒                  ← 唯一的新代码就这一行的思路
```

也就是说：
- "冷却缩短"**不是**改冷却 GE 本身，而是一个**属性**（CooldownReduction），
  装备用你写了几十遍的普通 modifier 去加它；
- 唯一的新动作发生在 **Spec 创建时刻**：把定义层的静态 duration，
  按当下属性值折算成运行时 duration 再提交。

### 这正是 Spec 层存在的意义

README 里你自己写过："GE 的数值可能在运行时计算，需要 Spec 预先算出最终值"——
写下这句话时 Spec 只是定义层的无脑拷贝，**明天它第一次真正干活**。
UE 对照：冷却时长用 ScalableFloat/MMC（ModifierMagnitudeCalculation）从属性读取，
计算发生在 MakeOutgoingSpec 时刻。链路完全同构。

### 建议实现步骤

1. `TestAttributeSet` 加 `CooldownReduction: 0.0`（顺手加 `MaxMana`，之前欠的）；
2. 做一个 `ge_swift_ring.tres`：INFINITE，CooldownReduction ADD +0.3；
3. `commit_ability` 里创建 cooldown spec 后、apply 前，按属性折算 `spec.duration`
   （注意 clamp：CDR ≥ 1.0 会算出 0 或负冷却，想清楚上限策略，比如封顶 0.7）；
4. 测试：无戒指放火球 → 3 秒 CD；穿戒指 → 2.1 秒 CD（掐表或打日志看 tag 消失时刻）；
   脱戒指（handle 移除）→ 恢复 3 秒；
5. 思考题（做完再看）：折算逻辑写死在 commit_ability 里，还是抽成 spec 的
   "运行时数值计算"通用入口？后者是通往 MMC/SetByCaller 的门。

### 顺带的收官小活

- commit 时把 cooldown 的 handle 存在 ability 上（`_cooldown_handle`）——
  "刷新冷却" = `asc.remove_active_effect(_cooldown_handle)` 一行；
  旧票无害化兜底，不需要任何失效通知。
- README 更新（第 2 节列的五处）。

---

## 6. 后续路线图

1. **眩晕打断进行中技能**：Ability 加 `cancel_with_tags`；`_add_owned_tag` 的 0→1 跳变时
   扫描 `_active_abilities` 主动 cancel（push 式打断落地）；
2. **EffectContext 接入**：ASC 加 `make_effect_spec()`（对应 MakeOutgoingSpec），
    spec 携带 source_asc → 通往"30% 攻击力伤害"（MMC / SetByCaller）；
3. **GameplayCue**：`gameplay_cue_tags` 目前无人消费；
4. **Stacking**（连按 2 无限叠 buff 是已知未实现）；
5. 更多 Task：WaitInput（连招）、WaitAnimNotify；
6. 小优化备忘：tag 祖先计数 O(1) 查询；周期效果首跳是否立即
    （UE 默认 bExecutePeriodicEffectOnApplication = true，当前实现是首个周期后才跳，属设计选择）。

---

## 7. 复盘：冷却缩短 30%（2026-07-19 完成）

### 落地的东西

- `commit_ability` 里开了两个虚函数缝 `_make_cooldown_spec` / `_make_cost_spec`（基类 = 无脑拷贝），
  折算公式（读 CooldownReduction、clamp）写在游戏层 FireBolt 的 override 里——**插件提供机制，游戏提供策略**；
- clamp 策略：乘数钳在 `[0.5, 1.0]`——冷却最多缩 50%，负 CDR 不延长冷却；
  （2026-07-22 修订：上限放宽到 2.0——负 CDR 允许把冷却拉长至两倍，为"冷却延长"类 debuff 预留。）
- `_cooldown_ge_handle`：commit 时存票根，初始化为 `INVALID_HANDLE`（不让 int 默认值 0 成为协议外的第三种状态）；
- 脱戒指恢复冷却是 modifier 架构**白送的**：`_cleanup_effect` 撤 modifier → CDR 自动归零，零额外代码；
- TestAttributeSet 补了 Mana ↔ MaxMana 钳制。

### 这轮想通的原则

- **handle 是无记名票根**：ASC 只承诺"凭票精确退场"，语义由持票人保管（装备系统记槽位票，ability 记冷却票）。
  谁 apply，谁在现场记票——过了现场，两个同 GE 实例无法区分（两枚相同戒指问题）。
- **可见性三受众**：类自己 / 子类（下划线字段可碰，≈protected）/ 外界（只许调方法）。
  公开字段是一份没打算签的合同（Hyrum's Law）——外界要的是"信息"（get_cooldown_remaining），不是"票"。
- **pre_attribute_change 不是没用**：600 伤害打 500 血不变负数就是它干的。但它只守 BaseValue 写入（INSTANT/周期路径），
  **modifier 路径（buff→current_value）绕过它**——UE 的完整答案是两个钩子
  （PreAttributeBaseChange 守 base / PreAttributeChange 守 current，聚合器重算也触发）。
  当前只有前者，所以 CDR 封顶只能钳在**使用侧**（override 里）。存储侧钳 current 记入备忘。
- pre 答"这个值可以是多少"（纯函数防递归），post 答"这次改动引发什么"（连锁决策）——不是假活和真活。

### 遗留

- spec `_init` 加了 context/source_asc/target_asc 可选参数——目前全是死管道，等 `make_effect_spec()` 填活；
- 思考题未答：Health 钳制用 MaxHealth 的 base_value，+200 最大生命 buff（改 current）不会抬高上限——该用哪个？
- modifier 路径的 pre 钩子（存储侧钳 current_value）→ 并入小优化备忘。

---

## 8. 复盘：属性上限联动（2026-07-19 晚完成）

### 落地的东西

- pre 钳制上限从 MaxHealth/MaxMana 的 **base_value 改为 current_value**——"+200 最大生命"装备（modifier 改 current）能真正抬高治疗上限；
- **上限缩水压顶**：TestAttributeSet 监听自己的 `attribute_changed`，Max 属性缩水时经
  `attribute_map`（Max→被压属性的映射表）算出 delta，**走 `apply_base_value_change` 漏斗**回调——
  信号、pre 钳制自动跟上（第一版直接 `set_base_value` 绕漏斗，UI 会静默失联，已纠正）；
- 新增 `attribute_initialized` 信号：初始值宣告与变化信号分离（不编造 old_value=0，飘字系统不会开局 "+500"）。
  **契约：监听者必须在 initialize_attributes 之前连接**；迟到者用 get_attribute_value() 拉取——初始状态用拉，后续变化用推；
- `initial_attributes` / `_attributes` 加 typed Dictionary 标注，配置字典改名与运行时字典区分（定义层→运行时层，GE→Spec 同纹理）；
- 重复 initialize 用 `_initialized` 守卫 + 报错（不静默吞）；
- 测试场景：Q/W/E 新键位，新增 heal_50 / add_max_health GE 与 MaxHealth 显示。

### 这轮踩的坑（都值得温故）

1. **抽函数抽丢了映射**：把两个 match 分支合并成 `_shrink_to_max(attr_name,...)` 时，
   "MaxHealth→Health" 的映射被蒸发，函数拿 Max 自己既当尺子又当布——条件恒 false，功能静默死亡。
   教训：**重构完必须重跑刚建好的测试**；"一个变量一个含义"。
2. **双负号 `a - - b`**：藏在 Mana 分支，被 pre 钳制掩护得测试全绿。教训：漏斗兜底是保险不是许可；日志要打中间值（delta）。
3. **"代码一样所以免验"不成立**：双负号恰好只在"看起来一样"的副本里。
   正确动作不是辩论而是重构——DRY 让对称性从"信念"变成"结构"，Health 的测试才真正覆盖 Mana。
4. delta 公式：压顶修正量 = 新上限 − 被压属性 current（不是 Max 自己的变化量）；带 modifier 的 Health 也能正确压顶。

### 遗留（明天热身清掉）

- `_on_attribute_changed` 的 match 臂 `&"MaxHealth", &"MaxMana"` 与 attribute_map 的键是同一份信息两处维护——
  改为 `if attribute_map.has(attr_name)` 让 map 当唯一事实源；
- `attribute_map` → `const _attribute_map`（内部 + 不可变）；
- `ge_add_max_mana.tres` 冒烟 Mana 接线（已提三次！）；
- 全量回归重跑一遍（含 E 键 CDR 2.1s）确认无回归。

---

## 9. 明天的课：眩晕打断进行中技能（push 式打断）

### 问题本质

`_check_block` 是**门禁（pull）**：只在激活那一刻查一次。火球蓄力中眩晕落下——门禁早查完了，
火球照样打出伤害。**先复现这个盲区**（蓄力中按 "3" 上晕），看到 bug 活着再动手。
修复换方向：不让技能轮询"我还能继续吗"，而是**事件找上技能（push）**——
眩晕 tag 出现的瞬间，扫一遍进行中的技能，该断的断。基建全是现成的：
`_tag_counts` 的 0→1 跳变沿 = "出现的瞬间"，`cancel_ability` = "断"。UE 对照：监听 Stun tag delegate → CancelAbilities。

### 实现步骤

1. `GASGameplayAbility` 加 `@export var cancel_with_tags: FGameplayTagContainer`（默认 new()，对齐其他字段防空引用）；
2. ASC `_add_owned_tag` 的 **0→1 分支里**（只在这个分支）扫 `_active_abilities`，命中 cancel_with_tags 的 cancel 掉；
3. 层级匹配方向：上 `State.Debuff.Stun`、技能声明 `State.Debuff` 也该断——matches_tag 谁调谁，和 has_tag 对齐，用具体例子推；
4. FireBolt 配 `State.Debuff.Stun`。

### 必想的三个坑

- **边遍历边删**：cancel 会动 `_active_abilities`——遍历 duplicate() 副本（想想为什么这里副本比倒序稳）；
- **重入推演**：cancel → end_ability → 信号回调若又动 tag，`_add_owned_tag` 重入——纸上推一遍为什么不死循环；
- **push/pull 是搭档**：打断管"屋里的"，门禁管"进门的"——检查 FireBolt 的 block 配置里有没有 Stun，缺一边都是洞。

### 验证清单

1. 蓄力中上晕 → task 取消、`ability_ended(true)`、**伤害没落地**；
2. 晕中叠晕（1→2）→ 不触发第二次扫描、无重复 cancel；
3. 晕到期（1→0）→ 恢复可施放；
4. 没配 cancel_with_tags 的技能（multi_task）不受影响；
5. 晕中按火球 → 门禁拒之门外（pull 侧健在）。

---

## 10. 复盘：眩晕打断进行中技能——push 式打断与漏斗幂等（2026-07-22 完成）

### 热身清理（attribute_map 收官）

- match 臂删除后，`has()` 的**含义变了**（注意：不是"还是原来的意思"）：
  原来是**断言**——match 在前面把关，"查不到 = 不变量被破坏"，配 error；
  删掉 match 后，**每一个**属性变化（Attack/Health/Mana）都涌进 `_on_attribute_changed`，
  `has()` 变成**路由**——"不在 map 里"是 Attack 的正常答案，必须静默流过。
  代码一个字没变，调用方契约变了，else 从"大声验尸"翻成"必须沉默"。
  它同时是防递归的闸：压顶引发的 Health 变化重入时在这里被无声挡下。
- error 的家搬到 `initialize_attributes`（装载边界）：配置对不对开局查一次，
  运行时路径里不该有"配置错了"的分支（原则 7），而不是每次运行相关逻辑都报一次。
- 德摩根翻车两次（加了 not 没翻 and）后拆成两个独立 if：不用背取反规则，
  且 key/value 各自精确报错、双缺双报，debug 时直接知道是哪一侧缺了谁。
  复杂布尔条件的一种修法是把它拆到不需要德摩根。

### 落地的东西

- `cancel_with_tags`：声明 ability 会被哪些 tag 打断；里面存宽泛值，
  做后续精确 tag 调 `matches_tag` 时的参数（具体的调、宽泛的当参数，与 has_tag 方向一致）；
- `_add_owned_tag` 仅 0→1 分支扫描：1→2 时 tag 一直存在，没有"出现"这个事件；
  且屋里不可能有可断对象——0→1 那次已清场，之后门禁一直守着（不变量由 push/pull 合力维护）；
- 扫描走 `cancel_ability` 漏斗：它的 `has()` 账本检查恰好就是快照模式的"点名前查活"，
  快照里的过期条目被无声挡下；命中即 break——断一次就够，剩下的 tag 不用再比；
- `end_ability` 幂等闸：开头非激活态直接 return（详见下方"漏斗幂等"）；
- 两处日志顺序修正（ability_task_delay / end_ability）：日志在动作之前打；
- FireBolt 配齐 block + cancel 双侧，五条验收全绿。

### 活体实验：push/pull 各守半场

只配了 `cancel_with_tags`、没配 `activation_blocked_tags` 时，先上晕再按火球：

```
[DEBUG][15:40:05][TestScene]:5
[DEBUG][15:40:05][TestScene]:6
[INFO][15:40:05][GameplayAbility]:Ability activated      ← 晕中照样起手
[INFO][15:40:07][AbilityTask]:Task ended, queue_free
[INFO][15:40:07][GameplayAbility]:Cost & cooldown applied ← 全程施放完成，伤害落地
```

- **push 是事件（跳变沿）**：只在 tag 出现那一瞬扫一次屋，管不了**之后才进屋的**——
  晕中起手时，跳变沿早已过去；
- **pull 是状态检查（门禁）**：只在激活那一刻查一次，管不了**进门之后才发生的事件**；
- 分工一句话：push 管"事件发生时屋里已有的"，pull 管"状态存在期间想进门的"——
  缺任何一边都是洞。这次是先亲手漏了球（上面这段日志）才补上的。

### 这轮想通的原则

- **快照 + 点名前查活 vs 倒序**（并入原则 9）：倒序安全的前提 = 遍历中的删除**只发生在当前元素**
  （end_ability 取消自己的 task 满足）；这里 cancel 触发的信号回调可能**任意增删**
  （连锁结束别的技能、激活新技能入账），前提即崩。快照冻结点名名单，
  `cancel_ability` 的 `has()` 负责查活——过期条目优雅跳过，正是门票机制那套"旧票无害化"。
  并入原则 9 的理由：同是"回调会动集合"的应对，has 查活本身也是一次验票。
- **跳变沿是递归的自然刹车**：一轮级联 = 一次源头事件**同步**引发的整条嵌套调用链
  （上晕 → 扫描 → cancel → end_ability → task 回调 apply 虚弱 GE → 重入 `_add_owned_tag`，
  全在同一个调用栈里走完）。级联中 tag 计数只升不降（到期扣减在之后的 `_process` 帧），
  同一 tag 第二次 apply 必然是 1→2——无跳变沿，扫描不触发，递归链在此断掉。
  跳变沿不只是省性能：它保证同一个 tag 在一轮级联里只能点燃一次扫描。
- **漏斗幂等（原则 2 补全）**：闸在 `end_ability` 第一行，非激活态直接 return。
  不装闸的三桩账：① `ability_ended` 发两次，"一次激活对应一次结束"的契约碎裂；
  ② 外层倒序循环的 range 按进门时的 size 算死，二次进入清空列表后索引越界崩溃；
  ③ 崩溃点与病根隔两层信号回调，debug 时先冤枉 task。
  修调用点是低级修法——防得了这个调用方，防不了窗口期里的下一个；
  所有死亡路径都汇进漏斗，闸就装在漏斗嘴上。
  注意分清两道刹车：**没有闸，递归也不会无限**（刹车是跳变沿）；闸保的是上面三条命。
- **日志在动作之前打**：倒叙日志误导时序判断——修正前读起来是"task 先死、能力后知后觉"
  （Cancelling task 出现在 Ending ability 之前）；修正后
  Ending ability → Cancelling task → Task ended，与真实调用栈的展开顺序一致。

### 踩的坑

- **`@export` 字段名会序列化进 .tres**：cancle → cancel 必须趁只有一两个资源时改——
  等二十个技能资源都存着旧属性名，改名后 Godot 加载对不上号，配置**静默丢失**
  （不只是"写代码难受"的问题）；
- **"账本里有但 is_active 已 false"的窗口期**：不是测试撞出来的，
  是推演"技能被打断时给自己上一层 debuff"这个合法玩法需求时推出来的——
  框架的闸为将来任何用户代码而装，信号回调是交出去的话筒，别人喊什么管不着，框架自己得站稳。

### 验收记录

| # | 用例 | 结果 | 证据（日志时间戳） |
|---|---|---|---|
| 1 | 蓄力中上晕 → 断、伤害不落地 | ✓ | 15:39:10 task 取消；无 "Cost & cooldown applied"，commit 根本没发生 |
| 2 | 晕中叠晕不二次扫描 | ✓ | 15:39:12~22 连按 5，无扫描、到期无 remove 报错 |
| 3 | 晕到期恢复施放 | ✓ | 16:10:01 两次被拦 → 16:10:02 激活成功 |
| 4 | 未配 cancel_with_tags 的 multi_task 免疫 | ✓ | 15:39:34 上晕，task 2 活到 15:39:43 自然善终 |
| 5 | 晕中按火球被门禁拦下 | ✓ | 15:41:44 / 15:41:46 `_check_block = false`（补配前 15:40:05 漏球，见活体实验） |

### 遗留

- `FGameplayTagContainer` 缺反方向查询方法（"容器里有没有把 query 收进范畴的"），ASC 暂时手伸 `_tags`；
- 测试文件残留 `cancle_tags` / "cancled" 拼写；
- `end_ability` 闸口静默 return vs 打 debug 日志：暂定静默（对齐"旧票无害化"），
  开发期如需排查"谁在重复调我"再加。

---

## 11. 下一课：EffectContext 接入与 make_effect_spec()

### 问题本质

目前所有 GE 数值都是配置里写死的静态 magnitude——"火球 -50"。但"造成**施法者攻击力 30%** 的伤害"
这句话没法配：数值取决于**谁**施的法、施法时他的属性是多少。spec 的 `_init` 里躺了两轮的
context / source_asc / target_asc 死管道，就是为这一刻留的。

### 三个角色

- **EffectContext**：这次施加的"案发现场"——至少记 source_asc（谁干的）；
- **`asc.make_effect_spec(ge)`**：ASC 上的 spec 工厂（UE：MakeOutgoingSpec）——
  造 spec 的同时把 context 填进去。今后"我要施加一个效果"都从这里出货，
  而不是散落各处的 `GASEffectSpec.new(ge)`；
- **运行时数值计算**：发生在 **spec 创建时刻**——和 CDR 折算完全同纹理
  （第 7 节的 `_make_cooldown_spec` 虚函数缝就是先例），这次读的是 source 的 Attack。

### 动手前必想的思考题

1. **快照时机**："30% 攻击力"在哪个时刻读攻击力——创建 spec 时（快照）还是 apply 到目标时（实时）？
   具体场景：火球出手瞬间攻击 buff 还在，飞行 0.5 秒后 buff 到期才命中——伤害按哪个算？
   两种答案都是合法设计（UE：snapshot vs non-snapshot），但必须**想清楚并写下来**；
2. **工厂的归属**：make_effect_spec 为什么长在 ASC 上而不是 GE 上？（提示：context 里的 source 是谁？）；
3. **旧调用点迁移**：现有的 `GASEffectSpec.new(ge)` 散在哪几处？全部改走工厂，还是允许两条路并存？
   （回忆"唯一收尾漏斗"的论证，入口和出口同理。）

### 验证目标

无 buff 火球伤害 = 基础值；攻击 buff 下伤害按 30% 折算变大；buff 到期后恢复
——中间那条能同时验证快照时机的选择。

### 更远的门

这条链路打通后，MMC（ModifierMagnitudeCalculation）和 SetByCaller 就只是
"把折算公式从子类 override 挪进可配置对象"的一步之遥。

---

## 12. 复盘：EffectContext 接入与 make_effect_spec()——管道通水（2026-07-22 完成）

### 三道思考题的最终答案

- **快照 vs 实时**：本课选**快照**。实现位置就是选择本身：spec 在 `activate` 起手时由
  `_make_damage_spec` 创建，Attack 在创建那一刻读进 modifier 副本，`_snapshot_spec` 字段
  持有到命中——此后 buff 怎么变都与这发火球无关。实时（若做）则是把读属性挪到 apply 时刻、
  从 `context.source_asc` 现查——这个选项在管道通水前**根本写不出来**：apply 那一瞬手里只有
  spec，源 ASC 无处可查。取舍的经验法则：**离手即定，持续附着**——效果离开施法者独立存在
  （弹道/火球）→ 快照，出手那刻的攻击力决定威力，飞行途中施法者掉 buff 甚至死了火球也不缩水；
  效果持续挂在源与目标的关系上（灼烧光环"每秒攻击力 10%"）→ 实时，攻击涨了灼烧就该变疼。
  UE 把这个选择做成 bSnapshot 交给策划，我们目前"写在哪就是哪"（见遗留）。验收 #4 就是给
  这个选择拍的毕业照。
- **工厂的归属**：`asc.make_effect_spec(ge)` 里调用方没传 source，但 source 填上了——
  它就是 `self`。**工厂的位置本身是一条数据**：方法长在谁身上，"谁干的"就自动已知，
  想忘都忘不了。换成 GE 方法或静态函数，source 立刻退化成一个**可能忘传的参数**，
  null 源会散布到每个调用点。无源效果（熔岩烫脚）的正确姿势是裸 `GASEffectSpec.new(ge)`——
  语义是**无源**而非非法；不能为了这 1% 的场景把主路退回静态工厂，让 99% 的有源场景
  重新暴露在忘传风险里。主路自动填、侧门显式走，侧门的存在不等于主路要降级。
- **迁移策略**：全迁（代码十八处 + README 三处）。与出口漏斗的论证**不对称**在强制力：
  出口收拢得住——所有死亡路径汇进 `end_ability`，闸装在框架自己的代码里，硬拦；
  入口拦不住——GDScript 没有私有构造函数，禁不了用户写 `GASEffectSpec.new(ge)`。
  焊不死的门只能靠三件软功夫：① 自己的代码全迁，库里 grep 不到一个反例（示范）；
  ② README 示例全部改走工厂（文档只教一条路）；③ 给裸 new 定下"无源"的合法语义——
  它从"另一条等价的路"变成"特殊场景的专用门"，用户裸 new 时知道自己在做什么。

### 落地的东西

- `asc.make_effect_spec(ge)` 工厂（UE：MakeOutgoingSpec）：new 一个 context，
  填 `instigator = owner_actor`、`effect_causer = avatar_actor`，连同 `self`（source_asc）
  一起交给 `GASEffectSpec.new(ge, context, self)`——今后"施加效果"都从这里出货；
- `apply_gameplay_effect_spec_to_self` 开头补 `spec.target_asc = self`——工厂填 source，
  apply 填 target（见下方原则）；
- 旧调用点十八处全迁工厂，README 三处示例同步改；
- FireBolt 的 `_make_damage_spec` 缝：与第 7 节 `_make_cooldown_spec` 同纹理的虚函数缝，
  读 source 的 Attack，`基础值 + 0.3×Attack` 折进 modifier 副本的 magnitude
  （改在副本上，.tres 配方仍是唯一事实源）；
- 快照挪到 `activate`：spec 创建即快照，`_snapshot_spec` 字段持有 1.5 秒蓄力，
  `_on_charge_down` 里 commit 通过后 apply；
- null 双门闩：生产者 `_make_damage_spec` 查 ge / attr_set，失败即 error + return null；
  消费者 `activate` 查到 null 即 `end_ability(true)`；apply 侧另有 null 检查返回
  INVALID_HANDLE 兜底；
- `ge_damage_base_attack.tres` 配方归位：基础伤害 -50 写在资源里，代码只做折算不写死数值。

### 这轮想通的原则

- **工厂填 source，apply 填 target**：一句话——**在信息第一次可知的时刻填**。
  起手那刻 source 已知（就是 self），但 target 是谁？火球还没命中，答案可能是 0.5 秒后
  撞上的任何人。法球飞行的空窗期里，spec 处于"有源无靶"的**合法中间态**，target 只能等
  命中那刻由 apply 补上。两个时刻两个填法不是随意的工程安排，是两条信息到位时刻不同逼出来的。
- **改副本，不另起炉灶**：`spec._init` 里 `mod.duplicate()` 拍副本，因为 GE 资源按引用共享——
  直接改 magnitude 会污染下一次施放的计算。"扣 30 血"那版的病根是**配方被架空**：
  数值绕开 .tres 在代码里另起炉灶，策划改配置全部落空。折算必须**改在配方的副本上**——
  配方仍是唯一事实源，代码只负责在副本上做加工。
- **报错必须带拦截**："装了警报器没装门闩" = 打完 `GameLogger.error` 继续往下走——
  日志喊完 "ge is null" 代码接着用这个 null，崩在别处或带病算出错账。fail-closed 完整两句：
  **报错的那一行必须同时中止当前操作；失败停在最近的合法状态，不许带病前行。**
  警报器和门闩必须成对出现，只响不拦等于没装。
- **谁生产 null，谁的调用方就得消费 null**：`_make_damage_spec` return null 后，
  若 activate 不查，null 存进 `_snapshot_spec` 字段安静躺 1.5 秒，雷在 `_on_charge_down`
  的 apply 调用里才炸——**炸点与病根隔一个字段 + 一次 task 回调 + 1.5 秒**，debug 会先
  冤枉 task（与第 10 节"崩溃点与病根隔两层信号回调"同纹理）。return null 是把责任推给
  调用方的契约，签了就得让**最近的**调用方立刻兑现（查到 null 即 end_ability）。
- **代码与文档不能静默分家**：CDR 的 clamp 上界代码是 2.0、文档写 1.0，拖了四轮才对账。
  为什么比两边都错更危险：两边都错，读者迟早撞上矛盾会起疑去验证；一对一错，
  信文档的人带着错误认知写代码——且**不一致本身不报错**，没有任何机制提醒，
  信任被静默消耗。对账必须是提交动作的一部分，不能靠"以后想起来"。

### 踩的坑

- **"扣除 30 血"是审讯线索，不是成功证明**：日志里 -30 看着像"折算生效了"，
  逐项对账才现形——期望 80 = 基础 50 + 折算 0.3×100；30 恰好只等于折算项，
  基础 50 压根没进账 → 反推配方是空的，spec 里根本没有 .tres 的那条 -50。
  修法即"配方归位 + 改在副本上"。教训：**数字要逐项对账**，"有数字出来"证明不了链路对，
  每一项都得能指认自己从哪来。
- **验票和用票必须是同一个对象**：早先版本 `find_attribute_set` 查了两遍——验的是第一次
  的返回值，用的是第二次的，两次查询之间没有任何一致性保证。查一次存局部变量，
  验它、用它是同一个对象。另：GAFireBold → GAFireBolt 拼写趁引用少改掉（同 cancle 教训——
  @export 序列化进 .tres 的名字，拖越久改越痛）。

### 验收记录

| # | 用例 | 期望 | 结果 / 判决性证据（完整日志见当轮控制台，表内只留定罪行） |
|---|---|---|---|
| 1 | 无 buff 火球 | -80（50 + 0.3×100） | ✓ 14:20:01 Health 405→325 = -80（Attack 100）——与 #3 同一事件兼作基线，见下方取证说明 |
| 2 | 攻击 buff(+50) 下 | -95（50 + 0.3×150） | ✓ 14:19:47 上 buff（Attack 100→150）→ 14:19:53 起手 → 14:19:55 Health 500→405 = -95 |
| 3 | buff 移除后 | 回 -80 | ✓ 14:19:59 Minus 移除 buff（Attack 回 100）→ 14:20:01 Health 405→325 = -80 |
| 4 | **快照专项**：起手后命中前 buff 消失 | 仍 -95 | ✓ **毕业照**：14:20:06 上 buff（Attack 150）→ 14:20:08 起手（快照定格）→ 同秒 Minus 移除（Attack 已回 100）→ 14:20:10 Health 325→230 = **-95**——出手时刻的攻击力说了算 |
| 5 | 回归：冷却 2.1s / 扣蓝 / 眩晕打断 | 全正常 | 扣蓝 ✓ Mana 1000→900→800→700（每发 -100）；冷却 ✓ 14:07:50 进 CD → 14:07:52 `_check_cooldown = false` 被拦 → 14:07:59 通过（秒级粒度与 2.1s 相容，精确取证已在第 7 节做过）；眩晕打断 ✓ 14:26:12 起手 → 14:26:13 上晕即断（Cancelling task、无 "Cost & cooldown applied"，Health 500 / Mana 1000 分文未动）→ 晕过后 14:26:20 恢复施放，14:26:21 落地 -80（500→420）、扣蓝 -100——顺带把 #1 的无 buff 基线独立取证了一次 |

取证说明：

- 第一轮（14:06~14:08）日志没带属性打印，只有生命周期行——"流程跑通"证明不了数值，
  **有过程无结论，不作数**；第二轮（14:19~14:20）补上属性打印重跑，上表全部数字证据出自这轮
  （又一次"不可观察的状态等于没测"）；
- 测试用 Minus 手动移除 buff 替代"自然到期"：两条路径汇入同一个 `_cleanup_effect` 漏斗，
  对折算读数等价；
- #1 与 #3 共用 14:20:01 那次事件（405→325）：既是"移除后回落"也是无 buff 基线——
  严格分离需冷启动首发取证，暂记等价。

### 遗留

- `world_origin` / `target_data` 仍无消费者；2D/3D 向量适配等第一个真实需求（范围伤害）再定；
- `context.ability` 字段未填——工厂看不见"哪个能力造的我"，等有消费者时再接（可能的方案：
  能力侧造 spec 后自己补，或 make_effect_spec 加可选参数）；
- 快照/实时目前是"写在哪就是哪"，还没做成 GE 上的配置开关（UE bSnapshot）——MMC 课的素材。

---

## 13. 下一课：MMC 与 SetByCaller——把公式变成数据

### 问题本质

看你的两道缝：`_make_cooldown_spec` 里的 CDR 折算、`_make_damage_spec` 里的 30% 攻击折算——
**同一个模式已经复写了两遍**："spec 创建时刻，用代码改数值"。公式硬编码在 GDScript 子类里，
后果有三：① 策划改个系数 0.3→0.5 要找程序员；② 每个新技能都要 override 一遍同构代码；
③ 快照/实时的选择埋在"代码写在哪"里，配置上看不见。
MMC 这课干的事一句话：**把折算公式从代码挪进 .tres，让 magnitude 从一个 float
升级成一个会算的对象**。UE 对照：FGameplayEffectModifierMagnitude。

### 四种弹药（magnitude 家族）

UE 的 modifier magnitude 有四种计算方式，我们做其中三种（第四种看完就知道为什么放弃）：

- **ScalableFloat（静态值）**：就是现在的裸 float——"-50"。已有，要做的是让它成为家族一员而非特例；
- **AttributeBased（属性折算）**：`(coefficient × (属性值 + pre_add)) + post_add`——
  火球的 `-80 = (-0.3 × (Attack:100 + 0)) + (-50)`。带 **snapshot 开关**（本课主菜）；
- **SetByCaller（调用方传值）**：配置里只留一个 key，数值由代码在运行时塞进 spec——
  "蓄力越久伤害越高"这类**配置时刻根本不可知**的数；
- ~~CustomCalculationClass~~（自定义计算类）：GDScript 里它和"写个子类 override"没有本质区别，
  等 ExecutionCalculation 课一起说。

### 动手前必想的思考题

1. **公式归谁所有**：折算公式现在住在能力子类里，它到底是谁的知识——能力的？GE 的？
   还是 modifier 的？（提示：想想"两枚同款戒指"那套定义/实例论证——公式跟着**配方**走还是跟着
   **这一次施加**走？）想清楚后回答：为什么 magnitude 要从 float 变成 **Resource**？
   这次分层和 GE→Spec 的分层是不是同一个纹理？
2. **snapshot 开关落在哪、两条读取路径各在哪一行执行**：snapshot=true 时在谁的哪个函数里读属性？
   snapshot=false 时呢？（呼应第 12 节：实时读取为什么必须等 apply？target-based 的
   AttributeBased——"按目标防御折算"——为什么**只能**是实时？）；
3. **SetByCaller 没人喂值怎么办**：key 用 StringName 还是 tag？调用方忘了 set 值，
   apply 时查无此 key——fail-open（当 0 用）还是 fail-closed？（重温原则 5 的判据：
   这是"查询返回否定答案"还是"查询本身无法成立"？UE 的答案是 default value + 大声警告，
   你可以不同意，但要写出你的理由。）

### 实现路线提示（顺序即依赖）

1. `GASModifierMagnitude` 基类（Resource + 虚函数 `calculate(spec) -> float`），
   三个子类各占一个文件；`GEModifier.magnitude: float` 换成新类型——
   **旧 .tres 的迁移方案先想好再动手**（cancle 改名的教训：@export 类型一换，存量资源怎么办）；
2. spec 管道接上：谁在什么时刻调 `calculate`？（snapshot 路径和实时路径**不是同一个调用点**）；
3. `ge_damage_base_attack.tres` 改配 AttributeBased(-0.3, Attack, post_add=-50)，
   **删掉 FireBolt 的 `_make_damage_spec` override**——缝还在（别的技能可能用），火球不再需要它；
4. SetByCaller 用例自选，最小可验即可（一个手动传值的测试键就够，不必做完整蓄力系统）；
5. `set_by_caller` 的存取 API 长在 spec 上（想想为什么不是 GE 上——第 12 节同款问题）。

### 验证目标

1. **回归即基线**：第 12 节验收表 #1/#2/#4 原样重跑全绿（-80 / -95 / 快照仍 -95）——
   重构成功的定义是**行为一个数都没变**；
2. **策划工作流**：只改 .tres（0.3→0.5），不碰任何 .gd，伤害变 -100；
3. **snapshot 开关**：同一个 GE，只翻开关重跑 #4——snapshot=false 时毕业照场景应变成 -80
   （实时读到掉 buff 后的 100）。**一个开关翻出两种合法设计，才算真正做完了第 12 节的遗留**；
4. SetByCaller：传值生效 + **不传值时的 fail 路径有日志取证**（你思考题 3 的答案落在代码里）。

### 更远的门

AttributeBased 只能读**一个**属性；"伤害 = 攻击 × 暴击 − 目标护甲"这种多属性攻防结算，
就是 ExecutionCalculation 课的活。Stacking 在它后面排队。

---

*本轮结束时代码状态：EffectContext + make_effect_spec 管道通水（代码在 commit `ce469c5`，
本次提交补第 12 节复盘与验收取证）。验收 5/5 全绿，快照折算毕业照已拍（14:20:10 仍 -95）。
下一课：MMC / SetByCaller——把 `_make_damage_spec` 里的折算公式从子类 override 挪进可配置对象，
快照/实时做成 GE 上的 bSnapshot 开关。*

---

## 14. 复盘：MMC 与 SetByCaller——把公式变成数据（2026-07-25 完成）

（复盘由 Claude 代笔，骨架取自用户在对话中的两次口头复述——SetByCaller 完整链路 +
is_snapshot 时序推演，均自行讲对。这是第二次代笔，下节复盘归还用户。）

### 三道思考题的最终答案

- **公式归谁所有**：归**配方**（modifier）。magnitude 从 float 升级成 Resource 后，
  公式跟着 .tres 走，策划改系数不再碰 .gd（验证 2 取证）。分层与 GE→Spec 是同一个纹理：
  **Resource = 定义，共享、无状态；Spec = 实例，每次施放各一份**。这条纹理立刻回答了
  本课最关键的架构问题——SetByCaller 的字典为什么必须住 spec 不能住 magnitude：
  magnitude 是共享 Resource，两枚同时飞行的火球引用**同一个**对象，数值存它身上第二发
  一 set 就覆盖第一发（"两枚同款戒指"论证第三次出场）。最终分工：
  **magnitude 管"去哪读"（data_key），spec 管"存了什么"（信箱）**——配方写"取抽屉 A 的数"，
  抽屉长在每一次施放上。
- **snapshot 开关落在哪**：`is_snapshot()` 在这条管道里实际控制的是**"何时 resolve"**——
  true = `GASModifierSpec._init`（即 `make_effect_spec` 时刻）当场结算；
  false = apply 里的 `resolve_all()` 补算。target-based 的属性折算只能实时，
  因为 `_init` 时刻 target 还不存在（第 12 节"工厂填 source、apply 填 target"的直接推论）。
- **SetByCaller 没人喂值**：fail-open——`default_value` + `GameLogger.warn`。
  判据（原则 5）：信箱本身存在、只是没人投递，属于"查询返回否定答案"而非"查询无法成立"；
  与 UE 同款（default + 大声警告）。key 用 StringName，够用且与属性名同风格；
  UE 用 GameplayTag 的层级校验优势暂不需要（记入遗留）。验证 4-Y 键对 fail 路径做了日志取证。

### 落地的东西

两个阶段，第一阶段在 commit `29f8f4e`，第二阶段本次提交：

- **magnitude 家族**：`GASModifierMagnitude` 基类（Resource + 无状态纯函数
  `calculate(spec) -> float`），三个子类各占一文件——ScalableFloat（裸值入家族）、
  AttributeBased（`coefficient × (属性 + pre_add) + post_add`，带 snapshot 开关）、
  SetByCaller（`data_key` + `default_value`，`is_snapshot` 恒 false）；
- **GASModifierSpec 运行时账页**：持配方引用 + `resolved`/`value`，
  `duplicate()` 改副本的旧方案退休；
- **两条 resolve 路径**：`spec._init` 结算快照类，apply 的 `resolve_all()` 补算实时类——
  第 12 节遗留的"快照/实时写在哪就是哪"正式变成配置开关；
- **缝的清理**：FireBolt 删 `_make_damage_spec` override（公式进 .tres），
  `_check_cost` 改走 `_make_cost_spec` 缝，存量 .tres 十个全部迁移；
- **SetByCaller 三件套**：spec 信箱 `set_by_caller: Dictionary[StringName, float]`、
  存取 API `set_setbycaller_magnitude` / `get_setbycaller_magnitude`（缺失 warn + default）、
  `GASModifierMagnitudeSetByCaller`；
- **验证 4 测试键**：T（塞 -77 断言生效）/ Y（不塞值断言走 default 0 + 警告）。

### 这轮想通的原则

- **数值按出生地分三类**：配置表里就定死的 → ScalableFloat；随角色状态变的 → AttributeBased；
  只在本次施放过程中才产生的 → SetByCaller（蓝猫滚了多远、枪械距离衰减、蓄了多久）。
  推论即分工纪律：**SetByCaller 传"事实"，magnitude 配"公式"，游戏逻辑永远不该知道公式长什么样**——
  代码只报告"飞了 1700 码"，"每百码折多少伤"是策划在配方里的事。
- **snapshot 对 SetByCaller 是范畴错误**：快照开关回答的是"数据在 t0 和 t2 都存在，读哪个时刻"——
  攻击力有得选。SetByCaller 的值出生在 t1（t0 造 spec 之后、t2 apply 之前），
  t0 时刻它压根不存在，"要不要快照"成了"要不要拍一张空气的照片"。
  这就是 UE 里 SetByCaller 根本没有 snapshot 概念的原因——snapshot 是属性捕获专属的词。
  值来得最晚，resolve 就必须选最晚的时刻。
- **resolved 即定案，无人补救**：`resolve_all` 跳过 `resolved == true` 的账页。
  is_snapshot=true 实验（有意为之）取证：错误时刻 resolve 会把 default 记成死账，
  之后塞进信箱的 -77 **不是晚到，是永远被无视**——信箱里躺着值，账已在 `_init` 用 0 记完。
  快照的本质是"过了这个时刻，后面发生什么都与我无关"，威力与危险同源。
- **混合公式的出路**：距离×攻击力这类"事实×属性"，UE 靠第四类 CustomCalculation 打通
  两条隔离管道；本项目基类签名 `_calculate(spec)` 拿得到完整 spec（信箱 + source_asc 属性），
  管道天然是通的——写个子类即可。下一课的加餐。

### 踩的坑

- **Inspector 实验残留污染共享配方**：实验 SetByCaller 时顺手把
  `ge_damage_base_attack.tres` 的 magnitude 存成了 SetByCaller(charge_time)，三层后果：
  ① 第 12 节回归基线（-80/-95）被静默击穿；② 符号反转——charge_time=1.7 是正数，
  火球变成给目标**加** 1.7 血；③ 裸事实（秒数）未经公式直接当 Health 增量，
  正是"传事实不传公式"的反模式。git checkout 复原。教训两条：
  **.tres 是共享事实源，实验完必须对账 git status**；
  **配方被改过之后，此前的"验证全绿"取证全部作废**——本轮验证 1 因此重跑。
- **防线站在解引用之后等于没有防线**：`set_setbycaller_magnitude` 那行插在了
  `make_effect_spec` 赋值与 null 检查**之间**——若工厂返回 null，崩在防线前一行。
  已修（塞值挪到检查之后）。null 检查的位置纪律：**第一次解引用之前**。

### 验收记录

| # | 用例 | 期望 | 结果 |
|---|---|---|---|
| 1 | 回归基线（29f8f4e 当轮） | 行为一个数不变 | ✓ -80 / -95 / 快照 -110 |
| 2 | 策划工作流：只改 .tres 系数 | 伤害变 -100 | ✓ 不碰 .gd |
| 3 | 翻 snapshot 开关重跑毕业照 | 实时读到新值 | ✓ -125 |
| 4-T | SetByCaller 塞 -77 | 血量 -77 | ✓ 断言过 |
| 4-Y | 不塞值 | default 0 + 控制台警告 | ✓ 血量不动，警告在案 |
| 附 | is_snapshot=true 反证实验 | T 键失效、只捞 default+警告 | ✓ 断言炸，符合推演 |
| 附 | .tres 复原后 #1 复跑 | -80/-95 回归 | ✓ 用户确认 |

取证说明：本节验收粒度不如第 12 节——#1 复跑与 4-T/4-Y 为口头确认，未存档带时间戳的
控制台日志。按"不可观察的状态等于没测"的标准这是欠账，记入遗留；数字本身经逐项对账无疑点。

### 遗留

- FireBolt `activate` 里 `set_setbycaller_magnitude(&"charge_time", 1.7)` 现为死代码
  （配方复原后无人读此 key）——**故意留下**，下一课加餐直接把它变活；
- 测试文件 docstring 里旧 float magnitude 示例待清；
- SetByCaller 的 key 用 StringName 未用 tag——等 tag 校验有真实需求再换；
- 本节验收欠一份带时间戳的日志存档；
- AttributeBased 只能读一个属性——ExecutionCalculation 课的正题。

---

## 15. 下一课：ExecutionCalculation——多属性攻防结算（加餐先行：第四类 magnitude）

### 问题本质

modifier 管道的形状是**"算一个数，改一个属性"**：一条 modifier 读若干输入、产出一个
magnitude、以一种 op 写一个属性。三类 magnitude 只是"这个数怎么来"的三种答案，
形状本身没变。但真实的攻防结算长这样：

> 伤害 = (攻击 × (1 + 暴击率 × 暴击伤害) − 目标护甲) × 属性克制系数

读**源的三个**属性、读**目标的一个**属性、混合快照与实时、可能同时写 Health 和
附带一个吸血写源的 Health——这个形状塞不进任何 magnitude。UE 的答案：
`UGameplayEffectExecutionCalculation`——GE 上挂一个**执行类**，声明要捕获哪些属性
（RelevantAttributesToCapture），apply 时刻一次算完，可产出**多条** modifier。
一句话：**magnitude 是"一个数的公式"，execution 是"一次结算的公式"**。

### 加餐先行（半小时量级）

第 13 节放弃的第四类 CustomCalculationClass 先补上：写 `GASModifierMagnitudeChargeDamage`
（名字自定），`_calculate(spec)` 里读信箱的 `charge_time` × 从 source 捕获的 Attack ×
`@export` 系数——FireBolt 里那行死代码就地复活。做完你会亲手证明两件事：
① `_calculate(spec)` 签名下信箱与属性两条管道本来就是通的；
② 它和 execution 的差距只剩"读目标属性"和"写多个属性"——正课的动机自然浮现。

### 动手前必想的思考题

1. **execution 和 magnitude 的边界**：都是"代码算数"，为什么要两个概念？
   如果给 magnitude 加上"能读目标"，它能取代 execution 吗？
   （提示：一条 modifier 只有一个 op、一个 attr_name——吸血"写两个人的 Health"卡在哪一层？）
2. **捕获声明是代码还是数据**：execution 要读 Attack/CritChance/目标 Armor，
   "我要读什么"写死在 `_calculate` 里，还是像 UE 一样声明成列表交给系统？
   声明换来了什么？（提示：系统不知道你的依赖，就无法帮你做快照捕获，
   更无法在 Stacking/聚合课里做"依赖变了要重算"。）
3. **目标属性在哪个时刻才可读**：execution 必须等 apply（第 12 节结论的又一次复用）。
   那 DURATION + period 的 DoT 呢——每跳都重新执行一遍吗？源的 Attack 捕获快照、
   目标的 Armor 每跳实时，**同一次结算里混两种时序**，账怎么记？

### 实现路线提示（顺序即依赖）

1. 加餐（自定义 magnitude 子类）先做，热身 + 立靶子；
2. 测试场景先立**木桩**：第二个角色挂 ASC + Armor 属性——目前测试全是
   `apply_to_self`，攻防结算逼着源/目标真正分家（EffectContext 终于双向都有戏份）；
3. `GASExecutionCalculation` 基类（Resource，虚函数拿 spec 算出"输出集合"）；
   GE 上加挂载点；apply 管道里给它一个执行时刻——想清楚它和 modifiers 数组的
   执行顺序谁先谁后；
4. 输出怎么表达："一组 (attr_name, op, magnitude)" 的临时 modifier？
   直接改属性？想想哪种走法能复用现有的 modifier 结算管道；
5. 第一个真实用例：`伤害 = 攻击 − 目标护甲`（先别上暴击，两个属性先把管道打通），
   验证改木桩 Armor 伤害跟着变。

### 验证目标

1. 加餐：蓄力 1.7s 火球伤害 = charge_time × 系数 × Attack，改系数只动 .tres/Inspector；
2. 木桩回归：对木桩施放现有火球，-80/-95 基线在"真目标"身上重现（source≠target 首次取证）；
3. 攻防结算：`攻击 100 − 护甲 20 = -80`，只改木桩 Armor（20→50），伤害变 -50；
4. 时序专项：DoT 版攻防结算，中途给木桩上护甲 buff——每跳实时读 Armor 的证据。

### 更远的门

execution 产出的 modifier 与常驻 modifier 如何合账（多个 buff 同时改 Attack 谁说了算）——
聚合器（Aggregator）；同一 GE 叠加 N 层——Stacking。都在 execution 之后排队。

---

*本轮结束时代码状态：SetByCaller 三件套 + 验证 4 + is_snapshot 反证实验完毕，
MMC 课全部验证目标达成，本次提交关账（含第 14 节复盘）。charge_time 死代码故意留作
下一课加餐的靶子。下一课：ExecutionCalculation 多属性攻防结算，加餐 CustomCalculation 先行。*

---

## 16. 复盘：ExecutionCalculation——多属性攻防结算与 DoT 实时结算（2026-07-26 完成）

（骨架 Claude 搭，思考题答案与坑的心理现场取自用户口头复述、Claude 誊写。
第 1 题口头版把 execution 和 magnitude 的方向说反了一次，纠正记录在正文——
这正是复盘该抓的东西。）

### 三道思考题的最终答案

- **execution 和 magnitude 的边界在产出端宽度**。两个函数签名就是判决书：
  `calculate(spec) -> float` 返回**一个数**，塞进**一条** modifier 的坑位——一个
  attr_name、一个 op，写谁由 apply 决定，这才是"单值、单方向"；
  `_execute(spec) -> Array[GASModifierEvaluatedData]` 返回**一摞小票**，每张自带
  receiver（TARGET/SOURCE）、attr_name、op、value——多值、多方向。吸血卡在 magnitude 的
  **产出端**：就算开放读目标，返回值也只有一个 float、一个坑位，"源也要回血"的第二笔账
  没有座位。边界不在读端——加餐的第四类 magnitude 已证明信箱与属性两条读管道本来就通。
  （口头复述时两词说反，被签名当场纠正。）
- **捕获声明买的是"系统看得见你的依赖"**。声明成数据（挂在配方上的列表）而非硬读在
  `_calculate` 里，换来两样：① 系统能替你**逐个依赖**在正确时刻拍快照——`is_snapshot`
  开关就是最小号的捕获声明；② 失效重算的入场券——聚合器课里 DURATION 的 magnitude
  依赖 Attack，Attack 变了系统得知道找谁重算，读死在代码里系统是瞎的。一句话：
  **声明住配方，捕获值住账页**。本项目 execution 目前硬读（UE 的
  RelevantAttributesToCapture 未做），记入遗留。
- **同一次结算混两种时序不乱，是因为住址不同**。快照值在 `make_effect_spec` 时刻
  结算进 spec，跟着 spec 飞两秒也不变；实时值每跳 `_execute` 现场从属性集读。
  DoT 的每一跳都是**完整重跑一遍配方**，把"t0 的账"和"这一跳的现场"混合——
  本轮实测 Armor 中途变、下一跳立即变，就是"现场读"的取证。要快照哪个输入，
  在 spec 里预折算即可，机制已备。**引擎给确定性（每跳同一执行时刻、快照值恒定），
  语义归配方（哪个输入走哪种时序是配方作者的声明）。**

### 落地的东西

两个阶段，第一阶段在 commit `e1e1d7d`，DoT 站本次提交：

- **加餐**：`GASModifierMagnitudeSetByCallerTimesAttribute`（第四类 CustomCalculation，
  信箱 charge_time × source Attack × `@export` 系数，is_snapshot 恒 false）+
  `ge_damage_charge.tres`——FireBolt 里躺了两课的 charge_time 死代码复活；
- **木桩**：test 场景第二角色 npc（asc_npc + 完整 TestAttributeSet + Armor），
  source/target 首次真正分家，EffectContext 双向都有了戏份；
- **`apply_gameplay_effect_spec_to_target`**：空检查 + 一行转发
  `target_asc.apply_..._to_self(spec)`——第一版复制了 25 行双漏斗被重写，
  两份漏斗必然分叉，转发壳只此一家；
- **`GASModifierEvaluatedData` 小票**：receiver / attr_name / op / value——
  配方只开票，落账归 ASC；execution 与结算管道之间的唯一通货；
- **`GASExecutionCalculation` 基类**（Resource，`_execute(spec)` 虚函数）+
  GE 的 `executions` 独立挂载点，与 modifiers 数组并列；
- **执行时刻法条**：INSTANT 分支 modifiers 之后、post_execute 之前；周期跳里
  modifiers 之后、post_execute 之前（与 INSTANT 同构）；period <= 0 的
  DURATION/INFINITE 拒收 executions（warn + 忽略，判决理由见原则第一条）；
  执行顺序定死 modifiers 先 executions 后，跟 UE；
- **`_run_executions(spec)` 漏斗**：INSTANT 与周期跳两个调用点才抽（一处不抽的纪律）；
  参数就一个 spec，因为落账要的三样东西都在它身上——executions 列表、`_execute` 的
  入参、SOURCE 行跨墙用的 source_asc。"spec 啥都能拿到"不是理由，逐项点名才是；
- **三个测试键**：O（INSTANT 攻防结算）、P（`ge_dot_execution`：DURATION 5.01s +
  period 0.5s + modifiers 空 + 只挂 execution，UE 伤害 GE 标准形态的 DoT 版）、
  A（`ge_add_armor`：DURATION 1s 的 +10 护甲 buff，对照实验的手术刀）。

### 这轮想通的原则

- **幽灵 modifier 判决书**：DURATION 挂 execution 被拒，是因为聚合器式 modifier 用
  target 的 handle 记账，SOURCE 行会把 modifier 写进别人家的 AttributeSet，而
  `_cleanup_effect` 只扫自己家——到期清不掉。周期跳合法，是因为每跳走
  `apply_base_value_change` 一次性落账，写完就完，案发条件不存在。
  **同一个功能，换一种落账方式，罪名就不成立。**
- **apply 时刻 ≠ 落账时刻**：周期 GE 在 apply 时只入册（`_active_effects` 登记簿），
  第一跳在 period 秒后由 `_process` 心跳触发。INSTANT 养出的"apply 是唯一入口"直觉
  在这里是陷阱——动笔前先问：**这个 GE 的落账时刻在哪。**
- **账本唯一出处**：同一个判断全项目只认一个字段。`spec.period` 是 resolve 后的
  运行时账页，`spec.effect_def.period` 是配方原件——混用则将来 spec 级改写
  （急速缩短跳间隔）时读错账。
- **名实相符**：`_calc_evaluated_data` 改名 `_run_executions`——"calc"暗示纯计算
  无副作用，而它跑配方、改属性、落账满地。读名字就该知道它会动属性。
- **假口供**：warn 文案第一版写成 "only support period == 0"，与新法条正好相反。
  错误日志是给凌晨三点的自己看的证词，方向写反比不写更害人。
- **对照实验的数值设计**：三段各要一个独一无二的数字（-20 / -10 / -20 弹回），
  两个假设才会预测不同结果。护甲 buff 若 +40 会触发白卷条款归零，而"每跳 0"和
  "DoT 停了"在日志上同貌——实验设计要避开歧义读数。

### 踩的坑

1. **execution 放进了 DURATION 的 apply 分支**。现场：DoT 只在 apply 瞬间结算一次，
   之后每跳血不动。心理现场（最值钱）：忘了 DURATION 走 `_process` 主动调用，
   顺着"apply 是唯一入口"的惯性放到了最直接的地方。修法：调用移入
   `_apply_periodic_effect`，apply 分支只留 warn。新反射见原则第二条。
2. **`ge_add_armor.tres` 忘设 duration_policy**。现场：Armor 80→90→100→110→120
   单调上涨永不回落，最后两次 P 全场静默。诊断：没写就吃默认值 INSTANT，
   +10 直接写进 base value——根本不是 buff，是永久改造；护甲焊到 120 ≥ Attack 后
   每跳交白卷，无变化即无日志。教训：**.tres 里没写的字段也是配置**，
   INSTANT 是本插件 GE 的缺省人格；以及白卷静默与"DoT 坏了"同貌，见原则第六条。
3. **warn 文案说反**（假口供，见原则第五条）；顺手堵了 period 负数静默滑过的缝
   （条件 `== 0` 改 `<= 0`）。
4. **第一阶段的复制粘贴三连**（e1e1d7d 当轮）：npc 的 attr_set 认错主人
   （asc→asc_npc）、tag 信号接错、npc handler 刷错 label——复制成对出现的代码，
   错也成对出现。

### 验收记录

| # | 用例 | 期望 | 结果 |
|---|---|---|---|
| 1 | 加餐三连（e1e1d7d 当轮） | 蓄力 -85 / 改系数 -170 / is_snapshot=true 反证 warn 提前两秒 | ✓ |
| 2 | 木桩回归 I 键 | -80 在真目标重现；npc Attack=50 差异化仍 -80（读 source） | ✓ |
| 3 | O 键 INSTANT 攻防 | Armor 50/-50、80/-20、120/0 血不动；差异化证明读 target | ✓ |
| 4 | O 键漏斗抽取后回归 | 三连一个数不变（重构安检门） | ✓ |
| 5 | DoT 基线 | 每跳 -20 × 2 | ✓ |
| 6 | 中途上甲 | 上甲后**下一跳**立即 -10（快照假设预测 -20 不变，死刑一） | ✓ |
| 7 | 到期弹回 | buff 1s 后每跳弹回 -20 × 6，Armor 回 80（快照假设预测 -10 继续，死刑二） | ✓ |
| 附 | 总账 | 总伤 180 = 500−320；10 跳 = 5.01s ÷ 0.5s，一跳不丢 | ✓ |
| 附 | 到期现场 | "血不动、Armor 90→80"单独成行 = `_cleanup_effect` 摘聚合器 modifier 的铁证 | ✓ |
| 附 | 侦探记 | 第一轮"消失的第 10 跳"实为白卷（当时 Armor 100 = Attack 100）；账能对平 | ✓ |

取证说明：本节 DoT 实验留了带时间戳的完整控制台日志（20:48 一轮），
补上了第 14 节"验收欠日志存档"的欠账。

### 遗留

- INSTANT 结算无视 op 的旧债（modifier 循环同罪）——聚合器课一并清算；
- execution 目前 ADD-only（非 ADD error + continue）、捕获声明未做
  （RelevantAttributesToCapture）——都是聚合器课解禁的门；
- warn 文案还欠半句后果说明（executions ignored）；
- 测试 docstring 旧 float 示例待清；GameplayTagsManager 启动日志
  "加载 6 个/注册总数 0"两行打架待查；
- 下一课排队：聚合器（Aggregator）→ Stacking → GameplayCue。

---

*本轮结束时代码状态：ExecutionCalculation 课全部验证目标达成（含第 15 节验证目标 4 的
DoT 时序专项），本次提交关账（含第 16 节复盘）。下一课：聚合器（Aggregator）——
execution 产出的 modifier 与常驻 modifier 如何合账，op 旧债与 ADD-only 限制届时清算。*
