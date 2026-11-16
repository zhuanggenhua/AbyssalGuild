# 合并战区的初始中心

锁定 CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`。
原 `CombatManager.MergeCombats` 按新加入 attackers/defenders，再按旧任务的 attackers/defenders 收集，按第一次出现去重后分为 Player/Mob。旧任务 `CleanUpForMerge` 不走 LeaveCombat，不重组幸存者堆叠；它停止协程并销毁旧 Rect。新 `CombatRect.Initialize` 读取最终参与者的实际 transform 均值，再展平、限制到棋盘并排列。

迁移新增独立 `merge_center_sampler`：旧任务及 membership 清理完成之后，替代任务的入战和随机进度抽取之前采样。清理前保留每个旧参与者实际归属、拖拽与执行中资格。不会调用独立开战的普通采样器来解释旧战斗角色，也不改变 faction/去重/顺序。

Board 只接受完整可证集合：
- 新加入者沿用普通地面当前位姿合同。
- 旧参与者必须有清理前的正确归属、缓存战区布局、对应定义的真实视图；视图必须位于当前模型的地面排列槽，且不存在执行或残留近战动作、拖拽、装备或周期展示所有权。
- 正常旧战斗角色已经脱离堆叠，CardMotion 状态可以不存在；若存在，必须是身份一致的 blocked 状态，不能将普通动画的 +0.06 高度解释成战斗高度。
- 非单位 Board 变换、缺失视图、抬高、旧渲染位置落后于本步 resize 后的排列槽，均拒绝。resize 原版同步 SetTargetInstant，而 Godot 视图尚未同步时不能拿上一帧的位置当本步源位姿。

任一参与者拒绝时，整个初始中心回到现有模型目标位置路径，不将部分观测拼成新中心。有效中心仅是新任务的一次性收据，不存档。已有或恢复的 layout 仍优先，后续布局更新不重新居中。

本改动只验证中心来源及采样边界，不宣称原版全部入战时序、完整 overlap 推挤、动态图形、在途/抬高参与者或 Unity 画面对照已完成。现有 Godot 在 combat_started 时更新布局，尚不能由本项推导为 Unity 在构造 CombatTask 前完成所有布局和所有随机进度的逐步等价。

## AddCombatants 同步重排（受限原生接入）

锁定 Unity `a11a89b` 中 `CombatTask.AddCombatants`：有效新增成员完成
`EnterCombat` 和初始进度之后，调用 `CombatRect.UpdateLayout`；后者经
`ArrangeCards/ArrangeRow` 对本战斗所有成员执行 `SetTargetInstant(forceGround:true)`，
随后才 `CheckAndMergeCombats`。瞬时 setter 取消普通目标跟随和 tween，再落地设置 transform。

Godot 在 resize selector 中先更新布局，再对**整组可验证且无活跃动作**的原生
CardView 同步落位；取消该组同身份 CardMotion 状态。只有实际写入原生节点后，
既有合并采样器才读取这些节点。不会把模型目标冒充原生观测，也不重排被相交的其他战斗。
板节点必须单位变换，view 必须为直接子节点且定义身份匹配。缺视图、旧身份、拖拽、
装备/周期演出占用或尚有攻击 presentation 时，整组不写入，保留原有保守回退。

注意：Unity 原代码**没有** execution/dragged 门禁，且 KillTweens 不停止战斗 coroutine。
本次门禁是尚未迁移这些交互时的明确覆盖限制，不是原规则。活跃攻击中新增成员的完整
取消/继续顺序、真实图形与同帧 Unity 对照仍未验收。

原生 Board 回归使用导入参数：54 项通过。新增覆盖有效加入时先同步原生位置、普通
运动取消、整组平均、原地不刷新即可移位、拖拽和执行中原子拒绝；另外两矩形起初不交，
新增一人扩宽后确实相交并替换两个任务，候选任务节点保持不动。删除仅这一同步调用的
负对照为 47/54，七项失败（包括真实 resize merge 观测）；恢复后 54/54，无错误/泄漏。
这些是无头原生逻辑证据，不是渲染验收截图。
