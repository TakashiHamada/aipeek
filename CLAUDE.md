# AIPeek — Claude Code 用プロジェクトメモ

軽量 macOS スケッチアプリ。マウスで描いたスケッチを AI チャットへ素早く受け渡すための、Mac Catalyst + SwiftUI + PencilKit 製。

## アーキテクチャ要点

```
Sketch/
├── SketchApp.swift            # @main、Notification.Name (.showPreferences, .showAbout)
├── ContentView.swift          # ZStack 全部入り。canvas + toolbar + overlays
├── Canvas/
│   ├── CanvasView.swift       # UIViewRepresentable + Coordinator(stroke 並び替え)
│   ├── CanvasController.swift # @MainActor。autoSave / copyToClipboard / tool 切替
│   └── LoggingCanvasView.swift # PKCanvasView subclass。shift snap / 赤 underlay / cursor
├── Config/
│   ├── AppConfig.swift        # Codable な config.json マッピング
│   └── AppSettings.swift      # ObservableObject。@Published で UI 同期 + 永続化
├── Export/
│   ├── DrawingRenderer.swift  # PKDrawing → JPEG(quality 0.9)
│   ├── ClipboardWriter.swift  # UIPasteboard 書き込み(jpeg + plain-text path)
│   └── FileStore.swift        # ~/Library/Application Support/com.giftten.aipeek/...
├── Support/
│   └── TitleBarTuner.swift    # Catalyst titlebar 透明化(冪等)
└── UI/
    ├── AboutView.swift / HelpView.swift / PreferencesView.swift
    ├── ToastView.swift / Theme.swift
```

## 重要な設計判断

- **インキング描画は全て自前 preview + commit on touchesEnded**: `LoggingCanvasView` が `touchesBegan/Moved/Ended` を捕まえて `dragSegments: [Segment]` に蓄積し、CAShapeLayer の単一 path に毎フレーム反映。touchesEnded で `PKStroke` として `drawing.strokes` に append する。PencilKit のネイティブストローク作成パスは inking ツールでは使わない(super を呼ばない)。
- **複合ストローク**: 1 つのドラッグは複数の `Segment` から成る。`SegmentMode = .freehand | .line` をシフト状態の遷移で切り替える(shift down → 新しい line セグメント、shift up → 新しい freehand セグメント)。コミット時に全 segment を 1 本の PKStroke に flatten する。
- **eraser だけ PencilKit ネイティブ**: `PKEraserTool` のストローク削除アルゴリズムを再実装するコストは大きいので、消しゴム時のみ `super.touchesBegan/Moved/Ended` に委譲。
- **`drawingPolicy` の所有権は 1 つ**: `LoggingCanvasView.pollShift` (CADisplayLink 60fps) だけが真の owner。`finalizeDrag` や `Coordinator.pushRedStrokesToBack` は drawing 代入のために一時的に `.anyInput` にするが、復元時は **保存した値ではなく live な `globalShiftDown` を見る**。savedPolicy 方式は競合する。
- **Shift キー検出は CGEventSource.flagsState + CADisplayLink polling**: Mac Catalyst では修飾キー単独の押下が `UIPress` を発火しないため。polling が状態変化を検知したら `transitionSegment()` を呼んでドラッグの segment を切り替える。
- **赤マーカー = z-order トリック**: 赤ストロークは通常の `PKStroke` として保存されるが、`Coordinator.pushRedStrokesToBack` が `drawing.strokes` を「赤を前(=下層)・非赤を後(=上層)」に並べ替える。視覚的に「乗算合成」のように見える。
- **ドラッグ中の z-order**: コミット後の reorder では足りないので、`LoggingCanvasView` が touchesBegan で非赤ストロークだけを `UIImageView` にレンダリングして canvas の上にオーバーレイ表示する(赤 preview がその下に潜る)。
- **autoSave は detached Task**: `performAutoSave` は MainActor で snapshot(`PKDrawing` は値型)を取ってから `Task.detached(priority: .utility)` で renderJPEG + write を実行。UI スレッドは止めない。

## ドメイン語彙

