# 基础 StackCraft：特殊配方切片

## 范围与验证

实现 `ExplorationRecipe`、`GrowthRecipe`、`ResearchRecipe` 的源行为；不实现 Travel、场景切换、动画/粒子或全局堆叠碰撞避让。无 Unity 运行时依赖，无寒夜营地内容。测试读取真实 `data/stackcraft.json`，覆盖全部 5 个探索、6 个生长、1 个研究资产，以及边界用例。

运行：`bash tools/test_godot.sh res://tests/godot/test_special_recipes.gd`。测试隔离项目并使用可写 HOME/XDG。

结果：特殊配方 445 断言通过；原 runtime 76、quests 322、quest integration 70 全部通过，共 913 断言。特殊专测既包含直接动作边界，也覆盖全部 12 个源配方经实际 `move_to_stack`、选配方、暂停/计时、产物、重复运行与事件。实际 Explore 任务经探索完成，实际 Discover 任务经研究完成；另测取消、研究候选耗尽、探索生物产物继续重复、Travel 防误执行。

## 状态与正式接入

`special_recipes.gd` 是无状态动作函数，不保存第二套卡牌、堆栈、发现列表、随机数或计时器。所有变化直接使用调用 session 的 `cards`、`stacks`、`_next_id`、`rng`、`catalog`、`discovered_recipes` 和事件流。

已正式接入 `game_session.gd`。集成约定与实现：

1. preload SpecialRecipes；`_check_recipe` 候选允许普通 `RecipeDefinition` 或 `SpecialRecipes.supports(entry.script_class)`。仍使用现有匹配、权重、配方发现和栈计时。
2. `_complete_recipe` 读取完整 recipe entry；特殊类型调用 `SpecialRecipes.execute(self, stack, entry)`，不进入普通消耗/输出/`crafted` 分支。
3. 特殊动作后统一 `stack.cancel_craft()`、`_notify_stats_changed()`，按源规则决定重检：原配方 resultingCard 不是 Character/Mob，且 isContinuous 或存在 Consume/Destroy 输入，并且原栈仍注册。不能根据探索随机产物是否为生物来停止持续探索。
4. 不对刚分出的种子栈自动匹配配方。原 `CardStack.SplitAt` 只分栈，不启动新任务。
5. 研究通过 `spawn_recipe_card` 克隆原场景引用模板，并生成源格式配料描述。pack 路径本切片未重构；是否发现和事件先后仍由各调用路径管理。
6. TravelRecipe 不应进入普通分支。`execute` 对它返回 false，`supports` 也为 false。

## 源行为依据

审计源文件（只读外部参考，未复制第三方源码到仓库）：

- `Scripts/Crafting/Definitions/ExplorationRecipe.cs`：先找 Category.Area 且第一次 `GetRandomLoot` 非空的卡，再第二次抽取真正产物。只有第二次非空才 spawn 并发布探索事件；最后执行输入消耗。两次抽签不是笔误，本移植保留。权重借用 session 的 `_roll_loot`：非正权重忽略，空 Card 的正权重仍占概率。
- `GrowthRecipe.cs`：通过实际 definition 类型找第一个 Grower，以实际 definition 等于 resultingCard 找种子。只应用 Grower 的规则，不统一 Consume 全部输入。种子和它上面的所有卡一起拆出；种子已是栈底时不拆。产物额外生成一次。没有普通 crafted 事件。
- `GrowerDefinition.cs`：空标记子类，无额外参数。
- `ResearchRecipe.cs`：先消耗输入；从未发现、resultingCard 非空且非 Research/Growth/Exploration 的配方均匀选一个。原筛选未显式排除 Travel，本模块保留这一条件，但不实现 Travel 执行动作。没有候选也不退回已消耗输入。先生成配方卡，再发布发现事件。
- `RecipeDefinition.cs`：Consume=0、Keep=1、Destroy=2；消耗按底到顶实例顺序、依 BaseDefinition 匹配、限制计数。默认 craftingDuration=5、randomWeight=1、isContinuous=false、allowExcessIngredients=false，特殊类无不同默认值。
- `CardStack.SplitAt`：index<=0 不拆；index>0 将剩余上层移入新栈。
- `CardInstance.Size`：Collider size 加 CardSettings.margin。位移从导出场景 CardManager 的 category→prefab 引用解析，实际种子卡宽 0.8 加 margin.x 0.1，合计 0.9；不是猜测的视觉常量。缺失几何时不捏造位移。
- `CardManager.CreateRecipeCardDefinition/SpawnRecipeCard`：克隆场景 recipeCardTemplate，覆写 Recipe:id 和输出显示名。模块保留模板其余字段，不自行猜售价等属性。
- `CraftingManager` 完成顺序：Execute → 清除制作状态 → stats → 判断原配方输出类别与持续/消耗条件 → 重新匹配。

真实资产：探索 60 秒且持续；箱种植 60 秒；农场生长 30 秒；研究 60 秒且持续，需求 Library×1 + Villager×3。六个生长配方均 Keep Grower、Consume Seed，但实现必须按特殊逻辑保留种子，不可直接套普通 Consume。

## 已知展示边界

模型生成物遵循现有 session 的独立栈创建方式，排除原处理栈。原引擎的邻近自动附着、ResolveOverlaps、种子当前位置的3D堆叠偏移、粒子/音效不在此动作切片内。源定义和逻辑验证不等于这些展示行为已经迁移完成。
