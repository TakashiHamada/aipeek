# AIPeek

マウスで描いたスケッチを Claude Code / Claude.ai / Discord などにすぐ送り、AI に「ちょっと見て」と頼むための軽量 macOS アプリ。

## 概要

- ターゲット: macOS 14 (Sonoma) 以降 / Apple Silicon ネイティブ
- 構成: Mac Catalyst + SwiftUI + PencilKit
- Bundle ID: `com.giftten.aipeek`

## 主な機能

- **オートセーブモード**(デフォルト ON): セッション固定のファイル名で 500ms デバウンス自動保存
- **パス自動コピー**: 起動・新規・各保存タイミングで予約パスをクリップボードに自動コピー → Claude Code に一度貼ったら「もう一度見て」で最新が読まれる
- **Copy! ボタン**: 画像 + パスをまとめてクリップボードへ(Discord / Claude.ai 等への直接貼り付け用)

## ビルド

```sh
xcodebuild -project Sketch.xcodeproj -scheme Sketch -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' build

# Release
xcodebuild -project Sketch.xcodeproj -scheme Sketch -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' build
```

ビルド成果物の `AIPeek.app` を `/Applications/` にコピーすると Spotlight でも検索できる。

## ショートカット

| キー | 動作 |
|---|---|
| **P** | ペン |
| **E** | 消しゴム |
| **⌘N** | 新規(キャンバスをクリア + autoSave ON ならファイル名を再予約) |
| **⌘S** | Copy!(画像 + パスをクリップボードへ) |
| **⌘,** | 環境設定 |
| **⌘Z / ⌘⇧Z** | Undo / Redo |

## 保存先

```
~/Library/Application Support/com.giftten.aipeek/
├── config.json
└── sessions/
    └── YYYY-MM-DD/
        └── sketch_HH-MM-SS.jpg
```

## 設定 (`config.json`)

```json
{
  "autoSave": true,
  "retentionDays": 1
}
```

- `autoSave`: 自動保存とパス自動クリップボードコピーの ON/OFF(既定 `true`)
- `retentionDays`: 起動時に残すセッションフォルダ数。`-1` = 削除しない / `0` = 全削除 / `1` 以上 = 最新 N 日分(既定 `1`)

環境設定ウィンドウ(⌘,)から変更すると即座に反映・永続化される。
