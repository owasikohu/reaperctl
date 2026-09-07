# 開発と検証

## リポジトリ構成

```text
.
├── bridge.lua              # REAPER内で常駐するbridge
├── reaperctl.py            # Python標準ライブラリだけで動くCLI
├── examples/               # 観測・編集のReaScript例
├── tests/
│   ├── mock_reaper.lua     # 最小のREAPER APIモック
│   └── test_bridge.py      # CLIと実Lua VMを使う結合テスト
├── docs/
├── README.md
├── SECURITY.md
└── LICENSE
```

## 自動テスト

テストにはPython 3とLua 5.4が必要です。Lua実行ファイルがPATHにない場合は`LUA`で指定します。

```bash
python3 -m unittest discover -s tests -v

LUA=/path/to/lua \
  python3 -m unittest discover -s tests -v
```

Luaが見つからない環境ではLuaを使うテストはskipされます。本物の`bridge.lua`と`reaperctl.py`を実行し、REAPER固有APIだけを`mock_reaper.lua`へ置き換えています。

検証範囲:

- Hello → 状態取得 → 編集 → 再取得の往復
- 複数要求とID対応
- 構文、実行、JSON変換エラー後の復帰
- scalar、table、戻り値なしの変換
- 期限切れ要求と書き込み途中ファイルの無視
- bridge停止時のtimeoutと未取得要求の削除
- 存在しない入力ファイル

## 実機スモークテスト

未保存の空プロジェクトを開き、bridgeをRunしてから順番に実行します。

```bash
python3 reaperctl.py exec examples/hello.lua
python3 reaperctl.py exec examples/inspect_project.lua
python3 reaperctl.py exec examples/create_track.lua
python3 reaperctl.py exec examples/inspect_project.lua
```

Helloの`version`、画面と一致する初期状態、`Agent Test`の追加、トラック数の増加、REAPER Undo後の復元を確認します。bridge停止後の`--timeout 1`が終了コード124になることも確認します。

2026-09-07にWindows REAPER 7.79/x64とWSL Python CLIで上記を確認しました。4トラックのMIDI生成、VSTi挿入、状態再監査、48 kHz/24-bit/stereo WAVレンダーも同じ経路で確認しています。

macOS版、Linuxネイティブ版、WindowsローカルIPCの別配置、ネットワーク共有、OS異常終了時の全競合パターンは実機未検証です。

## 設計根拠

REAPERにはLua 5.4が組み込まれ、ReaScriptからREAPER APIを呼べます。本実装はLuaの`load(source, chunk_name, "t", env)`で要求をコンパイルし、実行環境から本物の`reaper` APIを参照します。

`reaper.defer(function)`はbridgeの常駐に使います。要求LuaはREAPERから呼ばれたcallback内で同期実行され、外部PythonスレッドからREAPER APIを直接呼びません。

`AddRemoveReaScript`で要求をActionへ登録し、`Main_OnCommand`で起動する方式も検討しました。しかしAction呼び出しにはLua戻り値の受け口がなく、結果IPCと要求ごとの登録・削除が別途必要です。組み込みLuaでの直接評価が実機で動作したため、PoCでは採用していません。

ファイルIPCではclose後のrenameを状態遷移に使い、書き込み途中の読み取りと同一要求の二重取得を避けます。詳細は[IPCプロトコル](PROTOCOL.md)を参照してください。

## 公式資料

- [REAPER ReaScript overview](https://www.reaper.fm/sdk/reascript/reascript.php)
- [REAPER ReaScript API functions](https://www.reaper.fm/sdk/reascript/reascripthelp.html)
- [Lua 5.4 `load`](https://www.lua.org/manual/5.4/manual.html#pdf-load)
- [REAPER 6.x changes: command-line ReaScript support](https://www.reaper.fm/download-old.php?ver=6x)
