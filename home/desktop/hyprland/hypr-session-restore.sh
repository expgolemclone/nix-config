#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
SESSION_FILE="$STATE_DIR/hypr-session.json"

# --- フォールバック: セッションファイルがない場合のデフォルト起動 ---
fallback_launch() {
  echo "No session file found, nothing to restore"
  exit 0
}

# セッションファイルが存在しない場合はフォールバック
[[ -f "$SESSION_FILE" ]] || fallback_launch

# モニター数を取得（ワークスペース番号のクランプに使用）
monitor_count=$(hyprctl monitors -j | jq 'length')

# JSON を読み込み
session=$(cat "$SESSION_FILE")
count=$(echo "$session" | jq '.windows | length')

if [[ "$count" -eq 0 ]]; then
  fallback_launch
fi

# 各ウィンドウを復元
for i in $(seq 0 $((count - 1))); do
  window=$(echo "$session" | jq -c ".windows[$i]")
  class=$(echo "$window" | jq -r '.class')
  workspace=$(echo "$window" | jq -r '.workspace')
  # ワークスペース番号をモニター数以内にクランプ
  workspace=$(( (workspace - 1) % monitor_count + 1 ))

  case "$class" in
    kitty)
      cwd=$(echo "$window" | jq -r '.cwd // empty')
      command=$(echo "$window" | jq -r '.command // empty')
      dir_flag=""
      [[ -n "$cwd" && -d "$cwd" ]] && dir_flag="--directory $cwd"

      case "$command" in
        claude)
          session_id=$(echo "$window" | jq -r '.claude_session_id // empty')
          if [[ -n "$session_id" ]]; then
            hyprctl dispatch exec "[workspace $workspace silent] kitty $dir_flag -e claude -r $session_id"
          else
            hyprctl dispatch exec "[workspace $workspace silent] kitty $dir_flag -e claude --resume"
          fi
          ;;
        codex)
          hyprctl dispatch exec "[workspace $workspace silent] kitty $dir_flag -e codex"
          ;;
        *)
          hyprctl dispatch exec "[workspace $workspace silent] kitty $dir_flag"
          ;;
      esac
      ;;
    google-chrome|chromium-browser)
      hyprctl dispatch exec "[workspace $workspace silent] google-chrome-stable"
      ;;
    code|code-oss|Code)
      hyprctl dispatch exec "[workspace $workspace silent] code"
      ;;
    org.kde.dolphin)
      hyprctl dispatch exec "[workspace $workspace silent] dolphin"
      ;;
    *)
      # 不明なアプリはクラス名でそのまま起動を試みる
      hyprctl dispatch exec "[workspace $workspace silent] $class" 2>/dev/null || true
      ;;
  esac

  # 連続起動の負荷を軽減
  sleep 0.2
done

# セッションファイルをバックアップに移動
mv "$SESSION_FILE" "${SESSION_FILE}.bak"

echo "Session restored ($count windows)"
