# AbyssalGuild

以 **StackCraft 基础模板**为参考、使用 Godot 4.6 重写的迁移工程。

## 当前状态

正在重新迁移。阶段提交是经过对应检查的备份，不代表整个游戏已完成，也不是最终亲测版。

- 唯一参考来源：`zhuanggenhua/CardLoop` 的 `a11a89b04cea8370476f2559b639bb9b4cbc08d8` 下 `Assets/StackCraft`。
- 参考场景：`Title`、`Main`、`Island`；不使用后续《寒夜营地》剧本。
- 原始模板的文件清单与 SHA-256：[`docs/source-lock.json`](docs/source-lock.json)。
- 源码只做静态读取，不启动 Unity；Godot 的逻辑、运行和画面分别验证。
- 不把 2026-11-09 的另一套迁移包视为此次迁移基础或最新工程。

## 第三方内容

当前仓库公开。模板自身的源码和整包再分发许可尚未确认，因此不在 Git 中复制 Unity 原文件、PDF、原模型、原素材或批量导出的内容数据。导入工具、独立重写的 Godot 源码、来源校验与测试会分阶段保存。

持有合法模板副本的开发者可以按[静态导入说明](docs/data-import.md)在本地生成被 Git 忽略的内容。未经核验，不将生成数据或素材重新加入公开提交。许可说明见 [`docs/source-baseline.md`](docs/source-baseline.md)。

## 验证

```sh
python3 tools/check_source_lock.py /path/to/Assets/StackCraft
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

导入后可用 Godot 4.6 打开 `project.godot`，运行主场景。当前已有可操作的原创 3D 桌面、战斗/装备和 Godot 原生存档，仍是迁移阶段版本，不是原版视觉复刻或最终亲测版。

```sh
bash tools/test_all.sh
godot --path .
```

没有本地导入数据时会明确阻止开始游戏，不以假数据代替原模板。操作说明见 [`docs/board-ui.md`](docs/board-ui.md)。

运行时和视觉验收进度见 [`docs/migration-progress.md`](docs/migration-progress.md)，已确认的剩余差异见 [`docs/remaining-parity.md`](docs/remaining-parity.md)。公开仓库的 GitHub Actions 仅验证不含授权素材的代码与合成测试。
