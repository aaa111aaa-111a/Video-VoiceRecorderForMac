# 契約変更の提案

Phase 1 の各ワークストリームが `AizuchiCore` の契約に不足を見つけた際、勝手に
`Sources/AizuchiCore/` を変更せず、ここに提案を追記する。Phase 2 の統合担当が
まとめて判断する。

---

## B (AizuchiCapture): `RecordingConfiguration` に `excludesOwnWindows` が無い

`RecordingSettings.excludesOwnWindows`（ユーザーが「自分のウインドウを録画から除外
する」を切り替えられる設定）はあるが、キャプチャ層が実際に受け取る
`RecordingConfiguration`（`RecordingConfiguration.resolve(settings:...)` の出力）
にはこのフラグが含まれていない。

`ScreenCapturing.start(target:configuration:)` は `RecordingConfiguration` しか
受け取らないため、`SCStreamScreenCapturer` はユーザーの設定を見る手段がない。

**現在の実装での対応**: `Sources/AizuchiCapture/Filtering/ContentFilterBuilder.swift`
の `bundleIdentifiersToExcludeFromDisplay` は、`.display` ターゲットのキャプチャで
常に Aizuchi 自身（`Bundle.main.bundleIdentifier`）を除外リストに入れる（無条件）。
タスク仕様（`docs/TASKS.md` B 節）の記述通りだが、ユーザーが設定でこれをオフに
できない。

**提案**: `RecordingConfiguration` に `excludesOwnWindows: Bool` を追加し、
`RecordingConfiguration.resolve(settings:...)` で `settings.excludesOwnWindows` を
渡すようにする。そうすれば `SCStreamScreenCapturer` はこの値を見て除外の有無を
切り替えられる。
