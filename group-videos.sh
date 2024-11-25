#!/bin/bash -e
# @installable
# groups files intro a single one
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    info "$ME - //${pad_n_topic} - returned $1 at line $2"
  fi
}

source $MYDIR/_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $(real require.sh)

projectd="$1"
require -d projectd

pattern="$2"
require pattern "file pattern to group"

order="$3"
require order "file preffix"

function group() {
  pattern="$1"
  order=$(lpad "$2")

  outn="$order-${pattern}_cut"
  outf="$projectd/${outn}.mp4"
  out="$projectd/${outn}-w_soundtrack.mp4"

  if [[ ! -f "$outf" ]]; then
    info "grouping: $pattern..."
    mkdir $projectd/$pattern && mv $projectd/*${pattern}*.mp4 $projectd/$pattern

    find "$projectd/$pattern" -maxdepth 1 -type f -name "*$pattern*.mp4" -printf "file '%p'\n" | sort | ffmpeg-concat.sh -o "$outf"
    require -f outf
  fi

  if [[ ! -f "$out" ]]; then
    faceless-soundtrack "$outf" -o "$out" --volume 0.15 --lib "$SONG_LIBRARY"
    readlink -f $out
    require -f out
    info "soundtrack ok: $out"
    if [[ -f "$outf" ]]; then
      mv "$outf" $projectd/$pattern
    fi
  fi

  echo "grouped $pattern: $out"
}

group $pattern $order