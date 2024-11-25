#!/bin/bash -e
# @installable
# regenerates the video
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

pfile=$projectd/positive.persona
require -f pfile
nfile=$projectd/negative.persona
require -f nfile

pscores=$projectd/persona1-scores.md
require -f pscores
nscores=$projectd/persona2-scores.md
require -f nscores

rm -f $projectd/persona1-scores.md.tmp
rm -f $projectd/persona2-scores.md.tmp

mkdir $projectd/leftovers
while read video
do
  mv $video $projectd/leftovers
done < <(ls -1 $projectd/*.mp4)

if [[ -d "$projectd/debate" ]]; then
  mv "$projectd/debate" "$projectd/bkdebate"
fi

if [[ -d "$projectd/tmp" ]]; then
  mv "$projectd/tmp" "$projectd/bktmp"
fi

$MYDIR/render-audios.sh $projectd && $MYDIR/group-videos.sh $projectd debate 0
