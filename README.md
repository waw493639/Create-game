# 六面开市

使用 Godot 4.7 制作的七日夜市经营原型，用来验证六向入口、摊位朝向和空格道路是否能产生有意义的空间规划。店铺使用透明化后的生成素材，悬停棋盘摊位可查看完整经营数据。

## 操作

| 操作 | 方式 |
| --- | --- |
| 放置起始摊位或招租摊位 | 按住右侧卡片并拖到棋盘 |
| 移动已有摊位 | 左键拖动 |
| 旋转摊位 | 拖动时滚轮/右键，或对棋盘摊位右键 |
| 查看首段预计路线 | 悬停底部客流预报 |
| 查看店铺详情 | 悬停棋盘中的店铺 |
| 取消当前拖放 | `Esc` |
| 开始客流模拟 | 点击“开市” |
| 控制模拟 | 暂停以及 `1x`、`2x`、`4x` |

空格是街道，六个紫色入口不可建造。只有金色售卖边面对空街时，摊位才能服务对应类别的顾客。筹备期间可以免费重排已经拥有的摊位。

## 运行

双击 `run_game.ps1`，或在 Godot 中导入本目录的 `project.godot` 后按 `F6`/`F5`。

本机 Steam 版 Godot 也可以直接运行：

```powershell
& 'D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path .
```

## 测试

双击 `test_game.ps1`，或运行：

```powershell
& 'D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/test_runner.gd
```

自动化测试覆盖六边坐标、入口和重叠规则、免费重排、招租成本、报价轮转、种子确定性、口碑加成、店铺详情、顾客消费与七日终局。