- **autoSave** — 描画完了から 1s デバウンスで sessions/ に保存
- **autoCopyOnSave** — 上記と同時にクリップボードへ画像 + パス送信
- **retentionDays** — 起動時に保持する過去日付フォルダ数。`-1`=全保持 / `0`=全削除 / `N`=最新 N
- **customSessionsRoot** — sessions/ フォルダのカスタム保存先(`null` = 既定)
- **dragSegments** — 1 ドラッグを構成する `Segment` の列。各 segment は `freehand` か `line` のモードを持ち、shift 状態の遷移で切り替わる
- **shift snap** — `line` segment 中、anchor → cursor が水平/垂直にスナップされる
- **赤マーカー / vermilion** — `Theme.vermilionRedUI` の朱色。z-order で黒の下に
- **session** — `sessions/YYYY-MM-DD/sketch_HH-MM-SS.jpg`(1 ファイル = 1 セッション)

## Review Checklists

新規/変更コードをレビューする際の固有チェック項目:

### PencilKit / Mac Catalyst 固有の落とし穴

- [ ] **インキング系の touches は PencilKit に渡さない**。`LoggingCanvasView.touchesBegan/Moved/Ended` は inking ツール時に super を呼ばず、自前で `dragSegments` を構築する。super を呼ぶのは eraser ツール時のみ
- [ ] **シフト状態変化は `transitionSegment()` で扱う**。`pollShift` がドラッグ中に shift の遷移を検知したら、現セグメントを「確定形」(line なら snap した端点で固定、freehand なら累積点をそのまま)にして、新セグメントを `cursorLocation` 起点で開始する
- [ ] `drawingPolicy` を一時的に書き換える場合、復元値は `LoggingCanvasView.isShiftPolicyActive` を見る(savedPolicy ローカル保存方式は禁止)
- [ ] `drawing` プロパティに代入する処理は再帰的に `canvasViewDrawingDidChange` を発火する → 再入ガード必須
- [ ] PKInkingTool の `.pen` は速度/筆圧で太さ変動する。Catalyst マウス入力 (force=0) では細くなる。`.monoline` を基本に
- [ ] PKInkingTool の色は ダークモードで自動反転される(.black ↔ .white)。アプリは `preferredColorScheme(.light)` で固定済み
- [ ] `Theme.vermilionRedUI` を直接コピー/別の赤を作らない。`isVermilionColor` の判定が壊れる
- [ ] Catalyst で modifier キー単独の押下は `UIPress` を発火しない → `CGEventSource.flagsState` ベースの polling を使う
- [ ] `UIPointerStyle.hidden()` は **関数呼び出し**(`.hidden` ではない)
- [ ] preview の `CAShapeLayer.lineWidth` と inject 後の `PKStrokePoint.size` は同じ値(生 `inking.width`)を使う。両者でズレると「ドラッグ中だけ細い/太い」現象が出る

### autoSave / 並行性

- [ ] `performAutoSave` 内の `url` / `drawing` は MainActor でローカルに snapshot してから detached task に渡す。`self.reservedURL` を後で参照すると newSession の URL swap で別ファイルに書き込んでしまう
- [ ] `autoSaveTask.cancel()` のあと in-flight task が完了する可能性がある → 世代カウンタ等で abort 判定する場合は要設計

### ファイル I/O

- [ ] `FileStore.reserveFilename` の連番は 99 まで、それ以上は ms 付与にフォールバック(オーバーライト禁止)
- [ ] `FileStore.customSessionsRoot` は @MainActor からのみ書く(`nonisolated(unsafe)`)

### UI

- [ ] トースト寿命は `CanvasController.toastLifetimeNs` 定数を使う(マジック数値禁止)
- [ ] Notification.Name の post 元は `SketchApp.commands`、受信は `ContentView.onReceive`。両方にコメントで道標を残す

## ビルド

```sh
xcodebuild -project Sketch.xcodeproj -scheme Sketch \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' build
```

DerivedData の app: `~/Library/Developer/Xcode/DerivedData/Sketch-*/Build/Products/Debug-maccatalyst/AIPeek.app`

## 残課題 / 既知のリスク

- **クラス名 `LoggingCanvasView`** は歴史的な命名で実体と合わない(logging 機能なし)。リネーム影響範囲が大きく未着手
- **`AppSettings.customSessionsRoot`** は非 Optional、`AppConfig.customSessionsRoot` は Optional のハイブリッド。永続化時に「既定と一致なら nil で書く」変換を `persistIfReady` で実施
- **CGEventSource の Catalyst 動作**: 実機で確認済みだが accessibility permission を将来要求される可能性。フォールバックパスは UIPressesEvent / GCKeyboard で実装済み
- **太さの視覚整合**: preview `CAShapeLayer.lineWidth` と PKStroke の表示太さに微差が出る可能性。現状は両者とも `inking.width` を生で使う。明確なズレが出たら経験的補正関数を再導入する余地あり
