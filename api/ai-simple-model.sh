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

model="$1"
require model

prompt="$2"
require prompt

if [[ -f "$prompt" ]]; then
    >&2 echo "reading prompt from file..."
    prompt=$(cat $prompt)
fi

# 1. replaces line breaks with double escaped \n so it's not converted back to a line break in the final sed command
# 2. replaces double quotes with single quotes so the JSON is not broken
# 3. echo -n so no new line at the end is added
prompt="$(echo -n "$prompt" | sed -z 's/\n/\\\\n/g' | sed "s/\"/”/g")"
if [[ "$prompt" == *'|'* ]]; then
    sed "s/aaa/$prompt/g" $ROOT/api/models/model-$1.json
else
    sed "s|aaa|$prompt|g" $ROOT/api/models/model-$1.json
fi