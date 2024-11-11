#!/bin/bash -e
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/../../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

$MYDIR/api-11labs.sh GET voices
#| jq -r .voices[].voice_id
