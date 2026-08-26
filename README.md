# Aizuchi（相槌）

**Apple Silicon Mac 用・音声が本当に入る会議レコーダー。**

Zoom / Microsoft Teams / Google Meet を macOS 標準の画面収録（⌘⇧5・QuickTime Player）で
録画すると、**相手の声が入らない**。macOS はアプリの再生音（システム音声）を
標準の画面収録に流し込まないためで、従来は BlackHole などの仮想オーディオドライバを
入れる必要があった。

Aizuchi は ScreenCaptureKit を使って **画面 + システム音声 + マイク** を
1 本のファイルに同期録画する。追加のドライバもカーネル拡張も不要。

> 会議の録画・録音は、参加者の同意と所属組織のポリシーに従って行ってください。

## できること

- 画面全体 / 特定ウインドウ / 特定アプリを選んで録画
- **システム音声（相手の声）とマイク（自分の声）を同時収録**し、1 トラックにミックス
- 録画開始前に**レベルメーターで「本当に音が入っているか」を確認**できる
- 文字起こし用に、マイクのみ / システム音声のみの m4a を別途書き出し（任意）
- メニューバー常駐 + グローバルショートカット（既定 ⌃⇧R）で会議中でも邪魔にならない
- H.264 / HEVC のハードウェアエンコード（Apple Silicon）、1080p30 で概ね 3.4 Mbps
- Zoom / Teams / Meet などの起動中の会議アプリを自動で候補に出す

## 動作環境

- macOS 14 (Sonoma) 以降
- Apple Silicon (arm64)
- 権限: **画面収録**（必須）、**マイク**（自分の声を録るなら）

macOS 15 以降ではマイクも ScreenCaptureKit 経由で取得し、同一クロックで
扱うことでズレをさらに小さくします。

## ビルド

```sh
git clone https://github.com/aaa111aaa-111a/Video-VoiceRecorderForMac.git
cd Video-VoiceRecorderForMac
make app          # dist/Aizuchi.app を生成（ad-hoc 署名）
make install      # /Applications へコピー
```

`swift build` / `swift test` も単体で動きます（Xcode プロジェクトは持ちません）。

初回起動時に **システム設定 > プライバシーとセキュリティ > 画面収録** で
Aizuchi を許可してください。ad-hoc 署名のため、リビルドすると許可が
リセットされることがあります。

## 使い方

1. メニューバーの ● アイコンをクリック
2. 録画対象（会議アプリ / 画面）を選ぶ
3. **メーターが振れているか確認**（相手が喋っているのにシステム音声が動かないなら権限を疑う）
4. 「録画開始」または ⌃⇧R
5. 会議終了後にもう一度 ⌃⇧R。`~/Movies/Aizuchi/` に保存されます

## 設計

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) を参照。
開発タスクの分解は [docs/TASKS.md](docs/TASKS.md)。

## ライセンス

MIT
