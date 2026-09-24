#!/bin/bash -e
# Interactive debate topic suggestions -> debate generator
# Usage: suggest-cli.sh [-p|--prompt TOPIC] [--dry-run] [--no-confirm]
#
# Uses fzf for multi-select when available. Otherwise, accepts numbered
# selections such as `1,3-5`, or `a` for all suggestions.

MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename "$MYSELF")

source "$MYDIR/_env.sh"
[[ -f "$LOCAL_ENV" ]] && source "$LOCAL_ENV"
source "$(real require.sh)"

dry_run=false
no_confirm=false
topic=""

while test $# -gt 0; do
  case "$1" in
    -p|--prompt)
      shift
      [[ $# -gt 0 ]] || { err "Missing value for --prompt"; exit 1; }
      topic="$1"
      ;;
    --dry-run)
      dry_run=true
      ;;
    --no-confirm|-y)
      no_confirm=true
      ;;
    -h|--help)
      echo "Usage: $ME [-p|--prompt TOPIC] [--dry-run] [--no-confirm]"
      exit 0
      ;;
    -*)
      err "Unknown option: $1"
      exit 1
      ;;
    *)
      topic="$1"
      ;;
  esac
  shift
done

require topic "Please provide a topic for debate suggestions."

info "$ME - generating debate suggestions for: $topic"

raw=$("$MYDIR/suggest.sh" "$topic" 2>/dev/null || true)
if [[ -z "$raw" ]]; then
  err "no suggestions returned from suggest.sh"
  exit 1
fi

mapfile -t suggestions < <(printf "%s\n" "$raw" \
  | sed '/^[[:space:]]*$/d' \
  | sed -E 's/^[[:space:]]*[0-9]+[.)][[:space:]]*//' \
  | sed -E 's/^[[:space:]]*[-*][[:space:]]*//')

if [[ ${#suggestions[@]} -eq 0 ]]; then
  err "no parseable debate suggestions"
  exit 1
fi

select_with_fzf() {
  printf "%s\n" "${suggestions[@]}" \
    | fzf --multi \
      --header "Select debates (TAB to multi-select, Enter to confirm)" \
      --prompt "Select: "
}

parse_numeric_selection() {
  local selection="$1"
  local -n output=$2
  local part start end index
  local -A selected=()

  [[ -n "$selection" ]] || return 1

  if [[ "$selection" =~ ^[Aa]$ ]]; then
    output=("${suggestions[@]}")
    return 0
  fi

  IFS=',' read -ra parts <<< "$selection"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start=${BASH_REMATCH[1]}
      end=${BASH_REMATCH[2]}
      (( start <= end )) || return 1
      for ((index=start; index<=end; index++)); do
        (( index >= 1 && index <= ${#suggestions[@]} )) || return 1
        selected[$((index - 1))]=1
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      (( part >= 1 && part <= ${#suggestions[@]} )) || return 1
      selected[$((part - 1))]=1
    else
      return 1
    fi
  done

  for index in "${!suggestions[@]}"; do
    [[ -n "${selected[$index]:-}" ]] && output+=("${suggestions[$index]}")
  done
}

selected_suggestions=()

if command -v fzf >/dev/null 2>&1; then
  info "using fzf for selection"
  selection=$(select_with_fzf) || true
  [[ -n "$selection" ]] || { err "no selection made"; exit 1; }
  while IFS= read -r line; do
    selected_suggestions+=("$line")
  done <<< "$selection"
else
  info "fzf not found, using numbered selection"
  for index in "${!suggestions[@]}"; do
    printf "%3d) %s\n" "$((index + 1))" "${suggestions[$index]}"
  done
  echo
  read -r -p "Enter selections (e.g. 1,3-5) or 'a' for all: " selection
  if ! parse_numeric_selection "$selection" selected_suggestions; then
    err "invalid selection: $selection"
    exit 1
  fi
fi

[[ ${#selected_suggestions[@]} -gt 0 ]] || { err "no topics selected"; exit 1; }

echo
info "selected ${#selected_suggestions[@]} debate topic(s):"
for suggestion in "${selected_suggestions[@]}"; do
  echo " - $suggestion"
done

if [[ "$dry_run" == true ]]; then
  info "dry-run: not launching ai-debate.sh"
  exit 0
fi

if [[ "$no_confirm" != true ]]; then
  read -r -p "Start generating the selected debate(s)? [y/N] " confirmation
  if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
    info "aborted by user"
    exit 0
  fi
fi

for suggestion in "${selected_suggestions[@]}"; do
  info "launching ai-debate for: $suggestion"
  if ! "$MYDIR/ai-debate.sh" "$suggestion"; then
    err "ai-debate.sh failed for: $suggestion"
  fi
done

info "done"