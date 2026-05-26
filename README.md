# ScoreBar

一个简洁的 macOS 菜单栏应用，随时掌控 NBA 和足球赛事动态。

## 功能特点

### NBA 赛事追踪
- 实时比分和比赛状态
- 支持赛前、进行中、结束各阶段
- 球员数据详情（得分、篮板、助攻等）

### 足球赛事覆盖
- 多联赛实时比分展示
- 比赛进程和结果即时更新

### 便捷使用
- 菜单栏常驻，打开即可查看比分
- 比赛置顶功能，关注的比赛永不漏过
- 中文界面，友好易读

### 实时更新
- 自动刷新，始终保持最新比分
- 低资源占用，后台运行无压力

## 安装使用

1. 下载最新版本的 `ScoreBar.zip`
2. 解压后将 `ScoreBar.app` 拖入应用程序文件夹
3. 首次运行需在系统设置中允许运行（macOS 安全限制）

## 构建源码

如需从源码构建：
```bash
xcodebuild -project NBALiveScore.xcodeproj -target ScoreBar -destination 'platform=macOS' build
```

然后在 `build/Release/` 目录找到编译好的应用。

## 数据来源

比赛数据来自 ESPN 官方 API。