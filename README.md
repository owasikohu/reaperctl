# reaperctl

任意のLua/ReaScriptをCLIからREAPER内で同期実行し、戻り値をJSONで受け取る最小ブリッジです。
操作コマンドの個別実装、HTTP、socket、MCP、外部Pythonパッケージは不要です。

```text
reaperctl.py → request-<uuid>.lua → bridge.lua (REAPER) → response-<uuid>.json → stdout
```

## 起動と実行

必要なものはREAPER 7.xとCLI用Python 3.8以降です。REAPER側のPython設定は不要です。
このリポジトリのルートに`bridge.lua`、`reaperctl.py`、`examples/`があります。

1. REAPERのActionsウィンドウで「ReaScript: Load」から`bridge.lua`を読み込み、Runします。
2. 同じディレクトリから次のコマンドを実行します（`python`がない環境では`python3`）。

```bash
python3 reaperctl.py exec examples/hello.lua
python3 reaperctl.py exec examples/inspect_project.lua
python3 reaperctl.py exec examples/create_track.lua
python3 reaperctl.py exec examples/inspect_project.lua
```

成功時のstdout例:

```json
{"id":"42af47f39a424248bd6e004c3c30dc43","ok":true,"result":{"message":"Hello from REAPER","version":"7.79/x64"}}
```

終了コードは成功`0`、Lua/入出力/応答エラー`1`、引数エラー`2`、timeout`124`、中断`130`です。
実行結果とエラーはstdoutの1行JSON、引数エラーはargparseのstderrです。
待機時間は`exec ... --timeout 30`で変更でき、既定値は10秒です。

停止はREAPERのActionsメニューにある実行中スクリプトから行います。
同じIPCディレクトリに対してブリッジは1個だけ起動してください。
通常の起動では自動常駐設定は行いません。REAPER再起動後は再度Runしてください。

## WSLのCLIからWindowsのREAPERを操作する

Windows側からWSLのファイルをUNCパスで直接開けます。この環境では次で起動できました。
既にbridgeが常駐している場合は再実行しないでください。

```bash
"/mnt/c/Program Files/REAPER (x64)/reaper.exe" -nonewinst \
  "$(wslpath -w "$PWD/bridge.lua")"
python3 reaperctl.py exec examples/hello.lua
```

