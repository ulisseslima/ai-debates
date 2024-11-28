#!/bin/bash -e
# @installable
# render waveforms into video
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
shift

padding_size=18
chapters_only=false

##
# render speeches
function render_audios() {
  info "creating waveform videos..."
  while read audio
  do
    $MYDIR/render-audio.sh "$audio" --chapters "$chapters"
  done < <(ls -1tr $projectd/*with-pause.ogg)
}

##
# discover chapters from file names
function chapters() {
  info "discovering chapters..."
  while read audio
  do
    fname=$(basename "$audio" | rev | cut -d'.' -f2- | rev)
    stage=$(echo "${fname}" | cut -d'-' -f3 | tr '_' ' ')
    stage=$(rpad "| ${stage^}" $padding_size)
    echo "$stage"
    
    if [[ -z "$chapters" ]]; then
      chapters="${stage}"
    else
      chapters=$(echo -e "${chapters}\n${stage}")
    fi
  done < <(ls -1tr $projectd/*with-pause.ogg)
}

while test $# -gt 0
do
    case "$1" in
    --chapters-only)
      chapters_only=true
    ;;
    -*)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

info "keeping alive"
nohup keep-gnome-alive.sh rendering &

chapters
if [[ $chapters_only != true ]]; then
  render_audios "$projectd"
fi

keep-gnome-alive.sh rendering stop
info "$ME - done"