# リリース手順

## 個人利用（署名なし）

```sh
make app
make install
```

ad-hoc 署名なので Gatekeeper の警告は出ませんが（自分でビルドしたバイナリのため）、
**リビルドのたびに画面収録の許可がリセットされることがあります**。

## 配布する場合（Developer ID + notarize）

Apple Developer Program（年 $99）が必要です。

```sh
# 1. Developer ID Application 証明書で署名
./Scripts/build-app.sh --configuration release --sign "Developer ID Application: YOUR NAME (TEAMID)"

# 2. zip に固める（.app のまま notarize はできない）
ditto -c -k --keepParent dist/Aizuchi.app dist/Aizuchi.zip

# 3. notarize（初回は認証情報を keychain に保存）
xcrun notarytool store-credentials "AC_PASSWORD" \
    --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"

xcrun notarytool submit dist/Aizuchi.zip --keychain-profile "AC_PASSWORD" --wait

# 4. チケットを .app に添付して再度 zip
xcrun stapler staple dist/Aizuchi.app
ditto -c -k --keepParent dist/Aizuchi.app dist/Aizuchi.zip
```

## 注意

- **Hardened Runtime が必須**です（`build-app.sh` は `--options runtime` を付けています）
- entitlements に `com.apple.security.device.audio-input` が必要
- App Sandbox は有効にしていません。有効にする場合は、ユーザーが選んだ保存先を
  security-scoped bookmark で保持する実装が前提になります（`RecordingSettings.outputDirectoryBookmark`）
- 画面収録の TCC は **bundle id + 署名** に紐づきます。署名 ID を変えると許可が外れます

## バージョン

`Sources/AizuchiCore/AppInfo.swift` の `version` が唯一の真実で、
`build-app.sh` が Info.plist に流し込みます。ビルド番号は `git rev-list --count HEAD`。
