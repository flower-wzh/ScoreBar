# ScoreBar

一个 macOS 菜单栏应用，支持 NBA 和足球赛程与比分实时展示（SwiftUI）。

## 开发环境
- Xcode（建议使用最新稳定版）
- macOS（本项目为 macOS App）

## 运行方式
1. 用 Xcode 打开 `NBALiveScore.xcodeproj`
2. 选择运行目标 `ScoreBar`
3. `Run`（⌘R）

## 主要功能

### 双平台支持
- **NBA 赛事**：实时比分、比赛状态（进行中/已结束/未开始）
- **足球赛事**：支持多种联赛实时比分展示

### 实时更新
- 前台模式：轮询所有比赛数据（默认间隔 10 秒）
- 后台/静默模式：仅刷新置顶比赛，使用轻量级 API
- 状态栏实时显示当前比分和比赛状态

### 比赛置顶
- 可将任意比赛置顶，在后台模式下持续追踪
- 统一的置顶系统同时适用于 NBA 和足球

### 中文本地化
- 球员姓名、球队名称中文映射
- 比赛状态中文显示（如"第三节"、"全场战罢"）
- 支持姓名显示模式切换（仅名字/全名）

### 球员数据
- 支持从远程 JSON 词典拉取球员姓名映射
- 可在设置中自定义球员姓名映射 URL

## 技术架构

### 核心组件
- `ScoreBar/NBALiveScoreApp.swift`：状态栏、弹出窗口、前后台切换
- `ScoreBar/SportsViewModel.swift`：NBA 数据获取、轮询、状态管理
- `ScoreBar/SoccerViewModel.swift`：足球数据获取和轮询
- `ScoreBar/SoccerModels.swift`：足球数据模型和全局置顶管理
- `ScoreBar/ContentView.swift`：主视图，包含比赛列表、置顶功能、悬停详情

### 数据来源
- NBA：ESPN API (`site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard`)
- 足球：ESPN API (`site.api.espn.com/apis/site/v2/sports/soccer/{league}/scoreboard`)
- 后台刷新：轻量级摘要 API (`site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event={id}`)

### 状态映射
ESPN API 原始状态映射为统一内部状态：
- `post` → `final`（比赛结束）
- `pre` → `scheduled`（未开始）
- `in` → `live`（进行中）

## 词典（players.json）
- 仓库内置：`ScoreBar/data/players.json`
- 通过 Raw 访问（main 分支）：
  - `https://raw.githubusercontent.com/flower-wzh/ScoreBar/main/ScoreBar/data/players.json`

## 构建命令
- **编译**：`xcodebuild -project NBALiveScore.xcodeproj -target ScoreBar -destination 'platform=macOS' build`
- **清理编译**：`xcodebuild clean -project NBALiveScore.xcodeproj -alltargets`

