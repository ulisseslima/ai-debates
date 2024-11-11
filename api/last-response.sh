#!/bin/bash -e
# returns the response cache file for the last request of a service
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

type="$1"
require type 'response file pattern'

last_n=1

ls -t $CACHE/*${type}*.response.json | head -$last_n
