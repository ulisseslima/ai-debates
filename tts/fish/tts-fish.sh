#!/bin/bash -e
# https://docs.fish.audio/api-reference/endpoint/openapi-v1/text-to-speech
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/../../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

voice_id=$1
require voice_id 'arg1'
shift

text=$1
require text
shift

speaking_rate=1
volume=2.1
gender=

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
    --volume)
      shift
      volume="${1}"
    ;;
    --gender|--voice-preference)
      shift
      gender="${1}"
    ;;
    -*)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

if [[ "$voice_id" == random ]]; then
  voice="$($MYDIR/tts-fish-voices.sh ${gender:+--gender "$gender"} | jq -r '(.items[]._id + "#" + .items[].title)' | shuf -n1)"
  voice_id=$(echo "$voice" | cut -d'#' -f1)
  voice_name=$(echo "$voice" | cut -d'#' -f2)
elif [[ "$voice_id" == *'#'* ]]; then
  voice_id=$(echo "$voice_id" | cut -d'#' -f1)
fi

require voice_id 'resolved voice_id'

if [[ "$text" == none ]]; then
  echo "$voice"
  exit 0
fi

body="$($MYDIR/ai-tts-model.sh fish "$voice_id" "$text")"
response=$($MYDIR/api-fish.sh POST "v1/tts" "$body")
require -f response '-MPEG ADTS, layer III'

response_ogg="${response}-${speaking_rate}x.ogg"
if [[ ! -f "$response_ogg" ]]; then
  if [[ $speaking_rate == 1 && $volume == 1 ]]; then
    ffmpeg <&1- -v 16 -y -i "$response" -c:a libopus -b:a 128K "${response_ogg}"
  elif [[ $speaking_rate == 1 ]]; then
    ffmpeg <&1- -v 16 -y -i "$response" -filter:a "volume=$volume" -c:a libopus -b:a 128K "${response_ogg}"
  elif [[ $volume == 1 ]]; then
    ffmpeg <&1- -v 16 -y -i "$response" -filter:a "atempo=$speaking_rate" -c:a libopus -b:a 128K "${response_ogg}"
  else
    ffmpeg <&1- -v 16 -y -i "$response" -filter:a "atempo=$speaking_rate,volume=$volume" -c:a libopus -b:a 128K "${response_ogg}"
  fi
  require -f response_ogg -Opus
fi

if [[ -n "$out" ]]; then
    cp "${response_ogg}" "$out"
    echo "$out"
else
    echo "${response_ogg}"
fi
