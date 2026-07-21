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

> 你来写。括号里是引导问题，写完删掉。规矩同第 10 节：自己的话，能贴日志贴日志。

### 三道思考题的最终答案

- **快照 vs 实时**：（各自的实现位置在哪？"离手即定 / 持续附着"的经验法则；
  实时选项为什么在管道通水前根本写不出来？）
- **工厂的归属**：（为什么是 ASC 实例方法而不是 GE 方法/静态函数？"工厂的位置本身是一条数据"
  这句话展开讲；无源效果（熔岩）的正确姿势是什么——为什么不是退回静态工厂？）
- **迁移策略**：（为什么全迁？入口收拢和出口漏斗的论证哪里**不对称**——
  强制手段 vs 三件软功夫；裸 new 的语义是"非法"还是"无源"？）

### 落地的东西

- （逐条：make_effect_spec 工厂（填了什么）/ apply 填 target_asc / 十八处迁移 +
  README 三处 / _make_damage_spec 缝与 30% 攻击折算 / 快照挪到 activate + 字段持有 /
  null 双门闩（生产者 return null、消费者 end_ability）/ ge_damage_base_attack.tres 配方归位）

### 这轮想通的原则

- **工厂填 source，apply 填 target**：（为什么是两个时刻两个填法？法球飞行的 0.5 秒
  和"source 已知、target 未知"的空窗是什么关系？）
- **改副本，不另起炉灶**：（spec._init 里 mod.duplicate() 当初为什么拍副本？
  "扣 30 血"那版错在哪——配方被架空意味着什么？）
- **报错必须带拦截**：（"装了警报器没装门闩"那版长什么样？fail-closed 的完整两句是什么？）
- **谁生产 null，谁的调用方就得消费 null**：（return null 之后雷埋在了哪条数据流下游？）
- **代码与文档不能静默分家**：（clamp 1.0→2.0 拖了四轮才对账——两边不一致时为什么
  比两边都错更危险？）

### 踩的坑

- （"扣除 30 血"为什么是审讯线索而不是成功证明——数字对账怎么反推出配方是空的？）
- （验票和用票必须是同一个对象——find_attribute_set 查两遍的问题；GAFireBold 拼写）

### 验收记录

| # | 用例 | 期望 | 结果 / 日志时间戳 |
|---|---|---|---|
| 1 | 无 buff 火球 | -80（50 + 0.3×100） | （填） |
| 2 | 攻击 buff(+50) 下 | -95（50 + 0.3×150） | （填） |
| 3 | buff 到期后 | 回 -80 | （填） |
| 4 | **快照专项**：起手后命中前 buff 到期 | 仍 -95 | （填——这是本课毕业照） |
| 5 | 回归：冷却 2.1s / 扣蓝 / 眩晕打断 | 全正常 | （填） |

### 遗留

- `world_origin` / `target_data` 仍无消费者；2D/3D 向量适配等第一个真实需求（范围伤害）再定；
- `context.ability` 字段未填——工厂看不见"哪个能力造的我"，等有消费者时再接（可能的方案：
  能力侧造 spec 后自己补，或 make_effect_spec 加可选参数）；
- 快照/实时目前是"写在哪就是哪"，还没做成 GE 上的配置开关（UE bSnapshot）——MMC 课的素材；
- 仓库根目录 `bash.exe.stackdump` 是崩溃转储垃圾文件，已被 git 追踪——应 rm + .gitignore。

---

*本轮结束时代码状态：（写完第 12 节后更新——参照第 10 节末尾那条的写法）*
