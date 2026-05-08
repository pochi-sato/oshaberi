# ずんだもん Stop 通知 — Claude Code 用セットアップガイド

Claude Code (claude.ai/code の CLI) で、応答完了 / subagent 完了時にずんだもんが
「○○さん、{プロジェクト名}のくろーどから○○が来ているよ」と喋ってくれる仕組みを構築する手順書。

## どう動くか

- Claude が応答末尾に **`[1]`〜`[8]` のカテゴリ番号** (intent タグ) を自分で書く
- Claude Code の **Stop hook** が応答完了時に shell スクリプトを叩く
- スクリプトが intent タグを正規表現で抜き、定型フレーズに変換して **VOICEVOX engine** を叩いて発声
- 同時に複数発声しないよう mkdir lock で直列化

LLM spawn 不要 / Anthropic API key 不要 / Claude Code サブスクで完結。

## 前提条件 (= Claude Code に任せず自分でやってください)

1. **macOS** (Linux / Windows は本ガイド対象外)
2. **VOICEVOX.app** をインストールして起動: <https://voicevox.hiroshiba.jp/>
   起動すると自動で `http://127.0.0.1:50021` でエンジンが立ち上がる
3. **Claude Code** をインストール済み (`claude` コマンドが叩ける)
4. macOS 標準の `jq` `python3` `afplay` があれば OK

確認コマンド:

```bash
curl -s --max-time 3 http://127.0.0.1:50021/version  # "0.X.X" が出れば engine OK
which jq python3 afplay                              # 全て path が出れば OK
```

## Claude Code に投げるプロンプト

新規 Claude Code セッションを開いて、以下の **`---PROMPT START---` から `---PROMPT END---` まで** をそのままコピペしてください。

---PROMPT START---

VOICEVOX (ずんだもん) で Claude Code の応答完了を音声通知する仕組みをセットアップしてほしい。以下の手順を上から順に進めて、各ステップで結果を私に報告してから次へ進んでほしい。

## STEP 0. 前提確認

下記コマンドで前提を確認:

```bash
curl -s --max-time 3 http://127.0.0.1:50021/version
which jq python3 afplay
ls ~/.local/bin 2>/dev/null && echo "~/.local/bin exists"
echo "$PATH" | tr ':' '\n' | grep -F "$HOME/.local/bin" && echo "PATH OK" || echo "PATH MISSING"
```

VOICEVOX engine に繋がらなければ「VOICEVOX.app を起動してから再開してください」と私に伝えて止まる。`~/.local/bin` が PATH に無ければ `~/.zshrc` の末尾に `export PATH="$HOME/.local/bin:$PATH"` を追記する (既存に同等の行があれば何もしない)。

## STEP 1. 名前を確認

私 (ユーザー) に「ずんだもんに呼ばれたい名前」を聞いて。例: 「太郎」「Alice」など。聞いたらメモして以降のスクリプト中に使う ($USER_NAME と表記)。

## STEP 2. zundasay スクリプト

`~/.local/bin/zundasay` を作成 (`mkdir -p ~/.local/bin`):

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: zundasay <text> [speaker_id]
  default speaker = 3 (ずんだもん/ノーマル)
  env: VOICEVOX_URL (default http://127.0.0.1:50021)
       VOICEVOX_SPEAKER (default 3)
EOF
  exit 1
}

text="${1:-}"
[ -z "$text" ] && usage

speaker="${2:-${VOICEVOX_SPEAKER:-3}}"
engine="${VOICEVOX_URL:-http://127.0.0.1:50021}"

if ! curl -s --max-time 2 "${engine}/version" >/dev/null; then
  echo "zundasay: VOICEVOX engine に繋がらない (${engine})" >&2
  echo "  → VOICEVOX.app を起動するか、エンジンを立ち上げてね" >&2
  exit 2
fi

q=$(mktemp -t zundasay_query)
w=$(mktemp -t zundasay_wav).wav

curl -sS --fail -X POST \
  --get \
  --data-urlencode "text=${text}" \
  --data-urlencode "speaker=${speaker}" \
  "${engine}/audio_query" > "$q"

curl -sS --fail -X POST \
  -H "Content-Type: application/json" \
  --data @"$q" \
  --output "$w" \
  "${engine}/synthesis?speaker=${speaker}"

LOCKDIR="${TMPDIR:-/tmp}/zundasay.lockdir"
LOCK_TIMEOUT=60
LOCK_START=$SECONDS
while ! mkdir "$LOCKDIR" 2>/dev/null; do
  if (( SECONDS - LOCK_START > LOCK_TIMEOUT )); then
    rm -rf "$LOCKDIR"
    mkdir "$LOCKDIR" 2>/dev/null || true
    break
  fi
  sleep 0.1
