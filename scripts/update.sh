#!/usr/bin/env bash
#
# Refresh the R-Forge mailing list archives.
#
# For every list directory (one with a config.json) this downloads any pipermail
# mbox files that are missing or belong to the current period, re-parses the
# list with rmail-parser, and rebuilds the top-level lists.tsv index.
#
# Usage: scripts/update.sh [--force] [--no-fetch] [list ...]
#   --force     re-download every archive file, not just new or current ones
#   --no-fetch  skip downloading; only re-parse what is already in raw/
#   list ...    limit the run to these lists (default: all of them)
#
# Environment:
#   RMAIL_PARSER  path to the rmail-parser binary (default: ./rmail-parser)
#   ALIASES       path to an aliases.json for name resolution (optional)

set -euo pipefail

cd "$(dirname "$0")/.."

RMAIL_PARSER=${RMAIL_PARSER:-./rmail-parser}
ALIASES=${ALIASES:-}
UA="rforge-archive (+https://github.com/r-mailing-lists/rforge-archive)"

# Every request is bounded. R-Forge is going away, and a server that has stopped
# answering otherwise holds each request until the connection times out by
# itself, several minutes at a time.
fetch() {
  curl -fsSL --connect-timeout 20 --max-time 300 --retry 2 -A "$UA" "$@"
}

# Set once the source proves unreachable, so the remaining lists are not each
# made to wait out the same timeout.
SOURCE_DOWN=false

FORCE=false
FETCH=true
LISTS=()
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --no-fetch) FETCH=false ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) LISTS+=("$arg") ;;
  esac
done

if [ ${#LISTS[@]} -eq 0 ]; then
  for cfg in */config.json; do
    LISTS+=("${cfg%/config.json}")
  done
fi

MONTHS=(_ January February March April May June July August September October November December)
CUR_YEAR=$(date -u +%Y)
CUR_MONTH="${CUR_YEAR}-${MONTHS[$(date -u +%-m)]}"
CUR_QUARTER="${CUR_YEAR}q$(( ($(date -u +%-m) - 1) / 3 + 1 ))"

# Download one list's archive files into <list>/raw/ as uncompressed .mbox.
# R-Forge is being retired, so every failure here must leave what is already
# archived untouched: a file is only replaced by a complete, non-empty download.
fetch_list() {
  local list=$1 base_url index archive stem dest tmp rc=0
  base_url=$(jq -r '.source_url' "$list/config.json")
  mkdir -p "$list/raw"

  index=$(fetch "$base_url") || rc=$?
  if [ "$rc" -ne 0 ]; then
    # 22 is an HTTP error, which is about this list alone. Anything else means
    # the server itself could not be reached.
    if [ "$rc" -eq 22 ]; then
      echo "  $list: archive index unavailable, keeping existing files" >&2
    else
      SOURCE_DOWN=true
      echo "  $list: source unreachable (curl exit $rc), keeping existing files" >&2
      echo "  not asking for the remaining lists" >&2
    fi
    return 0
  fi

  { grep -oE 'href="[^"/]*\.txt(\.gz)?"' <<<"$index" || true; } |
    sed 's/href="//;s/"//' | sort -u |
    while read -r archive; do
      stem=${archive%.gz}
      stem=${stem%.txt}
      dest="$list/raw/$stem.mbox"

      # Past periods are final; only the current month, quarter, or year can still grow.
      if [ "$FORCE" != true ] && [ -f "$dest" ] &&
         [ "$stem" != "$CUR_MONTH" ] && [ "$stem" != "$CUR_QUARTER" ] && [ "$stem" != "$CUR_YEAR" ]; then
        continue
      fi

      tmp=$(mktemp)
      if fetch -o "$tmp" "${base_url%/}/$archive"; then
        if [[ "$archive" == *.gz ]]; then
          gunzip -c "$tmp" > "$tmp.mbox" 2>/dev/null || : > "$tmp.mbox"
        else
          cp "$tmp" "$tmp.mbox"
        fi
        if [ -s "$tmp.mbox" ]; then
          mv "$tmp.mbox" "$dest"
          echo "  $list: fetched $stem"
        else
          echo "  $list: $archive came back empty, keeping existing file" >&2
        fi
      else
        echo "  $list: failed to download $archive, keeping existing file" >&2
      fi
      rm -f "$tmp" "$tmp.mbox"
    done
}

# Parse <list>/raw/ into <list>/processed/ and lift the stats files next to it,
# matching the layout of the per-list archive repositories.
parse_list() {
  local list=$1 f log
  local aliases_args=()
  if [ -n "$ALIASES" ]; then
    aliases_args=(--aliases "$ALIASES")
  fi

  rm -rf "$list/processed"
  mkdir -p "$list/processed"
  # The parser logs one line per file it writes; only surface that on failure.
  if ! log=$("$RMAIL_PARSER" parse --input "$list/raw/" --output "$list/processed/" \
      --list "$list" ${aliases_args[@]+"${aliases_args[@]}"} 2>&1); then
    echo "$log" >&2
    echo "  $list: rmail-parser failed" >&2
    return 1
  fi

  for f in meta.json index.json message-order.json contributors.json; do
    mv "$list/processed/$f" "$list/$f"
  done
}

for list in "${LISTS[@]}"; do
  if [ ! -f "$list/config.json" ]; then
    echo "No such list: $list" >&2
    exit 1
  fi
  echo "$list"
  if [ "$FETCH" = true ] && [ "$SOURCE_DOWN" = false ]; then
    fetch_list "$list"
  fi
  parse_list "$list"
done

# Rebuild the index of every list from its config.json and meta.json.
{
  printf 'list\tdescription\tmessages\tthreads\tfirst_message\tlast_message\tsource_url\n'
  for cfg in */config.json; do
    jq -r --slurpfile meta "${cfg%/config.json}/meta.json" '
      [.list, .description, $meta[0].total_messages, $meta[0].total_threads,
       ($meta[0].first_message // ""), ($meta[0].last_message // ""), .source_url] | @tsv
    ' "$cfg"
  done
} > lists.tsv

echo "Indexed $(($(wc -l < lists.tsv) - 1)) lists in lists.tsv"
