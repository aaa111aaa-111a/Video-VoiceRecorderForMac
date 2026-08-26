# 並列実装ワークストリームの進め方

Phase 1 の作業者（worktree 上で作業するエージェント）向けの共通ルール。

## 1. 契約は `AizuchiCore` にある

自分のモジュールが公開する型は、`Sources/AizuchiCore/Protocols/` の protocol を
実装する形にすること。**`Sources/AizuchiCore/` と `Package.swift` は編集しない。**
契約に不足があると判断したら、勝手に変えずに次のようにする:

1. 自分のモジュール内に必要な型を追加して先へ進む
2. 変更提案を `docs/CONTRACT_CHANGES.md` に追記する（なければ作る）

複数の worktree が同じファイルを直すとマージが破綻するため、これは厳守。

## 2. 担当ディレクトリの外に書かない

`docs/TASKS.md` の担当ディレクトリだけを触る。テストは自分のモジュールの
テストターゲットに置く。テストターゲットが無い場合は `Package.swift` を変更せず、
既存の `Tests/AizuchiCoreTests/` には**追加しない**（衝突するため）。

## 3. コンパイルできない環境で書いている前提で書く

このリポジトリは Linux の CI コンテナ上で開発されており、`swift build` は
ローカルで走らない。検証は GitHub Actions（macOS runner）で行う。したがって:

- API の記憶があいまいなときは、**推測で書かず** `#if canImport` や
  `if #available` で安全側に倒し、コメントで不確実な点を明示する
- 1 ファイルにまとめず、責務ごとに小さく分ける（コンパイルエラーの切り分けが楽になる）
- `import` を忘れない（`AVFoundation`, `CoreMedia`, `ScreenCaptureKit`, `AppKit`, `os`）
- Swift 5 言語モード（`swift-tools-version: 5.9`）。Swift 6 の厳格な並行性は前提にしない

## 4. スレッド規約

| 呼び出し元 | スレッド | 制約 |
|---|---|---|
| `ScreenCapturing` のデリゲート | SCStream の専用キュー | ブロック禁止。重い処理は自前キューへ |
| `MicrophoneCapturing` のデリゲート | AVCaptureSession のキュー | 同上 |
| `AudioMixing` のコールバック | ミキサの専用キュー | 同上 |
| `RecordingControlling` の全メンバ | main actor | UI から直接触れる |

`RecordingCoordinator` が main actor への集約点。UI 層は他のキューを知らない。

## 5. エラーは `RecorderError` に翻訳する

OS の `NSError` をそのまま UI に上げない。ユーザーが次に何をすればいいか分かる
`RecorderError` のケースに翻訳する。足りないケースは自分のモジュールでは追加できないので、
最も近いケースに詳細文字列を添えて使う。

## 6. コミット

worktree の中で、意味のある単位でコミットする。最後に必ず:

```sh
git add -A && git commit -m "..."
git log --oneline -5
git rev-parse --abbrev-ref HEAD
```

を実行し、**ブランチ名と worktree のパスを報告に含める**こと。統合担当がそれを見て
マージする。
