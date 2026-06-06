#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
SESSION_FILE="$STATE_DIR/hypr-session.json"
mkdir -p "$STATE_DIR"

# --- Claude Code のセッション ID を取得 ---
get_claude_session_id() {
  local cwd=$1
  local project_dir
  project_dir=$(echo "$cwd" | sed 's|^/||; s|/|-|g; s|^|-|')
  local session_dir="$HOME/.claude/projects/$project_dir"

  if [[ -d "$session_dir" ]]; then
    local latest
    latest=$(ls -t "$session_dir"/*.jsonl 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
      basename "$latest" .jsonl
    fi
  fi
}

# --- コマンド名を判定 ---
detect_command() {
  local cmdline_json=$1
  echo "$cmdline_json" | jq -r '
    (.[0] // "") as $cmd |
    if ($cmd | test("claude$")) then "claude"
    elif ($cmd | test("codex$")) then "codex"
    else null
    end
  '
}

# --- kitty エントリを生成 ---
make_kitty_entry() {
  local ws=$1 cwd=$2 cmdline_json=$3

  local cmd
  cmd=$(detect_command "$cmdline_json")

  local entry
  entry=$(jq -nc --arg class "kitty" --argjson ws "$ws" --arg cwd "$cwd" \
    '{class: $class, workspace: $ws, cwd: $cwd}')

  if [[ "$cmd" == "claude" ]]; then
    local session_id
    session_id=$(get_claude_session_id "$cwd")
    entry=$(echo "$entry" | jq -c \
      --arg cmd "claude" \
      --arg sid "${session_id:-}" \
      '. + {command: $cmd, claude_session_id: (if $sid == "" then null else $sid end)}')
  elif [[ "$cmd" == "codex" ]]; then
    entry=$(echo "$entry" | jq -c --arg cmd "codex" '. + {command: $cmd}')
  else
    entry=$(echo "$entry" | jq -c '. + {command: null}')
  fi

  echo "$entry"
}

# --- メイン処理 ---

clients=$(hyprctl clients -j)

# kitty PID ごとの hyprland ウィンドウ情報を構築
# { pid: [{workspace, title}] }
declare -A kitty_hypr_windows
declare -A processed_kitty_pids

windows="[]"

# 全クライアントを処理
while IFS= read -r client; do
  class=$(echo "$client" | jq -r '.class')
  workspace=$(echo "$client" | jq -r '.workspace.id')
  pid=$(echo "$client" | jq -r '.pid')
  title=$(echo "$client" | jq -r '.title')

  # 特殊ワークスペース (negative ID) はスキップ
  [[ "$workspace" -lt 0 ]] && continue

  if [[ "$class" == "kitty" ]]; then
    # この PID の hyprland ウィンドウ情報を蓄積
    kitty_hypr_windows[$pid]+="$(jq -nc --argjson ws "$workspace" --arg title "$title" \
      '{workspace: $ws, title: $title}')
"
  else
    # 非 kitty: システムトレイ系は除外
    case "$class" in
      waybar|nm-applet|blueman-applet|dunst|fcitx*|awww*) continue ;;
    esac
    entry=$(jq -nc --arg class "$class" --argjson ws "$workspace" \
      '{class: $class, workspace: $ws}')
    windows=$(echo "$windows" | jq -c --argjson e "$entry" '. += [$e]')
  fi
done < <(echo "$clients" | jq -c '.[]')

# 各 kitty PID を処理
for pid in "${!kitty_hypr_windows[@]}"; do
  socket="/tmp/kitty-$pid"

  # hyprland ウィンドウ情報を JSON 配列に
  hypr_wins=$(echo "${kitty_hypr_windows[$pid]}" | jq -sc '.')

  if [[ -S "$socket" ]]; then
    # --- kitty リモートコントロールが使える場合 ---
    kitty_ls=$(kitty @ --to "unix:$socket" ls 2>/dev/null) || kitty_ls=""

    if [[ -n "$kitty_ls" ]]; then
      # 各 OS ウィンドウを処理
      os_win_count=$(echo "$kitty_ls" | jq 'length')

      for owi in $(seq 0 $((os_win_count - 1))); do
        os_win=$(echo "$kitty_ls" | jq -c ".[$owi]")
        os_title=$(echo "$os_win" | jq -r '.title // ""')

        # タイトルで hyprland ウィンドウとマッチしてワークスペースを取得
        ws=$(echo "$hypr_wins" | jq -r \
          --arg title "$os_title" \
          '[.[] | select(.title == $title)] | .[0].workspace // empty')

        # タイトルマッチ失敗時: 順番でフォールバック
        if [[ -z "$ws" ]]; then
          ws=$(echo "$hypr_wins" | jq -r ".[$owi].workspace // 1")
        fi

        # この OS ウィンドウの全タブ・全ペインを取得
        while IFS= read -r pane; do
          cwd=$(echo "$pane" | jq -r '.cwd')
          cmdline=$(echo "$pane" | jq -c '.cmdline')
          entry=$(make_kitty_entry "$ws" "$cwd" "$cmdline")
          windows=$(echo "$windows" | jq -c --argjson e "$entry" '. += [$e]')
        done < <(echo "$os_win" | jq -c '
          .tabs[] | .windows[] | {
            cwd: (.foreground_processes[0].cwd // .cwd),
            cmdline: (.foreground_processes[0].cmdline // [])
          }')
      done
      continue
    fi
  fi

  # --- フォールバック: /proc から取得 ---
  # 子プロセス一覧を重複なしで取得
  declare -A seen_children
  children=()
  for child_file in /proc/"$pid"/task/*/children; do
    [[ -f "$child_file" ]] || continue
    for cpid in $(cat "$child_file" 2>/dev/null); do
      if [[ -z "${seen_children[$cpid]+x}" ]]; then
        seen_children[$cpid]=1
        children+=("$cpid")
      fi
    done
  done
  unset seen_children

  # シェルプロセスまたは claude/codex を抽出
  shell_entries=()
  for shell_pid in "${children[@]}"; do
    local_cmdline=$(tr '\0' ' ' < /proc/"$shell_pid"/cmdline 2>/dev/null) || continue
    [[ "$local_cmdline" == *"kitten __atexit__"* ]] && continue

    if [[ "$local_cmdline" == *"claude"* || "$local_cmdline" == *"codex"* ]]; then
      # claude/codex は直接子プロセス: cmdline をそのまま使用
      local_cwd=$(readlink /proc/"$shell_pid"/cwd 2>/dev/null) || continue
      fg_cmd=$(printf '%s' "$local_cmdline" | jq -Rs 'split(" ") | map(select(. != ""))')
      shell_entries+=("$(jq -nc --arg cwd "$local_cwd" --argjson cmdline "$fg_cmd" \
        '{cwd: $cwd, cmdline: $cmdline}')")
    elif [[ "$local_cmdline" == *"/bin/zsh"* || "$local_cmdline" == *"/bin/bash"* ]]; then
      local_cwd=$(readlink /proc/"$shell_pid"/cwd 2>/dev/null) || continue

      # 孫プロセス(実行中コマンド)
      fg_cmd="[]"
      for gc_file in /proc/"$shell_pid"/task/"$shell_pid"/children; do
        [[ -f "$gc_file" ]] || continue
        for gc_pid in $(cat "$gc_file" 2>/dev/null); do
          gc_cmdline=$(tr '\0' ' ' < /proc/"$gc_pid"/cmdline 2>/dev/null) || continue
          if [[ -n "$gc_cmdline" ]]; then
            fg_cmd=$(printf '%s' "$gc_cmdline" | jq -Rs 'split(" ") | map(select(. != ""))')
            break 2
          fi
        done
      done

      shell_entries+=("$(jq -nc --arg cwd "$local_cwd" --argjson cmdline "$fg_cmd" \
        '{cwd: $cwd, cmdline: $cmdline}')")
    fi
  done

  # ワークスペース割り当て: hyprland ウィンドウ数に合わせて分配
  ws_list=$(echo "$hypr_wins" | jq -c '[.[].workspace] | unique')
  ws_count=$(echo "$ws_list" | jq 'length')

  for idx in "${!shell_entries[@]}"; do
    shell_entry="${shell_entries[$idx]}"
    cwd=$(echo "$shell_entry" | jq -r '.cwd')
    cmdline=$(echo "$shell_entry" | jq -c '.cmdline')

    # ラウンドロビンでワークスペースを割り当て
    ws_idx=$((idx % ws_count))
    ws=$(echo "$ws_list" | jq ".[$ws_idx]")

    entry=$(make_kitty_entry "$ws" "$cwd" "$cmdline")
    windows=$(echo "$windows" | jq -c --argjson e "$entry" '. += [$e]')
  done
done

# JSON ファイルに書き出し
jq -n --argjson windows "$windows" '{windows: $windows}' > "$SESSION_FILE"

echo "Session saved to $SESSION_FILE ($(echo "$windows" | jq 'length') windows)"
