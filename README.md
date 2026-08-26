# OptiRecord

[![CI](https://github.com/aaa111aaa-111a/Video-VoiceRecorderForMac/actions/workflows/ci.yml/badge.svg)](https://github.com/aaa111aaa-111a/Video-VoiceRecorderForMac/actions/workflows/ci.yml)

**Apple Silicon Mac 用・音声が本当に入る会議レコーダー。**

Zoom / Microsoft Teams / Google Meet を macOS 標準の画面収録（⌘⇧5・QuickTime Player）で
録画すると、**相手の声が入らない**。macOS はアプリの再生音（システム音声）を
標準の画面収録に流し込まないためで、従来は BlackHole などの仮想オーディオドライバを
入れる必要があった。

OptiRecord は ScreenCaptureKit を使って **画面 + システム音声 + マイク** を
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

## Mac で動かす

### 必要なもの

- Apple Silicon の Mac、macOS 14 (Sonoma) 以降
- **Xcode Command Line Tools**（Xcode 本体は不要）

```sh
xcode-select --install     # 未インストールなら
swift --version            # Swift 5.9 以降が出れば OK
```

### 手順

```sh
git clone https://github.com/aaa111aaa-111a/Video-VoiceRecorderForMac.git
cd Video-VoiceRecorderForMac
make app       # dist/OptiRecord.app を生成（3〜5 分程度）
make install   # /Applications へコピー
open /Applications/OptiRecord.app
```

`make app` は `swift build` に加えて、`.app` バンドルの組み立て・Info.plist の
生成・ad-hoc 署名までを行います（`Scripts/build-app.sh`）。

### 初回起動

**OptiRecord はメニューバー常駐アプリです。Dock にアイコンは出ず、ウインドウも
開きません。** 画面右上のメニューバーに ● アイコンが出ていれば起動しています。

1. ● アイコンをクリックすると権限の案内が出ます
2. **システム設定 > プライバシーとセキュリティ > 画面収録** で OptiRecord をオン
   （システム音声＝相手の声はこの権限に紐づいています。マイク権限ではありません）
3. **一度アプリを終了して起動し直す**（TCC の許可は再起動後に反映されます）
4. 自分の声も録るなら、同じ画面の **マイク** でも OptiRecord をオン

自分でビルドした ad-hoc 署名のアプリなので、**リビルドすると画面収録の許可が
リセットされることがあります**。その場合は一覧から OptiRecord を削除（−）して
から追加し直してください。

### ビルドせずに試す

CI が毎コミット `.app` を生成しています。GitHub の
[Actions](https://github.com/aaa111aaa-111a/Video-VoiceRecorderForMac/actions) から
最新の成功した CI 実行を開き、Artifacts の `OptiRecord-app` をダウンロードします。

```sh
cd ~/Downloads
unzip OptiRecord-app.zip      # 中に OptiRecord.zip が入っています
unzip OptiRecord.zip
xattr -dr com.apple.quarantine OptiRecord.app   # ダウンロード隔離属性を外す
cp -R OptiRecord.app /Applications/
```

### その他のコマンド

```sh
make build   # swift build のみ
make test    # ユニットテスト（142 件）
make clean   # dist/ とビルドキャッシュを削除
```

## 使い方

1. メニューバーの ● アイコンをクリック
2. 録画対象（会議アプリ / 画面）を選ぶ
3. **メーターが振れているか確認**（相手が喋っているのにシステム音声が動かないなら権限を疑う）
4. 「録画開始」または ⌃⇧R
5. 会議終了後にもう一度 ⌃⇧R。`~/Movies/OptiRecord/` に保存されます

## 現状

全モジュールが実装済みで、macOS 15 の CI 上でビルド・142 件のユニットテスト・
`.app` の生成と署名検証まで通っている。

**ただし実機での動作確認はまだ**。CI には画面もマイクも画面収録の権限も無いため、
「実際に相手の声が録れるか」「長時間録画で音がズレないか」は Apple Silicon Mac 上で
確かめる必要がある。チェックリストは [docs/TASKS.md](docs/TASKS.md) の Phase 3 に。

## 設計

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) を参照。
音が入らないときの切り分けは [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。
開発タスクの分解は [docs/TASKS.md](docs/TASKS.md)。

## ライセンス

MIT
