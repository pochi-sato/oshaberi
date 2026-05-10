# zundamon-stop

Claude Code の応答完了 / subagent 完了時に、VOICEVOX のずんだもんが
**「○○さん、{プロジェクト名}のくろーどから○○が来ているよ」** と喋ってくれる仕組み。

このリポは「ソースを git で管理したい / 自分でカスタマイズしたい」派向けの **clone & symlink** セットアップ手順を提供する。プロンプトだけ Claude Code に投げて作ってもらいたい派は [zundamon-stop-setup.md](./zundamon-stop-setup.md) を参照。

## 仕組み

- Claude が応答末尾に `[1]`〜`[8]` の **intent タグ**を書く (= 「質問 / 完了報告 / プラン提示 / 進めて良いか」等の分類)
- Claude Code の **Stop hook** が応答完了で発火 → `zundasay-stop` シェルスクリプトを叩く
- スクリプトが intent タグから定型フレーズを引いて、**VOICEVOX engine** で発声
- mkdir lock で複数発声が直列化される (= 重ならない)

LLM spawn 不要 / Anthropic API key 不要 / Claude Code サブスクで完結。

## ファイル一覧

```
oshaberi/
├── bin/
│   ├── zundasay              # text → VOICEVOX → afplay
│   └── zundasay-stop         # Stop hook handler (intent タグ抽出 + zundasay 呼び出し)
├── rules/
│   └── intent-tag.md         # Claude への intent タグ書込みルール
├── project-names.example.json # 読み方マップのテンプレ
├── install.sh                 # symlink 一発セットアップ
├── README.md                  # このファイル (= ソース派向け)
└── zundamon-stop-setup.md     # プロンプト派向け
```

## 前提条件

- **macOS** (Linux / Windows は対応外、`afplay` 依存)
- **VOICEVOX engine** がローカルで動いてる (`http://127.0.0.1:50021`)
  - 一番楽: VOICEVOX.app をインストールして起動 <https://voicevox.hiroshiba.jp/>
  - GUI を出したくない: launchd で常駐 (本リポ範囲外、各自対応)
- **Claude Code** インストール済み
- macOS 標準の `jq` `python3` `afplay`

確認:

```bash
curl -s --max-time 3 http://127.0.0.1:50021/version  # "0.X.X" が出れば OK
which jq python3 afplay
```

## セットアップ

### 1. clone

```bash
git clone git@github.com:pochi-sato/oshaberi.git
cd oshaberi
```

### 2. install (symlink を張る)

```bash
./install.sh
```

これで以下の symlink が張られる:

- `~/.local/bin/zundasay` → `<repo>/bin/zundasay`
- `~/.local/bin/zundasay-stop` → `<repo>/bin/zundasay-stop`
- `~/.claude/rules/intent-tag.md` → `<repo>/rules/intent-tag.md`

`~/.local/share/zundasay/project-names.json` は **user-local** (= リポ管理外、自分の読み方マップ)。
初回 install 時に `project-names.example.json` から **コピー**で初期化される。
編集しても git に影響しない。

### 3. ユーザー名を環境変数で指定 (任意)

`~/.zshrc` の末尾に:

```bash
export ZUNDASAY_USER=あなたの呼ばれたい名前
```

これで「{name}さん、...」と呼ばれる。未設定時は **"たくてぃむ"** (デフォルト)。

ターミナル再起動 / `source ~/.zshrc` で反映。

### 4. PATH 確認

`~/.local/bin` が PATH に通ってない場合:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

確認:

```bash
which zundasay   # → /Users/<you>/.local/bin/zundasay
```

### 5. Claude Code の hooks 設定