done
trap 'rm -f "$q" "$w"; rm -rf "$LOCKDIR"' EXIT INT TERM

afplay "$w"
```

`chmod +x ~/.local/bin/zundasay` で実行権を付与。

動作確認: `zundasay "セットアップ中なのだ"` で「セットアップ中なのだ」と聞こえれば OK。

## STEP 3. プロジェクト名読み方マップ

`~/.local/share/zundasay/project-names.json` を作成 (空辞書で OK、後で追加できる):

```bash
mkdir -p ~/.local/share/zundasay
cat > ~/.local/share/zundasay/project-names.json <<'JSON'
{}
JSON
```

例: 後で `my-app` を「マイアプリ」と読ませたければ `{"my-app": "マイアプリ"}` を書く。未登録の pj はそのまま VOICEVOX に渡される。

## STEP 4. Stop hook ハンドラ

`~/.local/bin/zundasay-stop` を作成。**STEP 1 で聞いた名前を `__USER_NAME__` の部分に置換**してから書き込む:

```bash
#!/usr/bin/env bash
set -euo pipefail

export PATH="/Users/$(whoami)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

INPUT=$(cat)

LOG_DIR="${HOME}/.local/share/zundasay"
LOG="${LOG_DIR}/hook.log"
mkdir -p "$LOG_DIR"
{
  echo "---$(date -Iseconds)---"
  echo "$INPUT"
} >> "$LOG"

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "Stop"')
LAST_MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')

PJ_BASENAME=""
if [ -n "$CWD" ]; then
  PJ_PATH=$(echo "$CWD" | sed 's|/\.claude/worktrees/.*||')
  PJ_BASENAME=$(basename "$PJ_PATH" | sed 's/--claude-worktrees-.*//')
fi

PJ_DICT="${HOME}/.local/share/zundasay/project-names.json"
if [ -f "$PJ_DICT" ] && [ -n "$PJ_BASENAME" ]; then
  PJ_NAME=$(jq -r --arg key "$PJ_BASENAME" '.[$key] // $key' "$PJ_DICT" 2>/dev/null || echo "$PJ_BASENAME")
else
  PJ_NAME="${PJ_BASENAME:-くろーど}"
fi

extract_intent() {
  printf '%s' "$1" | python3 -c '
import sys, re
text = sys.stdin.read().rstrip()
m = re.search(r"\[([1-8])\]\s*$", text)
if m:
    print(m.group(1))
' 2>/dev/null || true
}

intent_to_phrase() {
  case "$1" in
    1) echo "質問が来ているよ" ;;
    2) echo "完了報告が来ているよ" ;;
    3) echo "相談したいみたいだよ" ;;
    4) echo "プランを見てほしいみたいだよ" ;;
    5) echo "進めて良いか聞いているよ" ;;
    6) echo "問題が起きてるみたいだよ" ;;
    7) echo "選択肢が出てるよ" ;;
    *) echo "お知らせが来ているよ" ;;
  esac
}

case "$EVENT" in
  Stop)
    INTENT=$(extract_intent "$LAST_MSG")
    PHRASE=$(intent_to_phrase "$INTENT")
    msg="__USER_NAME__さん、${PJ_NAME}のくろーどから${PHRASE}"
    ;;
  SubagentStop)
    INTENT=$(extract_intent "$LAST_MSG")
    PHRASE=$(intent_to_phrase "$INTENT")
    msg="__USER_NAME__さん、サブエージェントから${PHRASE}"
    ;;
  *)
    msg="__USER_NAME__さん、${PJ_NAME}のくろーどから何か来たのだ"
    ;;
esac

nohup zundasay "$msg" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
```

`chmod +x ~/.local/bin/zundasay-stop` で実行権付与。

動作確認:

```bash
echo '{"hook_event_name":"Stop","cwd":"'$PWD'","last_assistant_message":"テスト [2]"}' \
  | ~/.local/bin/zundasay-stop
```

→ 数秒後に「○○さん、{現在ディレクトリ名}のくろーどから完了報告が来ているよ」と聞こえれば OK。

## STEP 5. intent タグルール

`~/.claude/rules/intent-tag.md` を作成:

```bash
mkdir -p ~/.claude/rules
```

中身:

```markdown
# 応答末尾の Intent タグ (毎ターン注入)

応答の**最後の行**に必ず以下の形式でカテゴリ番号を **1 個だけ**書け:

`[1]` 〜 `[8]`

