# Sketch (走り書き)

macOS 用の軽量スケッチアプリ。思いついたアイデアをすぐ書き出し、Claude Code / Claude.ai / Discord などのチャットに素早く共有することを目的としている。

## 概要

- ターゲット: macOS 14 (Sonoma) 以降 / Apple Silicon ネイティブ
- 構成: Mac Catalyst + SwiftUI + PencilKit
- Bundle ID: `com.giftten.sketch`

## ビルド

```sh
# Debug (Mac Catalyst)
xcodebuild -project Sketch.xcodeproj -scheme Sketch -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' build

# Release
xcodebuild -project Sketch.xcodeproj -scheme Sketch -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' build
```

ビルド成果物の `Sketch.app` を `/Applications/` にコピーすると Spotlight でも検索できる。

## キーボードショートカット

- `⌘S` — Copy & Save(PNG をクリップボードへコピー & ディスクへ保存)
- `⌘N` — Clear(キャンバスをリセット、`⌘Z` で復活可能)
- `⌘Z` / `⌘⇧Z` — Undo / Redo(PencilKit 標準)

## 保存先

`~/Library/Application Support/com.giftten.sketch/`

```
.
├── config.json
└── sessions/
    └── YYYY-MM-DD/
        └── sketch_HH-MM-SS.png
```

## 設定

`config.json`(無ければ起動時にデフォルトで動作)。

```json
{
  "retentionDays": 1
}
```

- `retentionDays`: 起動時に最新 N 日分のセッションフォルダを残す。`-1` = 削除しない / `0` = 全削除 / `1` (既定) = 最新の 1 日分のみ。
