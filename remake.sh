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

speech=$projectd/debate.md

pfile=$projectd/positive.persona
require -f pfile
persona1=$(cat $pfile | cut -d'(' -f1 | xargs)

nfile=$projectd/negative.persona
require -f nfile
persona2=$(cat $nfile | cut -d'(' -f1 | xargs)

pscores=$projectd/persona1-scores.md
if [[ ! -f "$pscores" ]]; then
  echo "${persona1}’s Scores:" > "$pscores"
  cat "$speech" | sed "s/'/’/g" | sed "s/ out of /\//" | sed -n "/$persona1’s Scores/,/$persona2’s Scores/p" | sed '$d' | grep -P "^[\d]" >> "$pscores"
fi
require -f pscores

nscores=$projectd/persona2-scores.md
if [[ ! -f "$nscores" ]]; then
  echo "${persona2}’s Scores:" > "$nscores"
  cat "$speech" | sed "s/'/’/g" | sed "s/ out of /\//" | sed -n "/$persona2’s Scores/,\$p" | sed '$d' | grep -P "^[\d]" >> "$nscores"
fi
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
