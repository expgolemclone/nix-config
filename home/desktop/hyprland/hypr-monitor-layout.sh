set -euo pipefail

LAPTOP_OUTPUT="eDP-1"
LAPTOP_RULE="eDP-1, preferred, 0x0, 1.5"

EXTERNAL_DESCRIPTIONS=(
  "ASUSTek COMPUTER INC ASUS VA32U 0x00015DB6"
  "LG Electronics LG HDR 4K 601NTRLN4694"
  "LG Electronics LG Ultra HD 0x00009D2A"
)

EXTERNAL_WIDTHS=(3840 3840 3840)
EXTERNAL_HEIGHTS=(2160 2160 2160)
EXTERNAL_REFRESHES=(30 60 30)
EXTERNAL_X=(0 1440 2880)
EXTERNAL_Y=(0 0 0)
EXTERNAL_SCALES=(1.5 1.5 1.5)
EXTERNAL_TRANSFORMS=(1 1 3)

REQUIRED_EXTERNAL_COUNT="${#EXTERNAL_DESCRIPTIONS[@]}"

EXPECTED_ARRAY_LENGTHS=(
  "${#EXTERNAL_WIDTHS[@]}"
  "${#EXTERNAL_HEIGHTS[@]}"
  "${#EXTERNAL_REFRESHES[@]}"
  "${#EXTERNAL_X[@]}"
  "${#EXTERNAL_Y[@]}"
  "${#EXTERNAL_SCALES[@]}"
  "${#EXTERNAL_TRANSFORMS[@]}"
)

log() {
  printf 'hypr-monitor-layout: %s\n' "$*" >&2
}

first_line() {
  local text="$1"

  text="${text%%$'\n'*}"
  if [ "${#text}" -gt 200 ]; then
    text="${text:0:200}..."
  fi

  printf '%s\n' "$text"
}

hypr_json() {
  local output summary

  if ! output="$(hyprctl "$@" -j 2>&1)"; then
    summary="$(first_line "$output")"
    if [ -n "$summary" ]; then
      log "hyprctl $* -j failed: $summary"
    else
      log "hyprctl $* -j failed"
    fi
    return 1
  fi

  if ! jq -e . >/dev/null 2>&1 <<<"$output"; then
    summary="$(first_line "$output")"
    if [ -n "$summary" ]; then
      log "hyprctl $* -j returned non-json output: $summary"
    else
      log "hyprctl $* -j returned empty output"
    fi
    return 1
  fi

  printf '%s\n' "$output"
}

external_descriptions_json() {
  printf '%s\n' "${EXTERNAL_DESCRIPTIONS[@]}" | jq -R . | jq -s .
}

validate_external_config() {
  local length

  for length in "${EXPECTED_ARRAY_LENGTHS[@]}"; do
    if [ "$length" -ne "$REQUIRED_EXTERNAL_COUNT" ]; then
      log "external monitor config arrays have different lengths"
      return 1
    fi
  done
}

external_rule() {
  local index="$1"

  printf 'desc:%s, %sx%s@%s, %sx%s, %s, transform, %s\n' \
    "${EXTERNAL_DESCRIPTIONS[$index]}" \
    "${EXTERNAL_WIDTHS[$index]}" \
    "${EXTERNAL_HEIGHTS[$index]}" \
    "${EXTERNAL_REFRESHES[$index]}" \
    "${EXTERNAL_X[$index]}" \
    "${EXTERNAL_Y[$index]}" \
    "${EXTERNAL_SCALES[$index]}" \
    "${EXTERNAL_TRANSFORMS[$index]}"
}

active_external_count() {
  local descriptions_json

  descriptions_json="$(external_descriptions_json)"
  hypr_json monitors | jq -r \
    --argjson descriptions "$descriptions_json" \
    '
      [
        .[]
        | select(.description as $description | $descriptions | index($description))
      ]
      | length
    '
}

first_active_external() {
  local descriptions_json

  descriptions_json="$(external_descriptions_json)"
  hypr_json monitors | jq -r \
    --argjson descriptions "$descriptions_json" \
    '
      [
        .[]
        | select(.description as $description | $descriptions | index($description))
      ]
      | sort_by(.x, .y)
      | .[0].name // empty
    '
}

center_cursor_on() {
  local output="$1"
  local point x y

  if ! point="$(
    hypr_json monitors | jq -r --arg output "$output" '
      [
        .[]
        | select(.name == $output)
        | [(.x + (.width / 2 | floor)), (.y + (.height / 2 | floor))]
        | @tsv
      ][0] // empty
    '
  )"; then
    return 0
  fi

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
    if ! active_count="$(active_external_count)"; then
      sleep 0.2
      continue
    fi

    if [ "$active_count" -ge "$expected_count" ]; then
      if ! output="$(first_active_external)"; then
        return 1
      fi
      [ -n "$output" ] || return 1
      printf '%s\n' "$output"
      return 0
    fi

    sleep 0.2
  done

  if active_count="$(active_external_count)"; then
    log "only $active_count of $expected_count known external monitors are active"
  else
    log "could not read active external monitor count"
  fi
  return 1
}

