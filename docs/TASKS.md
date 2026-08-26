# 開発タスク分解

## 進め方

- **Phase 0（完了）**: 骨組み・共通契約・CI。ここが全並列作業の前提。
- **Phase 1**: A〜E の 5 ワークストリームを `git worktree` で並列実装（実装は Sonnet）。
- **Phase 2**: 統合。契約のズレを潰し、CI を緑にする（監督は Opus）。
- **Phase 3**: 実機での作り込み（同期精度、長時間録画、ショートカット、配布）。

Phase 1 の 5 本は**ファイルの担当領域が重ならない**ように切ってある。
共有ファイル（`Package.swift`, `Sources/OptiRecordCore/**`）は Phase 0 で確定済みで、
Phase 1 の作業者は原則として触らない。契約の変更が必要になったら、勝手に直さず
統合担当に上げる。

---

## Phase 0 — 基盤（完了）

- [x] SwiftPM パッケージ構成（6 モジュール + 2 テストターゲット）
- [x] `OptiRecordCore` の型と protocol 契約
- [x] 設定モデルと永続化（前方互換デコード付き）
- [x] 純粋ロジック（ファイル名生成、ビットレート算出、一時停止タイムライン、レベル正規化）とそのテスト
- [x] `.app` バンドル組み立てスクリプト + Info.plist + entitlements
- [x] GitHub Actions（macOS runner で毎 push ビルド + テスト + .app 生成）

---

## Phase 1 — 並列実装

### A. `OptiRecordAudio` — 音声変換とミキサ（この App の心臓部）— **完了**

担当ディレクトリ: `Sources/OptiRecordAudio/`, `Tests/OptiRecordAudioTests/`

- [x] `AudioFormatConverter`: 任意の入力 `CMSampleBuffer` → 48kHz/2ch/Float32 へ `AVAudioConverter` で変換。
      モノラルはステレオへ複製。フォーマット変化（デバイス切り替え）でコンバータを作り直す。
- [x] `TimelineMixer: AudioMixing`: 絶対フレーム位置ベースのリングバッファ。
      無音埋め、最大待ち時間 200ms、1024 フレーム単位で出力。
- [x] ゲイン適用とソフトクリップ（単純加算で 0dBFS を超えたときの歪み対策）。
- [x] `LevelMeter`: peak/RMS を dBFS で算出、50ms ごとにコールバック。
- [x] `CMSampleBuffer` ⇄ `AVAudioPCMBuffer` の相互変換ユーティリティ。
- [ ] **テスト**（実デバイス不要な設計にすること）:
      合成 PCM を注入して — 遅れて届いたバッファが正しい位置に入る / 欠損が無音で埋まる /
      ドリフトが累積しない / ゲインとミュートが効く / レベル計算が既知の正弦波と一致する。

### B. `OptiRecordCapture` — ScreenCaptureKit とマイク、権限 — **完了**

担当ディレクトリ: `Sources/OptiRecordCapture/`

- [x] `SCStreamScreenCapturer: ScreenCapturing`
      - `SCShareableContent` から `ShareableContentSnapshot` を作る
      - `SCContentFilter`（display / window / application）を `CaptureTarget` から組み立てる
      - `SCStreamConfiguration`: 解像度・fps・`capturesAudio`・`excludesCurrentProcessAudio`・
        `showsCursor`・`queueDepth`・`minimumFrameInterval`・色空間
      - `.complete` 以外のフレーム（`SCStreamFrameInfo.status`）は捨てる
      - macOS 15+ ではマイクも `SCStream` から受け取る（`captureMicrophone`）
- [x] `AVCaptureMicrophoneCapturer: MicrophoneCapturing`（macOS 14 用 / デバイス指定時）
      - 入力デバイス列挙、デフォルト判定、デバイス切断のハンドリング
- [x] `SystemPermissionChecker: PermissionChecking`
      - `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`
      - `AVCaptureDevice.authorizationStatus/requestAccess`
      - システム設定の各ペインを開く
- [x] 対象ウインドウが閉じた・対象アプリが終了した場合の通知
- [x] キャプチャ系のエラーを全部 `RecorderError` に翻訳する

### C. `OptiRecordRecording` — 書き出しとコーディネータ — **完了**

担当ディレクトリ: `Sources/OptiRecordRecording/`

- [x] `AssetWriterMediaWriter: MediaWriting`
      - `AVAssetWriter` + 映像入力（H.264/HEVC, `expectsMediaDataInRealTime`）+ 音声入力（AAC）
      - 最初の映像バッファで `startSession`、それ以前の音声は破棄
      - `movieFragmentInterval = 5s`（クラッシュしても直前まで再生可能に）
      - 任意で system / microphone の m4a サイドカーを並行して書く
      - `finish()` で `RecordingResult`（長さ・サイズ・サイドカー）を返す
