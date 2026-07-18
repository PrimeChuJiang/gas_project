# GAS 开发日志 · 调试与重构专场（2026-07-18 ~ 07-19）

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
2. **唯一收尾漏斗** —— N 条退出路径汇入 1 个清理函数（end_ability / end_task / _cleanup_effect，本轮搭了三次）。
3. **生命周期不变量 + 配对** —— 谁登记谁注销；所有 Ability 路径的终点必须是 end_ability。
4. **门票代替引用** —— 跨系统持有的凭据用 ID，不用对象引用；旧票优雅 false。
5. **fail-open vs fail-closed** —— "查询无法成立"才需要抉择；付费关口从严 + 大声报告。
6. **查询与命令分离（CQS）** —— 检查随时做，命令只做一次且基于当下。
7. **校验压在边界** —— 配置合法性在装载时查一次；被复用的谓词里不写调用方视角的日志。
8. **计数 + 跳变沿** —— 多方共享的状态用引用计数；信号只在存在性真正改变时发。
9. **数据当参数传** —— 清理函数吃 entry，不删后回查；遍历中会被回调修改的集合用快照或倒序。

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

*本轮结束时代码状态：三大 bug 修复 + 六项设计根治全部落地，全量手动回归通过。*
