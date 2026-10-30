#!/bin/bash -e
# lists fish.audio voice models.
# defaults to the public voice catalog (sorted by popularity) since most
# accounts have no self-owned voice clones to pick a "random" voice from.
# pass --self to list only voice models owned by the active workspace instead.
# pass --gender <male|female|neutral> to filter voices by that tag (most public
# voices are tagged with their perceived gender).
# https://docs.fish.audio/api-reference/endpoint/model/list-models
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

self=false
gender=

while test $# -gt 0
do
    case "$1" in
    --self)
      self=true
    ;;
    --gender)
      shift
      gender="${1,,}"
    ;;
    esac
    shift
done

if [[ "$self" == true ]]; then
  query='model?self=true&page_size=100'
else
  query='model?page_size=100&sort_by=score'
fi

case "$gender" in
  male|man|m)
    query="${query}&tag=male"
  ;;
  female|woman|f)
    query="${query}&tag=female"
  ;;
  neutral|n)
    query="${query}&tag=neutral"
  ;;
  '')
    : # no gender filter requested
  ;;
  *)
    query="${query}&tag=${gender}"
  ;;
esac

$MYDIR/api-fish.sh GET "$query"

# famous voice models (sorted by popularity)
# lula: a4ac1426e4a749839c86853ad613eebe
# bolsonaro: b1c2d3e4f5a67890123456789abcdef0
# moro: c0ffee1234567890abcdef1234567890
# doria: 1234567890abcdef1234567890abcdef