- [x] `RecordingCoordinator: RecordingControlling`（`@MainActor`）
      - 状態機械: idle → preparing → recording ⇄ paused → finishing → idle
      - 権限確認 → 出力先の準備 → キャプチャ開始 → ミキサ結線 → ライタ開始
      - **モニタリングモード**（録画せずメーターだけ動かす）
      - 一時停止・再開（`TimelineOffsetter` を映像・音声で共有）
      - 経過時間、ディスク残量監視、対象消失時の自動停止
      - 全コールバックを main actor へホップしてから UI に渡す
- [x] 異常系: ライタ失敗・キャプチャ停止・ディスク不足でも**録れたところまでは残す**

### D. `OptiRecordUI` + `OptiRecordApp` — メニューバー UI — **完了**

担当ディレクトリ: `Sources/OptiRecordUI/`, `Sources/OptiRecordApp/`

- [x] `RecorderViewModel: ObservableObject`（`RecordingControlling` を包む）
- [x] `PreviewRecordingController`（`RecordingControlling` のモック。SwiftUI プレビュー用）
- [x] `MenuBarExtra` 本体: 状態表示・経過時間・開始/停止/一時停止
- [x] `SourcePickerView`: 画面 / ウインドウ / アプリのタブ。会議アプリを先頭に。
- [x] `LevelMeterView`: システム音声とマイクを縦 2 本。無音警告とクリップ表示。
      **「相手が喋っているのに振れない」ときのトラブルシュートを画面内に出す**
- [x] `SettingsWindow`: 画質 / fps / コーデック / 保存先 / ファイル名テンプレート /
      マイクデバイス / ゲイン / サイドカー出力 / ショートカット / ログイン時に起動
- [x] `PermissionOnboardingView`: 未許可の権限を並べて、その場で要求・設定を開く
- [x] `RecordingsListView`: 直近の録画。Finder で表示・再生。
- [x] `OptiRecordApp`: `@main`、`NSApplication` 設定、通知、ログイン時起動（`SMAppService`）

### E. ビルド・配布・ドキュメント — **完了**

担当ディレクトリ: `Scripts/`, `.github/`, `docs/`, `Resources/`

- [x] `Scripts/build-app.sh` の詰め（アイコン生成、バージョン埋め込み、`--notarize`）
- [ ] `Resources/AppIcon.icns` の生成スクリプト（SF Symbols ベースの簡易アイコン）
- [x] `docs/TROUBLESHOOTING.md`: 音が入らないときの切り分け手順（権限・出力デバイス・
      Zoom 側の「オリジナルサウンド」設定・Bluetooth ヘッドセットの HFP 問題など）
- [x] `docs/RELEASING.md`: 署名・notarize・zip 配布の手順
- [x] GitHub Actions のリリースワークフロー（タグで .app を zip にして Releases へ）

---

### 並列実装の実際

5 本のうち B（キャプチャ）と A（ミキサ）はエージェントがコミットまで完了した。
C（書き出し・コーディネータ）と D（UI）を担当したエージェントはコミットを残さずに
終了したため、C は監督（Opus）が実装し、D は作業ツリーに残っていた成果物を回収して
統合した。

このため「エージェントには必ず worktree 内でコミットさせ、ブランチ名を報告させる」
という運用ルール（docs/AGENT_GUIDE.md §6）は、成果物を失わないために重要だった。
コミットが無くても作業ツリーからは回収できるが、途中経過か完成品かの判断が難しくなる。

## Phase 2 — 統合（監督）— **完了**

- [x] 各 worktree のマージと API 齟齬の解消
- [x] `OptiRecordApp` に実装を結線（`RecordingCoordinator` を注入）
- [x] CI 緑化（コンパイルエラー・警告・テスト）
- [x] 実機チェックリストの作成（下記）

## Phase 3 — 実機での作り込み（ここから先は実機が必要）

CI（macOS 15 runner）でビルドとテストが通ることまでは確認済み。ただし CI には
画面も、マイクも、画面収録の権限も無いため、**実際に音が録れるかどうかは実機でしか
確認できない**。以下は Apple Silicon Mac 上でのチェックリスト。


- [ ] Zoom / Teams / Meet それぞれで 30 分録画し、**末尾で音ズレが 50ms 以内**か確認
- [ ] Bluetooth ヘッドセット接続中・録画中の入力デバイス切り替え
- [ ] 外部ディスプレイの抜き差し、スリープ復帰
- [ ] 2 時間超の長時間録画（ファイルサイズ、メモリ、サーマル）
- [x] グローバルショートカットの登録（Carbon `RegisterEventHotKey`）
- [ ] 自動録画（会議アプリの起動を検知して録画開始を提案）
