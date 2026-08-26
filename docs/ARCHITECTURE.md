# OptiRecord アーキテクチャ

## 解こうとしている問題

macOS 標準の画面収録（⌘⇧5 / QuickTime Player）は **システム音声を録れない**。
そのため Zoom / Teams / Google Meet を録画しても「相手の声が入っていない」動画ができあがる。

OptiRecord は ScreenCaptureKit を使い、**画面 + システム音声 + マイク**を 1 本の
ファイルに同期して書き出す。仮想オーディオドライバ（BlackHole / Loopback 等）の
インストールは不要。

## 全体データフロー

```
                ┌──────────────────────── OptiRecordCapture ────────────────────────┐
                │                                                                 │
  画面 ───────► │ SCStream ──► video CMSampleBuffer ─────────────────────────────┼──┐
  システム音声 ─► │        └──► audio  CMSampleBuffer ──┐                          │  │
                │                                      │                          │  │
  マイク ──────► │ AVCaptureSession(<macOS 15)          │                          │  │
                │   or SCStream mic(macOS 15+) ────────┤                          │  │
                └──────────────────────────────────────┼──────────────────────────┘  │
                                                       ▼                             │
                        ┌──────────────── OptiRecordAudio ─────────────────┐             │
                        │ AVAudioConverter ─► 48kHz / 2ch / Float32     │             │
                        │ TimelineMixer (PTS 基準のリングバッファ)        │             │
                        │   ├─ gain / mute / レベル計測                  │             │
                        │   └─ 1024 フレーム単位でミックス出力             │             │
                        └───────────────┬───────────────────────────────┘             │
                                        │ mixed CMSampleBuffer                        │
                                        ▼                                             ▼
                        ┌──────────────────────── OptiRecordRecording ────────────────────┐
                        │ AVAssetWriter                                                │
                        │   video input : H.264 / HEVC (VideoToolbox HW encode)         │
                        │   audio input : AAC (mixed)                                   │
                        │   (option) system-only / mic-only の追加トラック                │
                        │ RecordingCoordinator: 状態機械 / 一時停止 / 経過時間 / 後始末    │
                        └───────────────┬─────────────────────────────────────────────┘
                                        │ RecordingControlling
                                        ▼
                        ┌──────────────── OptiRecordUI / OptiRecordApp ───────────┐
                        │ MenuBarExtra + 設定ウィンドウ + レベルメーター       │
                        └───────────────────────────────────────────────────┘
```

## モジュール分割

| モジュール | 責務 | 依存 |
|---|---|---|
| `OptiRecordCore` | ドメインモデル・プロトコル契約・設定・純粋関数ヘルパー。**他モジュールはここだけを共通言語にする** | なし |
| `OptiRecordAudio` | フォーマット変換、タイムライン整列ミキサ、レベル計測 | Core |
| `OptiRecordCapture` | ScreenCaptureKit ラッパ、マイク入力、TCC 権限 | Core, Audio |
| `OptiRecordRecording` | AVAssetWriter パイプライン、`RecordingCoordinator` | Core, Audio, Capture |
| `OptiRecordUI` | SwiftUI ビュー / ビューモデル | Core, Recording |
| `OptiRecordApp` | `@main`、アプリライフサイクル、.app バンドル本体 | UI, Recording, Capture |

依存は必ず下向き。上位モジュールの型を下位が知ることはない。

## 音声同期の設計（この App の心臓部）

システム音声とマイクは**別のクロックドメイン**から届くため、単純に足し合わせると
時間が経つほどズレる（ドリフト）。以下の方針で吸収する。

1. **共通タイムライン**: ScreenCaptureKit も `AVCaptureSession` も PTS は
   ホストクロック (`CMClockGetHostTimeClock()`) 基準。録画開始時の PTS を
   `anchor` とし、すべてのサンプルを `frameIndex = round((pts - anchor) * 48000)`
   という絶対フレーム位置に変換する。
2. **位置ベース書き込み**: 各ソースは自分の絶対フレーム位置でリングバッファに書く。
   届かなかった区間は無音で埋まる。デバイスのクロックドリフトは「位置で書く」ことで
   自動的に吸収される（累積しない）。
3. **出力プル**: 有効なソースすべてが揃うか、最大待ち時間（既定 200ms）を過ぎたら
   1024 フレーム単位でミックスして書き出す。
4. **正規化フォーマット**: 48kHz / 2ch / Float32。モノラルマイクは L/R に複製。
   変換は `AVAudioConverter`。

**既知の挙動**: 48kHz 以外のマイク（Bluetooth ヘッドセットの 16kHz 等）では、
`AVAudioConverter` のリサンプラがフィルタ履歴を満たすまで最初の数ミリ秒を内部に
保持する。結果として**このパスだけ 5〜10ms 程度の一定のレイテンシ**が乗る。
フレームが失われるわけではなく（`testResamplingLosesNoFramesOverTime` で担保）、
累積もしない。リップシンクの知覚閾値（40ms 程度）を大きく下回るため許容している。
出力位置を「変換後の累積フレーム数」で決めればこの一定オフセットは消せるが、
今度はデバイスのクロックドリフトが累積するようになるため、あえて入力 PTS 基準の
ままにしている。

一時停止 / 再開は `TimelineOffsetter`（Core、純粋型）が担当し、停止中の PTS を
差し引いて連続したタイムラインに詰める。映像・音声で同一のオフセットを使う。

## 録画の耐障害性

- `AVAssetWriter.movieFragmentInterval = 5s`。クラッシュしても直前までは再生可能。
- ディスク残量を録画前と録画中に監視し、閾値を下回ったら安全に停止する。
- 書き込み先は `RecordingSettings.outputDirectory`（security-scoped bookmark で永続化）。

## 権限

| 権限 | 用途 | 取得方法 |
|---|---|---|
| 画面収録 (Screen Recording) | 画面 + システム音声 | `SCShareableContent` 呼び出しで OS がプロンプト。`CGPreflightScreenCaptureAccess()` で事前確認 |
| マイク (Microphone) | 自分の声 | `AVCaptureDevice.requestAccess(for: .audio)` |

`Info.plist` に `NSMicrophoneUsageDescription`、`NSCameraUsageDescription` は不要。
ad-hoc 署名の場合、バイナリを更新するたびに TCC の許可がリセットされることがある。

## 最小 OS

**macOS 14 (Sonoma) / Apple Silicon**。
macOS 15+ では `SCStream` 内蔵のマイクキャプチャを使い、同一クロックドメインで
受け取ることでズレをさらに減らす（`if #available(macOS 15.0, *)` で分岐）。

## ビルド

Xcode プロジェクトは持たない。**SwiftPM が唯一の真実**で、`Scripts/build-app.sh` が
`.app` バンドル（Info.plist + entitlements + ad-hoc 署名）を組み立てる。
CI（GitHub Actions / macOS runner）で毎 push コンパイルとテストを回す。
