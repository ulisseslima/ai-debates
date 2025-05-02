#!/bin/bash -e
# @installable
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/../../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

response=$($ROOT/api/api-11labs.sh GET 'user/subscription')

count=$(echo $response | jq .character_count)
limit=$(echo $response | jq .character_limit)
echo $((limit-count))
