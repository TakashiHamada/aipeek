# AIPeek

マウスで描いたスケッチを Claude Code / Claude.ai / Discord などにすぐ送り、AI に「ちょっと見て」と頼むための軽量 macOS アプリ。

## 概要

- ターゲット: macOS 14 (Sonoma) 以降 / Apple Silicon ネイティブ
- 構成: Mac Catalyst + SwiftUI + PencilKit
- Bundle ID: `com.giftten.aipeek`

## 主な機能

- **オートセーブモード**(デフォルト ON): セッション固定のファイル名で 1 秒デバウンス自動保存
- **オートクリップボード**(デフォルト ON): 保存と同時に画像 + パスをクリップボードへ送信。Claude Code に一度貼ったら以降「もう一度見て」だけで最新の絵が読まれる
- **Shift スナップ**: Shift キーを押しながらドラッグで水平/垂直の直線を描画。Shift 押下中はマウスカーソルが十字に変わる
- **赤マーカー**: 朱色の不透明ペン。黒線の下層にレンダリングされるので「黒線の上に赤を引いても黒のまま」=乗算合成的な見た目
- **手動 Copy**: クリップボードへ画像+パスを送る(自動コピー OFF 時や、即時更新したい時に)

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
| **P** | ペン(黒・monoline・幅3) |
| **R** | 赤マーカー(朱色・幅14) |
| **E** | 消しゴム |
| **H** | ヘルプ画面を開く |
| **⌘N** | 新規(キャンバスをクリア + autoSave ON ならファイル名を再予約) |
| **⌘S** | Copy(画像 + パスをクリップボードへ。自動コピー時は disable) |
| **⌘,** | 環境設定 |
| **⌘Z / ⌘⇧Z** | Undo / Redo |
| **Shift + ドラッグ** | 水平/垂直の直線を描画 |

## 保存先

```
~/Library/Application Support/com.giftten.aipeek/
├── config.json
└── sessions/
    └── YYYY-MM-DD/
        └── sketch_HH-MM-SS.jpg
```

JPEG (quality 0.9) で書き出される。

## 設定 (`config.json`)

```json
{
  "autoSave": true,
  "autoCopyOnSave": true,
  "retentionDays": 1,
  "customSessionsRoot": null
}
```

| キー | 既定値 | 説明 |
|---|---|---|
| `autoSave` | `true` | 描画完了後 1s デバウンスで自動保存 + パス自動コピー |
| `autoCopyOnSave` | `true` | 自動保存と同時に画像本体もクリップボードへ送信 |
| `retentionDays` | `1` | 起動時に保持する過去セッションフォルダ数。`-1` = 削除しない / `0` = 全削除 / `N≥1` = 最新 N 日分 |
| `customSessionsRoot` | `null` | sessions フォルダのカスタム保存先。`null` で既定パス。`~` 展開対応 |

環境設定ウィンドウ(⌘,)から変更すると即座に反映・永続化される。

## アーキテクチャ

- `Sketch/Canvas/` — `PKCanvasView` 周辺。`LoggingCanvasView` が Shift スナップ・カーソル・赤マーカー underlay を担当、`CanvasView.Coordinator` がストロークの z-order 並び替えを担当
- `Sketch/Export/` — `DrawingRenderer` (PKDrawing→JPEG)、`FileStore` (パス管理・書き出し)、`ClipboardWriter`
- `Sketch/Config/` — `AppConfig` (Codable) と `AppSettings` (ObservableObject)
- `Sketch/UI/` — Help / About / Preferences / Toast / Theme
