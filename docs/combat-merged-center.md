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
