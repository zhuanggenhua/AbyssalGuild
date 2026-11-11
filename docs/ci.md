# 公开仓库 CI

`.github/workflows/public-checks.yml` 在 push 和 pull request 时运行，只验证公开代码。绿色状态不代表原模板数据、完整游戏、视觉或真实输入已验收。

## 固定环境和权限

- GitHub 托管的 `ubuntu-24.04`，Python `3.12.14`，`requirements.txt` 中固定的 `PyYAML==6.0.3`。
- 官方 `actions/checkout` v7.0.1 和 `actions/setup-python` v7.1.0 固定到完整提交 SHA，不使用浮动 action 标签。
- Godot **4.6.3 stable** Linux x86_64，仅从 [Godot 官方发布页](https://github.com/godotengine/godot/releases/tag/4.6.3-stable)下载。执行前校验 SHA-256，并核对版本 `4.6.3.stable.official.7d41c59c4`。
- 归档 `Godot_v4.6.3-stable_linux.x86_64.zip` 的 SHA-256 为 `d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3`。来源是[官方 release asset 425558795 的 digest](https://api.github.com/repos/godotengine/godot/releases/assets/425558795)，2026-11-11 核验。上游另提供 `SHA512-SUMS.txt`；本工作流直接固定官方 API 发布的 SHA-256。校验不匹配即停止，不跳过验证。
- 工作流令牌仅有 `contents: read`，checkout 不保留凭据；不使用仓库 secrets、子模块、LFS、第三方安装 action、`pull_request_target` 或手动 dispatch。
- 不下载原模板，不恢复项目缓存，不上传文件或 artifacts，不导出游戏包。临时测试存档与日志在退出时删除。
- 整个作业最长 15 分钟；回归命令最长 300 秒，超时后再给 10 秒清理；GitHub 回归步骤另有 6 分钟上限。

## 覆盖范围

`tools/test_public_ci.sh` 首先拒绝含有 `source/`、`third_party/`、`data/`、`assets/imported/`、`.godot/`、`build/`、`artifacts/` 或 `.env*` 的工作目录，然后调用现有的 `tools/test_all.sh`。不会删除开发者的本地内容来凑出一个公开环境。

- Python：当前 27 个合成输入测试，覆盖导入、源清单、防篡改、视觉资源与场景元数据。
- Godot：由 `tools/test_all.sh` 维护的公开组，包括战斗、战斗布局、堆叠、存档、合成视觉绑定、桌面布局、合成相机和音频、缺少数据时的 UI 防护。各脚本通过 `tools/test_godot.sh` 隔离项目和用户数据。
- 除命令退出状态外，CI 会检查日志中的 `SCRIPT ERROR`、`ERROR`、`FAIL` 和断言错误，以免引擎报告错误但退出码为零造成假成功。

以下内容会明确标记为 **SKIP**，不是通过：

1. `tools/test_all.sh` 中需要 `data/stackcraft.json` 的源数据验证与 Godot 组，例如桌面集成、场景生成、世界规则、运行时、特殊配方、任务、旅行和怪物 AI。
2. 混合测试里依赖本地导入的分支，例如真实桌面/战斗布局参数、原始相机、音频绑定，以及完整 UI 游戏流程。公开 UI 测试只确认缺失数据时不能开始假游戏。
3. `test_source_board_mesh.gd` 的原始 FBX 模型断言，以及真实游戏操作、画面和音频验收。

新增公开测试应加入 `tools/test_all.sh` 的公开组；新增依赖已授权数据的测试应加入源数据组。不要为了让 CI 通过而提交被忽略的模板数据、原源码或导入素材。

## 本地复现

在不含私有导入结果的全新公开 clone 中，安装 Python 3.12.14 和已校验的 Godot 4.6.3 后执行：

```sh
python3 -m pip install --only-binary=:all: -r requirements.txt
GODOT=/absolute/path/to/Godot_v4.6.3-stable_linux.x86_64 bash tools/test_public_ci.sh
```

该命令需要 Linux 的 `timeout`。已有授权模板数据的开发目录继续使用 `bash tools/test_all.sh` 做更完整的本地回归；请勿把那份目录作为公开 CI 的输入。

工作流发布前，本地验证只能证明同一命令在当前机器和公开副本上通过。GitHub Actions 的首次真实运行、仓库 Actions 是否启用以及分支保护状态，都需要发布后另行查看；本次添加不会修改仓库设置。
