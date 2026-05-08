#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "repo: $REPO"

mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.local/share/zundasay"

chmod +x "$REPO/bin/zundasay" "$REPO/bin/zundasay-stop"

ln -sf "$REPO/bin/zundasay" "$HOME/.local/bin/zundasay"
ln -sf "$REPO/bin/zundasay-stop" "$HOME/.local/bin/zundasay-stop"
ln -sf "$REPO/rules/intent-tag.md" "$HOME/.claude/rules/intent-tag.md"

if [ ! -f "$HOME/.local/share/zundasay/project-names.json" ]; then
  cp "$REPO/project-names.example.json" "$HOME/.local/share/zundasay/project-names.json"
  echo "✓ project-names.json をテンプレから初期化"
else
  echo "ℹ project-names.json は既存のまま (上書き回避)"
fi

echo
echo "✓ symlink 設置完了:"
echo "  ~/.local/bin/zundasay          → $REPO/bin/zundasay"
echo "  ~/.local/bin/zundasay-stop     → $REPO/bin/zundasay-stop"
echo "  ~/.claude/rules/intent-tag.md  → $REPO/rules/intent-tag.md"
echo
echo "次のステップ (詳細は README.md):"
echo "  1. ~/.zshrc に \`export ZUNDASAY_USER=あなたの呼ばれたい名前\` を追加 (任意、未設定時は \"たくてぃむ\")"
echo "  2. ~/.local/bin が PATH に通ってなければ追加"
echo "  3. ~/.claude/settings.json の hooks に Stop / UserPromptSubmit を追加"
echo "  4. VOICEVOX engine 起動"
