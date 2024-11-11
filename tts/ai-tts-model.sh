#!/bin/bash -e
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    >&2 echo "$ME - returned $1 at line $2"
  fi
}

source $MYDIR/../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

model="${1}-tts"
shift
MODEL=$ROOT/api/models/model-$model.json
require -f MODEL

voice=$1
prompt="$2"

# replaces double quotes with curly quotes so the JSON is not broken
if [[ -f "$prompt" ]]; then
    prompt=$(cat $prompt)
else
    prompt="$(echo -n "$prompt" | sed -z 's/\n/\\\\n/g' | sed "s/\"/”/g")"
fi

if [[ "$prompt" == *'|'* ]]; then
    json=$(sed "s/aaa/$prompt/g" $MODEL)
else
    json=$(sed "s|aaa|$prompt|g" $MODEL)
fi

echo "$json" | sed "s/vvv/$voice/g"