apply_external_rules() {
  local index
  local rule
  local applied=0

  for index in "${!EXTERNAL_DESCRIPTIONS[@]}"; do
    rule="$(external_rule "$index")"
    if ! hyprctl keyword monitor "$rule" >/dev/null; then
      log "failed to apply monitor rule: $rule"
      return 1
    fi
    applied=$((applied + 1))
  done

  printf '%s\n' "$applied"
}

laptop_layout_matches() {
  local monitors_json

  if ! monitors_json="$(hypr_json monitors all)"; then
    return 1
  fi

  jq -e --arg output "$LAPTOP_OUTPUT" '
    [
      .[]
      | select(
          .name == $output
          and .disabled == false
          and .x == 0
          and .y == 0
          and .scale == 1.5
          and .transform == 0
        )
    ]
    | length == 1
  ' >/dev/null <<<"$monitors_json"
}

external_monitor_matches() {
  local monitors_json="$1"
  local index="$2"

  jq -e \
    --arg description "${EXTERNAL_DESCRIPTIONS[$index]}" \
    --argjson width "${EXTERNAL_WIDTHS[$index]}" \
    --argjson height "${EXTERNAL_HEIGHTS[$index]}" \
    --argjson refresh "${EXTERNAL_REFRESHES[$index]}" \
    --argjson x "${EXTERNAL_X[$index]}" \
    --argjson y "${EXTERNAL_Y[$index]}" \
    --argjson scale "${EXTERNAL_SCALES[$index]}" \
    --argjson transform "${EXTERNAL_TRANSFORMS[$index]}" '
      [
        .[]
        | select(
            .description == $description
            and .disabled == false
            and .width == $width
            and .height == $height
            and ((.refreshRate - $refresh) | if . < 0 then -. else . end) < 0.1
            and .x == $x
            and .y == $y
            and .scale == $scale
            and .transform == $transform
          )
      ]
      | length == 1
    ' >/dev/null <<<"$monitors_json"
}

external_layout_matches() {
  local index
  local monitors_json

  if ! monitors_json="$(hypr_json monitors all)"; then
    return 1
  fi

  for index in "${!EXTERNAL_DESCRIPTIONS[@]}"; do
    external_monitor_matches "$monitors_json" "$index" || return 1
  done

  jq -e --arg output "$LAPTOP_OUTPUT" '
    [
      .[]
      | select(.name == $output and .disabled == true)
    ]
    | length == 1
  ' >/dev/null <<<"$monitors_json"
}

apply_laptop_mode() {
  if laptop_layout_matches; then
    return 0
  fi

  log "using laptop output"
  if ! hyprctl keyword monitor "$LAPTOP_RULE" >/dev/null; then
    log "failed to apply laptop monitor rule: $LAPTOP_RULE"
    return 1
  fi
  sleep 0.2
  focus_output "$LAPTOP_OUTPUT"
}

apply_external_mode() {
  local expected_count="$1"
  local applied_count
  local output

  if external_layout_matches; then
    return 0
  fi

  log "using external monitor layout"
  applied_count="$(apply_external_rules)"
  if [ "$applied_count" -ne "$expected_count" ]; then
    log "only applied $applied_count of $expected_count active external monitor rules"
    return 1
  fi

  if ! output="$(wait_for_active_externals "$expected_count")"; then
    return 1
  fi

  focus_output "$output"
  if ! hyprctl keyword monitor "$LAPTOP_OUTPUT, disable" >/dev/null; then
    log "failed to disable laptop output: $LAPTOP_OUTPUT"
    return 1
  fi
  sleep 0.2
  focus_output "$output"

  if ! external_layout_matches; then
    log "external monitor layout did not converge"
    return 1
  fi
}

apply_layout() {
  local external_count
  local output

  if ! external_count="$(active_external_count)"; then
    return 1
  fi

  if [ "$external_count" -eq 0 ]; then
    apply_laptop_mode
  elif [ "$external_count" -lt "$REQUIRED_EXTERNAL_COUNT" ]; then
    if output="$(wait_for_active_externals "$REQUIRED_EXTERNAL_COUNT")"; then
      apply_external_mode "$REQUIRED_EXTERNAL_COUNT"
      focus_output "$output"
    else
      log "not applying external layout until all $REQUIRED_EXTERNAL_COUNT known external monitors are active"
      apply_laptop_mode
      return 1
    fi
  else
    apply_external_mode "$REQUIRED_EXTERNAL_COUNT"
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
  validate_external_config

  if [ "${1:-}" = "--once" ]; then
    apply_layout
    return
  fi

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
