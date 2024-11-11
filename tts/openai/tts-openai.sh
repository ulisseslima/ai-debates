#!/bin/bash -e
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/../../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

voices="alloy
echo
fable
onyx
nova
shimmer"

voice_id=$1
if [[ "$voice_id" == random ]]; then
    voice_id="$(echo "$voices" | shuf -n1)"
fi
require voice_id 'arg1'
shift

text=$1
require text
shift

speaking_rate=1

if [[ "$text" == none ]]; then
  echo "$voice_id"
  exit 0
fi

while test $# -gt 0
do
    case "$1" in
    --verbose|-v)
      verbose=true
    ;;
    --out|-o)
      shift
      out="$1"
    ;;
    --rate|-x)
      shift
      speaking_rate="${1}"
    ;;
    -*)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

body="$($ROOT/tts/ai-tts-model.sh gpt "$voice_id" "$text")"
response=$($ROOT/api/api-open-ai.sh POST "audio/speech" "$body")
require -f response '-MPEG ADTS, layer III'

response_ogg="${response}-${speaking_rate}x.ogg"
if [[ ! -f "$response_ogg" ]]; then
  if [[ $speaking_rate == 1 ]]; then
    ffmpeg <&1- -v 16 -y -i "$response" -c:a libopus -b:a 128K "${response_ogg}"
  else
    ffmpeg <&1- -v 16 -y -i "$response" -filter:a "atempo=$speaking_rate" -c:a libopus -b:a 128K "${response_ogg}"
  fi
  require -f response_ogg -Opus
fi

if [[ -n "$out" ]]; then
    cp "${response_ogg}" "$out"
    echo "$out"
else
    echo "${response_ogg}"
fi
