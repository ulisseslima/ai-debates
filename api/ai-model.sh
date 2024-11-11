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
shift

json=$(cat $MYDIR/models/model-${model}.json)

# note: --context must come first when calling the script as arg order matters
while test $# -gt 0
do
    case "$1" in
        --context)
            shift
            
            cache="$CACHE/context_${1}"
            if [[ -f "$cache" ]]; then
                context=$(cat "$cache")
                json=$(echo "$json" | jq ".messages += [${context}]")
            fi
        ;;
        --system)
            shift

            system=$(sanitize_json "$1")
            system="{ \"role\": \"system\", \"content\": \"$system\" }"
            json=$(echo "$json" | jq ".messages += [${system}]")
        ;;
        --prompt)
            shift

            prompt=$(sanitize_json "$1")
            prompt="{ \"role\": \"user\", \"content\": \"$prompt\" }"
            json=$(echo "$json" | jq ".messages += [${prompt}]")
        ;;
        --assistant)
            shift
            
            assistant=$(sanitize_json "$1")
            assistant="{ \"role\": \"assistant\", \"content\": \"$assistant\" }"
            json=$(echo "$json" | jq ".messages += [${assistant}]")
        ;;
        -*)
            echo "unrecognized option: $1"
            exit 1377
        ;;
    esac
    shift
done

require prompt

echo "$json"