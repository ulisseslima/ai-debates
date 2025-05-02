#!/bin/bash -e
# @installable
# https://platform.openai.com/docs/guides/chat/introduction
# https://platform.openai.com/docs/api-reference/introduction
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

model=4

cache=$(get-arg.sh --context $@)
cache="$CACHE/context_${cache}"

delete=$(get-arg.sh --delete $@)
if [[ "$delete" == true ]]; then
    # info "remove cache $cache ?"
    # read confirmation
    rm -f "$cache"
    info "cache $cache removed"
    exit 0
fi

json=$($MYDIR/ai-model.sh $model "$@")
response=$($MYDIR/api-open-ai.sh POST 'chat/completions' "$json" | jq -r .choices[0].message.content)
context="{ \"role\": \"assistant\", \"content\": \"$(sanitize_json "$response")\" }"

if [[ -n "$cache" ]]; then
    debug "writing context to $cache"
    # echo "$json" | jq ".messages += [${context}]" | jq ".messages | .[]" > $cache
    echo "$json" | jq ".messages += [${context}]" | jq ".messages" | tail -n+2 | head -n-1 > $cache
fi

echo "$response"