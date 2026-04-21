# NBALiveScore

一个 macOS 菜单栏/悬浮样式的 NBA 赛程与比分展示应用（SwiftUI）。

## 开发环境
- Xcode（建议使用最新稳定版）
- macOS（本项目为 macOS App）

## 运行方式
1. 用 Xcode 打开 `NBALiveScore.xcodeproj`
2. 选择运行目标 `NBALiveScore`
3. `Run`（⌘R）

## 功能说明
- 支持从远程 JSON 词典拉取球员姓名映射（也可在设置中自定义 URL）
- 支持姓名显示模式切换：
  - 仅展示名字（LastName）
  - 展示全名（FirstName·LastName）

## 词典（players.json）
- 仓库内置：`NBALiveScore/data/players.json`
- 通过 Raw 访问（main 分支）：
  - `https://raw.githubusercontent.com/flower-wzh/NBALiveScore/main/NBALiveScore/data/players.json`

