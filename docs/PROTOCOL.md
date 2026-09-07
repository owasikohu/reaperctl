# IPCプロトコル

この文書は`reaperctl.py`と`bridge.lua`間のPoCプロトコルを説明します。現時点では外部互換性を保証するバージョン付き公開仕様ではありません。

## IPCディレクトリ

既定値は各プログラムの隣にある`.reaper-agent/`です。設定の優先順位は次のとおりです。

1. CLIの`--ipc-dir`
2. `REAPER_AGENT_DIR`環境変数
3. `bridge.lua`または`reaperctl.py`の隣の`.reaper-agent/`

bridgeとCLIは、表記が異なっても同じ実体を指す必要があります。例としてWindowsの`C:\Users\me\reaper-ipc`とWSLの`/mnt/c/Users/me/reaper-ipc`は同じ場所です。

## ファイル名と状態遷移

`<id>`は`uuid.uuid4().hex`による32文字の小文字16進文字列です。

```text
request-<id>.tmp
        │ close → rename（要求を公開）
        ▼
request-<id>.lua
        │ rename（bridgeが取得）
        ▼
running-<id>.lua
        │ load → execute → JSON encode
        ▼
response-<id>.json.tmp
        │ close → rename（応答を公開）
        ▼
response-<id>.json
```

bridgeは`request-[a-f0-9]{32}.lua`だけを要求として扱います。`.tmp`や形式の違うファイルは無視します。close後のrenameを公開境界にすることで、書き込み途中の要求や応答を読みません。

## 要求形式

CLIはUTF-8 Luaの先頭へUnix timeの有効期限を付けます。

```lua
-- expires: 1788796800
return {track_count = reaper.CountTracks(0)}
```

bridge取得時に`os.time() < expires`を満たさなければ、Luaを実行せずエラー応答を返します。WSLとWindowsをまたぐ場合は両OSの時計を合わせてください。

## 実行順と並行要求

bridgeは各`reaper.defer()`コールバックで最大1要求を処理します。`request`から`running`へのrenameに成功したbridgeだけが実行します。

複数CLIを同時に使えますが、要求の選択順はファイルシステムとREAPERの列挙順に依存し、FIFOではありません。処理自体は1要求ずつです。観測に依存する編集は直列に実行してください。

## 応答形式

成功:

```json
{"id":"<id>","ok":true,"result":{"track_count":4}}
```

失敗:

```json
{"id":"<id>","ok":false,"error":"stack traceback ..."}
```

構文エラー、実行エラー、結果のJSON変換エラーは`error`へ入ります。CLIはobject、要求ID、booleanの`ok`、`result`または`error`を検証します。検証成功後に応答ファイルを削除し、同じJSONをstdoutへ出します。

## timeoutと不確定状態

```text
pending request ── timeout ──► CLIが削除（未実行）
running request ── timeout ──► REAPER内では継続（結果は不確定）
```

CLIがtimeoutした時点で要求がまだ`request`なら削除してキャンセルします。bridgeが既に`running`へrenameしていた場合、CLIは実行を止められません。timeoutやCtrl-C後に編集要求を自動再送せず、読み取り専用スクリプトで状態を再確認してください。

## クラッシュ後

異常終了時には`running-*`、遅着した`response-*`、`.tmp`が残る場合があります。bridgeは`running-*`を再実行しません。編集の二重実行を避けるためです。復旧手順は[トラブルシューティング](TROUBLESHOOTING.md#ipcファイルが残っている)を参照してください。

IPCディレクトリへ書き込めるプロセスは任意Luaを実行できます。IDと期限は認証機能ではありません。詳細は[Security](../SECURITY.md)を参照してください。