`~/.claude/settings.json` の `hooks` セクションに以下をマージ (`YOUR_USERNAME` は `whoami` の結果に置換):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -Rs '{hookSpecificOutput:{hookEventName:\"UserPromptSubmit\",additionalContext:.}}' < ~/.claude/rules/intent-tag.md"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/YOUR_USERNAME/.local/bin/zundasay-stop"
          }
        ]
      }
    ]
  }
}
```

既存に `UserPromptSubmit` / `Stop` がある場合は **配列に追加** (上書きしない)。

設定後、JSON が valid か:

```bash
jq . ~/.claude/settings.json > /dev/null && echo OK
```

### 6. 動作確認

```bash
zundasay "セットアップ完了したのだ"
```

→ 聞こえれば `zundasay` 動作 OK。

```bash
echo '{"hook_event_name":"Stop","cwd":"'$PWD'","last_assistant_message":"テスト [2]"}' \
  | ~/.local/bin/zundasay-stop
```

→ 数秒後に「{name}さん、oshaberiのくろーどから完了報告が来ているよ」と聞こえれば OK。

新規 Claude Code セッションで何か聞いて、応答完了時に発火すれば全部動いてる。

## カスタマイズ

### 発話フレーズ変更

`bin/zundasay-stop` の `intent_to_phrase` 関数を編集して push (= symlink なので即反映、再 install 不要)。

### キャラ on/off + idle 通知 on/off

`~/.local/share/zundasay/config.json` を直接編集 (= user-local、リポ管理外、`config.example.json` がテンプレ):

```json
{
  "active_characters": ["ずんだもん", "四国めたん"],
  "notify_idle": false
}
```

- `active_characters`: random pool に入れたいキャラ。リストから外したキャラは呼ばれない。空配列にすると全キャラ復活 (= fallback)。利用可能なキャラ: `ずんだもん` / `四国めたん` / `春日部つむぎ` / `冥鳴ひまり` / `もち子さん`
- `notify_idle`: `false` で「じっとしてるよ」(idle_prompt 通知) を発声しない。permission_prompt は別なので発声し続ける

### プロジェクト名読み方マップ

`~/.local/share/zundasay/project-names.json` を直接編集 (= user-local、リポ管理外):

```json
{
  "oshaberi": "おしゃべり",
  "my-app": "マイアプリ"
}
```

key = cwd basename。worktree suffix (`--claude-worktrees-*` や `/.claude/worktrees/*`) は zundasay-stop が自動除去するので、key には**元の pj 名**を書けば worktree からも効く。

### subagent 完了通知を有効にする

`~/.claude/settings.json` の `hooks` に追加:

```json
"SubagentStop": [
  {
    "hooks": [
      { "type": "command", "command": "/Users/YOUR_USERNAME/.local/bin/zundasay-stop" }
    ]
  }
]
```

(うるさいので注意。Agent ツールが終わるたびに発声する)

### 一時的に発声 OFF

`~/.claude/settings.json` の `Stop` block を削除 (JSON はコメント不可なので削除推奨、復活は同じ block を書き戻す)。

### Speaker (= ずんだもんのスタイル) 変更

`zundasay` のデフォルトは speaker=3 (ずんだもん/ノーマル)。あまあま=1 / ツンツン=7 / セクシー=5 / ささやき=22 等。

```bash
zundasay "あまあまボイス" 1
```

恒久設定 (`~/.zshrc`):

```bash
export VOICEVOX_SPEAKER=1
```

## トラブルシュート

- **発声しない**:
  1. VOICEVOX engine 生死: `curl localhost:50021/version`
  2. hook 発火履歴: `tail ~/.local/share/zundasay/hook.log`
  3. `last_assistant_message` に `[N]` が含まれてるか
- **タグが応答に付かない**: `~/.claude/rules/intent-tag.md` の symlink が張られてるか + settings.json の UserPromptSubmit hook
- **同時発声で重なる**: `rm -rf /tmp/zundasay.lockdir` で残骸 lock 解除
- **VOICEVOX.app が邪魔 / GUI 出したくない**: launchd で engine 単体常駐 (本リポ範囲外、別途対応)

## ライセンス

(未設定)
