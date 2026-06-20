set -euo pipefail

LAPTOP_OUTPUT="eDP-1"
LAPTOP_RULE="eDP-1, preferred, 0x0, 1.5"

EXTERNAL_DESCRIPTIONS=(
  "ASUSTek COMPUTER INC ASUS VA32U 0x00015DB6"
  "LG Electronics LG HDR 4K 601NTRLN4694"
  "LG Electronics LG Ultra HD 0x00009D2A"
)

EXTERNAL_RULES=(
  "desc:ASUSTek COMPUTER INC ASUS VA32U 0x00015DB6, 3840x2160@60, 0x0, 1.5, transform, 1"
  "desc:LG Electronics LG HDR 4K 601NTRLN4694, 3840x2160@60, 1440x0, 1.5, transform, 1"
  "desc:LG Electronics LG Ultra HD 0x00009D2A, 3840x2160@60, 2880x0, 1.5, transform, 3"
)

log() {
  printf 'hypr-monitor-layout: %s\n' "$*" >&2
}

hypr_json() {
  hyprctl "$@" -j 2>/dev/null
}

external_descriptions_json() {
  printf '%s\n' "${EXTERNAL_DESCRIPTIONS[@]}" | jq -R . | jq -s .
}

known_external_count() {
  local descriptions_json

  descriptions_json="$(external_descriptions_json)"
  hypr_json monitors all | jq -r \
    --argjson descriptions "$descriptions_json" \
    '
      [
        .[]
        | select(.description as $description | $descriptions | index($description))
      ]
      | length
    '
}

active_external_count() {
  local descriptions_json

  descriptions_json="$(external_descriptions_json)"
  hypr_json monitors all | jq -r \
    --argjson descriptions "$descriptions_json" \
    '
      [
        .[]
        | select(.disabled == false)
        | select(.description as $description | $descriptions | index($description))
      ]
      | length
    '
}

first_active_external() {
  local descriptions_json

  descriptions_json="$(external_descriptions_json)"
  hypr_json monitors all | jq -r \
    --argjson descriptions "$descriptions_json" \
    '
      [
        .[]
        | select(.disabled == false)
        | select(.description as $description | $descriptions | index($description))
      ]
      | sort_by(.x, .y)
      | .[0].name // empty
    '
}

center_cursor_on() {
  local output="$1"
  local point x y

  point="$(
    hypr_json monitors all | jq -r --arg output "$output" '
      [
        .[]
        | select(.name == $output and .disabled == false)
        | [(.x + (.width / 2 | floor)), (.y + (.height / 2 | floor))]
        | @tsv
      ][0] // empty
    '
  )"

  [ -n "$point" ] || return 0

  IFS="$(printf '\t')" read -r x y <<<"$point"
  [ -n "$x" ] && [ -n "$y" ] || return 0

  hyprctl dispatch movecursor "$x" "$y" >/dev/null 2>&1 || true
}

focus_output() {
  local output="$1"

  hyprctl dispatch focusmonitor "$output" >/dev/null 2>&1 || true
  center_cursor_on "$output"
}

wait_for_active_externals() {
  local expected_count="$1"
  local active_count output

  for _ in $(seq 1 50); do
    active_count="$(active_external_count)"
    if [ "$active_count" -ge "$expected_count" ]; then
      output="$(first_active_external)"
      [ -n "$output" ] || return 1
      printf '%s\n' "$output"
      return 0
    fi

    sleep 0.2
  done

  active_count="$(active_external_count)"
  log "only $active_count of $expected_count known external monitors are active"
  return 1
}

apply_laptop_mode() {
  log "using laptop output"
  hyprctl keyword monitor "$LAPTOP_RULE" >/dev/null
  sleep 0.2
  focus_output "$LAPTOP_OUTPUT"
}

apply_external_mode() {
  local expected_count="$1"
  local output

  log "using external monitor layout"
  for rule in "${EXTERNAL_RULES[@]}"; do
    hyprctl keyword monitor "$rule" >/dev/null || log "failed to apply monitor rule: $rule"
  done

  if ! output="$(wait_for_active_externals "$expected_count")"; then
    return 1
  fi

  focus_output "$output"
  hyprctl keyword monitor "$LAPTOP_OUTPUT, disable" >/dev/null
  sleep 0.2
  focus_output "$output"
}

apply_layout() {
  local external_count

  external_count="$(known_external_count)"

  if [ "$external_count" -eq 0 ]; then
    apply_laptop_mode
  else
    apply_external_mode "$external_count"
  fi
}

wait_for_socket() {
  local socket

  while true; do
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
      socket="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
      if [ -S "$socket" ]; then
        printf '%s\n' "$socket"
        return 0
      fi
    fi

    for socket in "${XDG_RUNTIME_DIR}"/hypr/*/.socket2.sock; do
      if [ -S "$socket" ]; then
        printf '%s\n' "$socket"
        return 0
      fi
    done

    sleep 0.5
  done
}

watch_socket() {
  local socket="$1"
  local line

  while IFS= read -r line; do
    case "$line" in
      monitoradded'>>'*|monitorremoved'>>'*|configreloaded*)
        sleep 1
        apply_layout || log "failed to apply monitor layout"
        ;;
    esac
  done < <(socat -U - UNIX-CONNECT:"$socket")
}

main() {
  local socket socket_dir

  : "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
  export XDG_RUNTIME_DIR

  while true; do
    socket="$(wait_for_socket)"
    socket_dir="${socket%/.socket2.sock}"
    export HYPRLAND_INSTANCE_SIGNATURE="${socket_dir##*/}"

    apply_layout || log "failed to apply monitor layout"
    watch_socket "$socket" || true
    sleep 1
  done
}

main "$@"