## カテゴリ

- **1 = 質問**: ユーザーに疑問を投げて回答を待っている (末尾が ? / ？)
- **2 = 完了報告**: タスクや作業が終わった、修正した、書いた等
- **3 = 相談**: 「どっち?」「どうする?」など議論を持ちかけている
- **4 = プラン提示**: 計画 / 設計案 / 方針案を提示してレビューを求めている
- **5 = 進めて良いか**: 動詞指示・GO 待ち、権限不足、CLAUDE.md ルールで止まり中
- **6 = 問題発生**: エラー / 失敗 / 想定外 / ブロック / 不具合報告
- **7 = 選択肢**: A / B / C などから選んでほしい
- **8 = その他**: 上記に当てはまらない (挨拶 / 雑談 / 単なる事実通知 etc)

## 書き方

- 応答の**最後の行**に `[N]` だけを書く (半角角括弧 + 半角数字 1 桁)
- 前置きや説明は付けない (= 単独で 1 行)
- カテゴリが複数当てはまる場合は最も主要なものを 1 つ選ぶ
- カテゴリ判定に迷ったら 8
```

## STEP 6. settings.json に hook を登録

`~/.claude/settings.json` を読み、`hooks` セクションに以下をマージ。**既存の hooks 設定があっても壊さないよう、既存キー (例: PreToolUse, UserPromptSubmit) はそのまま残し、`Stop` を追加 / `UserPromptSubmit` の hooks 配列に command を追加** する形で:

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
            "command": "/Users/__USERNAME__/.local/bin/zundasay-stop"
          }
        ]
      }
    ]
  }
}
```

`__USERNAME__` は `$(whoami)` の結果に置換すること。

既存に `UserPromptSubmit` がある場合は `hooks` 配列の中に上記 command を **追記**。既存に `Stop` がある場合は **配列に追加** (上書きしない)。

settings.json の編集後、JSON が valid であることを `jq . ~/.claude/settings.json > /dev/null` で確認。

## STEP 7. 動作確認 + 報告

セットアップ完了後、私 (ユーザー) に以下を報告してほしい:

1. STEP 2〜6 で作成 / 編集したファイルの一覧
2. 次の応答完了時に Stop hook が発火して発声するはず、と告知
3. 注意点として:
   - **subagent 通知はデフォルト無効** (うるさいので)。有効にするには settings.json の hooks に `SubagentStop` block を `Stop` と同じ内容で追加
   - **無効化したいとき** は settings.json の `Stop` block を削除 (または event名を別の有効でないキーにリネームする方法もあるが、Claude Code の hook event enum でバリデーションされるので削除推奨)
   - **発話フレーズ変更**: `~/.local/bin/zundasay-stop` の `intent_to_phrase` 関数を編集
   - **pj 読み方追加**: `~/.local/share/zundasay/project-names.json` に `{"pj-name": "読み方"}` を追加

報告したら、応答末尾に `[2]` を付けて完了。

---PROMPT END---

## カスタマイズ / 制約

- **macOS 専用**: `afplay` 依存。Linux なら `paplay` (PulseAudio) / `aplay` (ALSA) に書き換える必要あり
- **subagent 通知**: デフォルト無効。`~/.claude/settings.json` の `hooks` に下記 block を追加すれば有効化:
  ```json
  "SubagentStop": [
    {
      "hooks": [
        { "type": "command", "command": "/Users/USER/.local/bin/zundasay-stop" }
      ]
    }
  ]
  ```
- **発話フレーズ変更**: `~/.local/bin/zundasay-stop` の `intent_to_phrase` 関数を編集
- **pj 名読み方マップ**: `~/.local/share/zundasay/project-names.json` を編集 (例: `{"my-app": "マイアプリ"}`)
- **直列再生**: `mkdir` lock (`/tmp/zundasay.lockdir`) で重ならないようになってる。Claude Code が複数同時発火するときも順番待ちで再生
- **30 字キャップは無し** (intent タグ方式は短文発話なので不要)

## トラブルシュート

- **発声しない**: `~/.local/share/zundasay/hook.log` を `tail` で見て、Stop hook が発火してるか / `last_assistant_message` に `[N]` が含まれてるか確認
- **タグが応答に付かない**: `~/.claude/rules/intent-tag.md` が UserPromptSubmit hook で注入されてるか、`settings.json` を確認
- **VOICEVOX engine 落ちてる**: VOICEVOX.app を再起動
- **重なる**: lock dir (`/tmp/zundasay.lockdir`) が残骸で残ってる場合あり、`rm -rf /tmp/zundasay.lockdir`
