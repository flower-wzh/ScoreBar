# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
ScoreBar is a macOS menu bar application built with SwiftUI that displays NBA and soccer game schedules and scores. It fetches real-time data from ESPN APIs and provides detailed game statistics.

## Development Commands
- **Build**: `xcodebuild -project NBALiveScore.xcodeproj -target ScoreBar -destination 'platform=macOS' build`
- **Clean Build**: `xcodebuild clean -project NBALiveScore.xcodeproj -alltargets`
- **Run in Xcode**: Select the ScoreBar scheme and press ⌘R

## Architecture Overview

### Background/Foreground Modes
The app operates in two modes:
- **Foreground Mode**: Full polling for all games (NBA + Soccer), triggered on app activation
- **Background/Silent Mode**: When app is not active, only pinned game is refreshed via lightweight API calls to `site.api.espn.com`

### Core Components
1. **AppDelegate** (`ScoreBar/NBALiveScoreApp.swift`): Manages status bar, popover, background/foreground observers, and silent mode refresh
2. **SportsViewModel** (`ScoreBar/SportsViewModel.swift`): NBA data fetching, polling, state management. Status values are standardized: `final`, `scheduled`, `live`
3. **SoccerViewModel** (`ScoreBar/SoccerViewModel.swift`): Soccer data fetching and polling
4. **GlobalPinnedGameManager** (`ScoreBar/SoccerModels.swift`): Unified pinned game state for both sports
5. **ContentView** (`ScoreBar/ContentView.swift`): Main SwiftUI view with game list, pin functionality, and hover details

### Data Flow
- **NBA Data Source**: ESPN API (`site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard`)
- **Soccer Data Source**: ESPN API (`site.api.espn.com/apis/site/v2/sports/soccer/{league}/scoreboard`)
- **Background Refresh**: Uses lightweight summary endpoint (`site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event={id}`)

### Status State Mapping (Important)
ESPN API returns raw states (`post`, `pre`, `in`) which must be mapped to internal states for consistency:
- `post` → `final` (比赛结束)
- `pre` → `scheduled` (未开始)
- `in` → `live` (进行中)

This mapping exists in `SportsViewModel.swift:169` and must be replicated in `NBALiveScoreApp.swift` for background refresh to maintain consistency.

### State Bar Display Logic
Status bar uses `displayGame.status` to determine display format:
- `live`: Period name (e.g., "第三节") + game clock
- `final`: "全场战罢" + "已结束"
- `scheduled`: "未开始" + formatted start time

## Key Features
- **Dual Sport Support**: NBA and Soccer with unified pinning system
- **Background Silent Updates**: Lightweight refresh when app is in background
- **Status Bar Integration**: Custom image rendering for menu bar display
- **Game Pinning**: Pin a game to always show in status bar
- **Live Updates**: Configurable polling interval (default 10s)
- **Chinese Localization**: Team names, player names, and status text in Chinese

## Data Models
- `Game` (`SportsViewModel.swift`): NBA game entity with teams, scores, status
- `Team` (`SportsViewModel.swift`): Team with id, name, score, logo, tricode
- `SoccerGame`, `SoccerTeam` (`SoccerModels.swift`): Soccer equivalents
- `GlobalPinnedGameManager` (`SoccerModels.swift`): Manages pinned game state for both sports
- `BoxscoreModel` (`ContentView.swift`): Detailed game statistics with player data

## Networking
- URLSession with custom User-Agent headers to mimic browser requests
- Anti-bot measures: proper headers and ephemeral sessions
- Background refresh uses lightweight summary API (not full scoreboard)