# トラブルシューティング

## `timeout`になる

次を順に確認します。

1. REAPERが起動している
2. Actionsメニューの実行中スクリプトに`bridge.lua`がある
3. bridgeとCLIが同じIPCディレクトリを見ている
4. REAPERのReaScript consoleに`ReaScript bridge stopped:`が出ていない
5. WSLとWindowsの時計が合っている

bridgeが要求を取得した後にtimeoutした可能性があります。編集をすぐ再実行せず、`inspect_project.lua`などで結果を確認してください。

## bridgeがconsoleへエラーを出して停止した

ディレクトリ作成、要求読み込み、応答公開の失敗では、bridgeはエラーをconsoleへ表示して停止します。パス、書き込み権限、空き容量を直してから再度Runします。

Lua要求の通常の構文・実行エラーではbridgeは停止せず、CLIへ`ok:false`を返して次の要求を処理します。

## WSLとWindowsでIPCパスが一致しない

Windowsローカルの専用ディレクトリを共有できます。

```text
Windows: C:\Users\me\reaper-agent-ipc
WSL:     /mnt/c/Users/me/reaper-agent-ipc
```

REAPERを起動するWindows環境では`REAPER_AGENT_DIR`にWindows形式の絶対パスを設定し、REAPERを再起動します。起動済みREAPERには後から設定した環境変数が反映されません。

WSL側では同じ実体を指定します。

```bash
export REAPER_AGENT_DIR=/mnt/c/Users/me/reaper-agent-ipc
python3 reaperctl.py exec examples/hello.lua
```

またはCLIごとに`--ipc-dir /mnt/c/Users/me/reaper-agent-ipc`を指定します。

## IPCファイルが残っている

REAPERのActionsメニューからbridgeを停止し、関連CLIが終了していることを確認してから一覧を見ます。

```bash
find .reaper-agent -maxdepth 1 -type f -print
```

| ファイル | 意味 |
|---|---|
| `request-*.lua` | 未取得要求 |
| `running-*.lua` | bridgeが取得済み。実行済みかもしれない |
| `response-*.json` | CLIが受け取らなかった応答 |
| `*.tmp` | 書き込みが完了しなかった一時ファイル |

REAPERの状態とファイル内容を確認し、対象が明確なものだけを削除します。`running`を`request`へ戻すと編集が二重実行される可能性があります。

## `Invalid bridge response`になる

同じIDの応答が壊れているか、手動で置いたファイルがプロトコルに合っていません。同じIPCディレクトリを複数実装や複数bridgeで共有していないか確認してください。不正な応答は自動削除されません。

## `JSON cannot encode ...`になる

戻り値にハンドル、関数、循環参照、疎な配列、NaNなどが含まれています。[戻り値の仕様](SCRIPTING.md#戻り値)に従い、名前、GUID、番号などへ変換してください。

## FXが見つからない

REAPERのFX browserで表示される名前と`TrackFX_AddByName`の指定が一致しているか、plugin scanが完了しているか確認します。外部VSTiを使うサンプルは、その環境に同じpluginがなければ動きません。最小確認には`hello.lua`、`inspect_project.lua`、`create_track.lua`を使ってください。

## REAPERのUIが固まった

要求はREAPERのUI/main threadで同期実行されます。無限ループ、長い待機、重い処理がないか確認してください。CLIのtimeoutは開始済みLuaを強制停止しません。

REAPER側で停止できない場合は、未保存変更を考慮してREAPERプロセスを終了する必要があります。再起動後は残留IPCファイルを確認してください。
