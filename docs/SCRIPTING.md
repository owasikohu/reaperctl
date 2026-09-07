# ReaScriptガイド

`reaperctl`へ渡すファイルは、REAPERのLua 5.4で実行される通常のReaScriptです。bridge独自のAPIはありません。REAPERの状態は`reaper.*`で読み書きし、CLIへ返す値をトップレベルから`return`します。

## 観測する

ハンドルそのものはJSONにできないため、名前、GUID、番号、数値へ変換して返します。

```lua
local tracks = {}
for index = 0, reaper.CountTracks(0) - 1 do
  local track = reaper.GetTrack(0, index)
  local _, name = reaper.GetTrackName(track)
  local _, guid = reaper.GetSetMediaTrackInfo_String(track, "GUID", "", false)
  tracks[#tracks + 1] = {index = index, name = name, guid = guid}
end
return {tracks = tracks}
```

ポインタを後続のCLI呼び出しへ持ち越さず、再観測してGUIDなどから対象を解決してください。

## 編集する

変更はUndoブロックにまとめ、必要に応じてarrange viewを更新します。

```lua
local result
reaper.Undo_BeginBlock()
local ok, err = xpcall(function()
  local index = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(index, true)
  local track = assert(reaper.GetTrack(0, index))
  assert(reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "Agent Track", true))
  result = {index = index, name = "Agent Track"}
end, debug.traceback)
reaper.Undo_EndBlock("Agent: create track", -1)
if not ok then error(err) end
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
return result
```

`Undo_EndBlock`はエラー時にも呼ばれる形にしてください。ただし、失敗時に変更が自動ロールバックされるわけではありません。破壊的な編集では対象を先に観測し、実行後にもう一度観測してください。

## MIDIを扱う

MIDI位置はitem固有のPPQへ変換してから挿入します。

```lua
local start_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, 0)
local end_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, 1)
assert(reaper.MIDI_InsertNote(take, false, false, start_ppq, end_ppq,
  0, 69, 90, true)) -- channel 1, A4, defer sorting
reaper.MIDI_Sort(take)
```

大量のイベントでは`noSortIn=true`で挿入し、最後に一度`MIDI_Sort`を呼ぶと効率的です。編集後は`MIDI_CountEvts`と`MIDI_GetNote`でノート数、音域、重複を読み戻せます。

## 戻り値

bridgeは最初の戻り値をJSONへ変換します。戻り値がない場合は`null`です。

| Lua | JSON |
|---|---|
| `nil` | `null` |
| `boolean` | boolean |
| 有限の`number` | number |
| UTF-8の`string` | string |
| 1から連続する非空table | array |
| 文字列キーのtable | object |
| 空table | `{}` |

REAPERのハンドルを含む`userdata`、関数、thread、循環参照、疎な配列、0始まりの数値キー、NaN、無限大、不正UTF-8は変換エラーになります。複数値はtableにまとめてください。`print`や`reaper.ShowConsoleMsg`はCLIへ転送されないため、診断情報も戻り値へ含めます。

## 実行環境と制約

bridgeは要求ごとに新しい環境tableを作り、実際の`reaper` APIを参照させます。Lua標準ライブラリはREAPERプロセスと共有されます。セキュリティ用サンドボックスではありません。

送信したコードはbridgeの`reaper.defer()`コールバック内で、1要求ずつ同期実行されます。要求内での`reaper.defer`、`reaper.runloop`、`reaper.atexit`はエラーになります。無限ループや長時間の処理はREAPERのUIを停止させます。

`reaper.get_action_context()`が返すのは送信元Luaではなくbridgeのコンテキストです。`require`は利用できますが、モジュール探索はREAPERプロセスの`package.path`に従います。

## エージェント向けの実行ループ

1. 読み取り専用スクリプトで対象、GUID、範囲、FXを観測する
2. Undo対応の編集スクリプトを実行する
3. 別の読み取り専用スクリプトで結果を検証する
4. 必要なら修正し、最後にレンダーや保存を実行する

並行CLI要求の実行順は保証されません。依存する観測と編集は、前のCLIプロセスが終了してから次を実行してください。

## 公式リファレンス

- [REAPER ReaScript overview](https://www.reaper.fm/sdk/reascript/reascript.php)
- [REAPER ReaScript API functions](https://www.reaper.fm/sdk/reascript/reascripthelp.html)
- [Lua 5.4 reference manual](https://www.lua.org/manual/5.4/)
