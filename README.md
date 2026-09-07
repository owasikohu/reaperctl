# reaperctl

CLIエージェントから任意のLua/ReaScriptをREAPER内で実行し、戻り値をJSONで受け取るための小さなファイルIPCブリッジです。

DAW操作ごとの専用コマンドは持ちません。観測と編集はReaScriptに書き、`reaperctl`はそのスクリプトをREAPERへ渡して結果を返します。

```text
Codex / shell
    │  reaperctl exec script.lua
    ▼
request-<id>.lua ──► bridge.lua in REAPER ──► response-<id>.json
                           │
                           └─ reaper.CountTracks / MIDI_InsertNote / TrackFX_* / ...
```

現在はPoCです。ローカルで信頼できるLuaを同期実行する用途に絞っています。HTTP、socket、MCP、外部Pythonパッケージは使いません。

## 必要なもの

- REAPER 7.x
- CLI側のPython 3.8以降
- CLIとREAPERの双方から読み書きできるローカルディレクトリ

LuaはREAPERに組み込まれているため、別途インストールする必要はありません。REAPER側のPython設定も不要です。

## クイックスタート

1. このリポジトリをcloneします。
2. REAPERでActionsウィンドウ（既定では`?`）を開きます。
3. `ReaScript: Load...`から`bridge.lua`を選び、`Run`します。
4. リポジトリのルートでHelloを実行します。

```bash
python3 reaperctl.py exec examples/hello.lua
```

成功するとstdoutに1行のJSONが出ます。

```json
{"id":"42af47f39a424248bd6e004c3c30dc43","ok":true,"result":{"message":"Hello from REAPER","version":"7.79/x64"}}
```

続けて、状態取得と編集の往復を確認できます。

```bash
python3 reaperctl.py exec examples/inspect_project.lua
python3 reaperctl.py exec examples/create_track.lua
python3 reaperctl.py exec examples/inspect_project.lua
```

`create_track.lua`は現在のプロジェクトに`Agent Test`トラックを追加します。REAPERのUndoで戻せます。

bridgeの停止は、REAPERのActionsメニューに表示される実行中スクリプトから行います。REAPERを再起動した場合は、bridgeをもう一度Runしてください。同じIPCディレクトリに対してbridgeを複数起動しないでください。

## WSLからWindows版REAPERを使う

Windows側からWSLのファイルをUNCパスで参照できる環境では、起動済みREAPERへbridgeを直接渡せます。

```bash
"/mnt/c/Program Files/REAPER (x64)/reaper.exe" -nonewinst \
  "$(wslpath -w "$PWD/bridge.lua")"

python3 reaperctl.py exec examples/hello.lua
```

この構成では、Windows側の`\\wsl.localhost\<distribution>\...\.reaper-agent`とWSL側の`.reaper-agent/`が同じディレクトリを指します。起動済みbridgeがある場合、上のREAPER起動コマンドを重ねて実行しないでください。

WindowsからUNCパスを読み込めない場合や、WindowsローカルのIPCディレクトリを使う場合は[WSLと共有パスの設定](docs/TROUBLESHOOTING.md#wslとwindowsでipcパスが一致しない)を参照してください。

## CLI

```text
usage: reaperctl.py exec [-h] [--timeout SECONDS] [--ipc-dir PATH] script
```

例:

```bash
python3 reaperctl.py exec edit.lua
python3 reaperctl.py exec inspect.lua --timeout 30
python3 reaperctl.py exec inspect.lua --ipc-dir /path/shared/with/reaper
```

`--timeout`の既定値は10秒です。`--ipc-dir`を省略すると、`REAPER_AGENT_DIR`環境変数、またはリポジトリ直下の`.reaper-agent/`を使います。

終了コード:

| コード | 意味 |
|---:|---|
| `0` | Luaが完了し、結果を受信した |
| `1` | Lua、ファイルI/O、または応答形式のエラー |
| `2` | CLI引数エラー |
| `124` | timeout |
| `130` | CLIが中断された |

成功と実行エラーはstdoutの1行JSONです。引数エラーは`argparse`がstderrへ出します。機械処理では終了コードを確認してからJSONの`ok`と`result`または`error`を読んでください。

## ReaScriptを書く

通常のReaScript APIを呼び、最後にJSON化可能な値を`return`します。

```lua
local tracks = reaper.CountTracks(0)
local tempo = reaper.Master_GetTempo()

return {
  track_count = tracks,
  tempo = tempo,
}
```

`reaper.GetTrack`、`reaper.TrackFX_AddByName`、`reaper.MIDI_GetNote`などをそのまま利用できます。変更を加えるスクリプトでは、UndoブロックとUI更新をスクリプト自身で管理してください。

対応する戻り値、同期実行の制約、編集スクリプトの書き方は[ReaScriptガイド](docs/SCRIPTING.md)にまとめています。

## サンプル

| ファイル | 内容 | 副作用・前提 |
|---|---|---|
| [`hello.lua`](examples/hello.lua) | REAPER内での実行とバージョンを確認 | 読み取りのみ |
| [`inspect_project.lua`](examples/inspect_project.lua) | テンポとトラック一覧を返す | 読み取りのみ |
| [`create_track.lua`](examples/create_track.lua) | `Agent Test`トラックを追加 | プロジェクトを編集、Undo対応 |
| [`frog_song.lua`](examples/frog_song.lua) | 「かえるの合唱」のMIDIとReaSynthを追加 | プロジェクトを編集、REAPER標準ReaSynthを使用 |
| [`electronic_16bars.lua`](examples/electronic_16bars.lua) | 140 BPM、A minor、16小節の4トラック曲を生成 | **既存トラックとマーカーを削除**。SIシリーズとVitalが必要、Undo対応 |

最後の2つはbridgeの最小動作確認ではなく、CLIエージェントが観測・編集を繰り返せることを示す応用例です。特に`electronic_16bars.lua`は空のテストプロジェクトで実行してください。

## ドキュメント

- [ReaScriptガイド](docs/SCRIPTING.md) — 戻り値、Undo、観測と編集、制約
- [IPCプロトコル](docs/PROTOCOL.md) — request/response、原子性、並行実行、timeout
- [トラブルシューティング](docs/TROUBLESHOOTING.md) — 起動、WSL、timeout、残留ファイル
- [開発と検証](docs/DEVELOPMENT.md) — テスト、実機確認、設計根拠
- [Security](SECURITY.md) — 信頼境界と脆弱性報告

## スコープ

このリポジトリが担当するのは「LuaをREAPERで実行し、結果を返す」部分です。DAW操作別のCLI/MCP API、ネットワーク実行、認証、Luaサンドボックス、非同期ReaScript、実行中Luaの強制停止、トランザクションロールバックは現在のスコープ外です。

## License

[BSD 3-Clause License](LICENSE)