この場合、Windows側は`\\wsl.localhost\Ubuntu\home\owata\reaperctl\.reaper-agent`、
WSL側は`/home/owata/reaperctl/.reaper-agent`を読み書きします。同じ実体なのでパス変換をIPCに組み込む必要はありません。
`-nonewinst`で既存インスタンスにスクリプトを渡す機能は[公式変更履歴](https://www.reaper.fm/download-old.php?ver=6x)に記載されています。
WSLからWindows実行ファイルを起動できない場合は、WindowsのActions画面から上記UNCパスの`bridge.lua`を読み込んでください。

既定のIPCは各ファイルの隣の`.reaper-agent/`です。別の場所に置く場合は、
REAPER起動前に環境変数`REAPER_AGENT_DIR`をWindowsが解釈できる絶対パスに設定し、
CLIには同じ実体を指す`--ipc-dir`または`REAPER_AGENT_DIR`を指定します。
例えばWindowsの`C:\Users\owata\reaper-agent-ipc`とWSLの`/mnt/c/Users/owata/reaper-agent-ipc`です。
起動済みREAPERには、後からシェルで設定した環境変数は反映されません。

## スクリプトの契約

普通のReaScript APIを使い、最後にJSON化できる値を`return`します。

```lua
return {track_count = reaper.CountTracks(0), tempo = reaper.Master_GetTempo()}
```

`reaper.GetTrack`、`reaper.TrackFX_AddByName`、`reaper.MIDI_GetNote`などをそのまま呼べます。
利用可能なAPIはインストール済みREAPERと拡張機能に依存します。
操作・観測のロジックは送信するLuaに書いてください。

- UTF-8のLuaソースを送信します。最初の戻り値だけが`result`になり、戻り値なしは`null`です。
- 文字列、有限数、boolean、文字列キーのtable、1から連続する配列tableを扱えます。空tableは`{}`です（空配列との区別はしません）。
- userdata（トラック等のハンドル）、関数、循環参照、疎な配列、NaN/無限大、不正UTF-8はエラーです。ハンドルは名前・GUID等に変換してください。
- `print`や`ShowConsoleMsg`はCLIの結果として回収しません。結果は`return`してください。
- 要求は同期完了が前提です。`reaper.defer`、`runloop`、`atexit`の直接呼び出しはエラーにします。非同期処理の完了待ちは実装していません。
- `get_action_context()`はブリッジのコンテキストです。送信元ファイルの相対パスや独立したAction IDは再現しません。`require`等には必要な絶対パス/package.pathを設定してください。
- 編集のUndoブロックやUI更新はLua側で管理します。例の`create_track.lua`はUndo点を作ります。

## 実装と公式資料の確認

[REAPERのReaScript解説](https://www.reaper.fm/sdk/reascript/reascript.php)はLua 5.4の組み込みと標準Luaマニュアルを案内しています。
[Lua公式のload](https://www.lua.org/manual/5.4/manual.html#pdf-load)はテキストチャンクと実行環境を指定できます。
本実装では`load(source, name, "t", env)`でコンパイルし、環境から実際の`reaper` APIを参照します。
`xpcall`で構文・実行・JSON変換の失敗を応答にします。実行環境は要求ごとに作りますが、標準ライブラリ等は共有です。

[REAPER API定義](https://www.reaper.fm/sdk/reascript/reascripthelp.html)で確認した関連機能:

- `defer(function)`はREAPERに次回コールバックを登録します。API呼び出しはこのホスト側コールバック内で直列に実行し、外部スレッドからREAPER APIを呼びません。UI/main thread制約を踏まえ、1コールバックにつき1要求です。
- `AddRemoveReaScript(true, 0, scriptfn, true)`はMainセクションに登録し、command ID（失敗なら0）を返します。`Main_OnCommand(command, 0)`で登録Actionを呼べます。ただしAction呼び出し自体にはLua戻り値の受け口がなく、別途結果IPCが必要です。本PoCでは直接Lua実行が実機で動いたため登録方式は採用していません。
- 別Luaモジュールの読み込みには`require`も案内されています。
- `EnumerateFiles(path, -1)`で列挙キャッシュを更新し、0からのインデックスで要求を検出します。
- deferスクリプトは自動Undo点を作らないため、編集例では明示的にUndo APIを呼びます。

要求ファイルは有効期限コメントとLua本文です。CLIはUUIDと期限を付けて`.tmp`へ書き、close後にrenameして公開します。
bridgeは`request-<id>.lua`を`running-<id>.lua`へrenameして取得し、期限を確認して実行します。
応答も`.tmp`からrenameして公開します。CLIはIDを検証し、受け取った応答を削除します。
並列CLIの応答はIDで分離されますが、要求の実行順は保証しません。観測→編集→観測は順番にCLIを待ってください。

## timeoutと運用上の範囲

timeoutはCLIの待機期限です。未取得要求はCLIが削除し、残った期限切れ要求もbridgeが実行前に拒否します。
期限は両側のOS時刻で比較するため、WSLとWindowsの時計を合わせてください。期限の丸めには最大約1秒の差があります。
取得とキャンセルの競合、実行開始後のtimeoutや中断では、編集済みかどうかを断定できません。
自動再送はしません。再観測してから次の操作を決めてください。

無限ループや長時間の同期処理はREAPERのUIを止めます。強制停止・ロールバック・クラッシュ後の再実行保証はありません。
処理途中のエラーでも編集が一部残る可能性があります。
異常終了後の`running-*`や遅着した`response-*`は再実行しません。必要ならbridgeとCLIを止めて該当ファイルを手動削除してください。
IPCの書き込み失敗ではbridgeがコンソールにエラーを出して停止します。

これは任意コードをREAPERと同じ権限で実行する仕組みで、サンドボックスではありません。
IPCは自分だけが書き込めるローカルディレクトリに置き、信頼できるLuaを送ってください。
WindowsのACLや既存ディレクトリの権限は変更しません。ネットワーク共有・同期ストレージは検証対象外です。

## 検証

```bash
python3 -m unittest discover -s tests -v
# Luaの場所を明示する場合:
LUA=/path/to/lua python3 -m unittest discover -s tests -v
```

Lua 5.4で実際のbridgeを実行し、REAPER APIのみをモックに置き換えます。
往復編集、並列ID対応、構文/実行/シリアライズエラー後の復帰、期限切れ、書き込み途中ファイル無視、timeout、戻り値を検証します。
Luaがない場合、Luaを使うテストはskipされます。

2026-09-07、この環境でWindows REAPER **7.79/x64**とWSL Python CLIの実機テストも実施しました。
`hello.lua`が実機バージョンを返し、`inspect_project.lua`→`create_track.lua`→`inspect_project.lua`で
トラック数が**1→2**となり、追加トラック名が**Agent Test**であることを確認しました。テンポは120でした。
追加トラックは残してあり、プロジェクトの保存は行っていません。

別環境では空のテストプロジェクトを開き、冒頭の4コマンドを順に実行してください。
Helloのバージョン、取得したテンポ、トラック数の+1、画面上のAgent Testを照合します。
REAPERでUndoしてから再取得すれば、元のトラック数へ戻ることも確認できます。
bridge停止後に`--timeout 1`で実行し、約1秒で終了コード124になることを確認してください。
macOS/Linux版REAPER、WindowsローカルIPCへの別配置、REAPER異常終了時の挙動は実機未検証です。
