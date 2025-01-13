#!/bin/bash -e
# creates timestamps for the segment
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    error="$ME - returned $1 at line $2"
    >&2 echo "$error"
    notify-send "$error"
  fi
}

source $MYDIR/_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

start=$(elapsed.sh)

projectd="$1"
require -d projectd
shift
projectd=$(readlink -f "$projectd")

script=$(readlink -f $projectd/debate.md)
list=$(grep -P '# \d\d' $script)
topics=$(echo "$list" | wc -l)

cd "$projectd"

info "generating chapters for '$script'..."
chapters=$projectd/chapters.md
echo "# CHAPTERS
0:00 INTRO" > $chapters

duration=$(ffmpeg-info.sh 01-debate-introduction-with-pause.ogg duration)
n_topic=2
for segment in $(ls $projectd/*-with-pause.ogg)
do
  [[ $segment == *debate-introduction* || $segment == *outro* ]] && continue
  
  pad_n_topic=$(lpad $n_topic)
  topic=$(cat "$script" | grep -m1 "# $pad_n_topic" | cut -d'-' -f2- | cut -d' ' -f2-)
  
  timestamp=$(clock.sh $(op.sh "round($duration)"))
  echo "$timestamp $topic" >> $chapters

  dur=$(ffmpeg-info.sh $segment duration)
  duration=$(op.sh $duration+$dur)
  
  n_topic=$((n_topic+1))
done

cat $chapters
