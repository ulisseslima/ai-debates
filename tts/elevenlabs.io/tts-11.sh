#!/bin/bash -e
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/../../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

voice_id=$1
if [[ "$voice_id" == 'random'* ]]; then
  # voice_id="$($MYDIR/tts-11-voices.sh | jq -r '.voices[].voice_id' | shuf -n1)"
  gender=$(echo $voice_id | cut -d'-' -f2)
  if [[ -n "$gender" ]]; then
    info "filter: $gender"
    voice="$($MYDIR/tts-11-voices.sh | jq -r '(.voices[] | [ .voice_id, .name, .labels.gender ]) | @tsv' | sed 's/\t/#/g' | grep -w ${gender,,} | shuf -n1)"
  else
    voice="$($MYDIR/tts-11-voices.sh | jq -r '(.voices[] | [ .voice_id, .name, .labels.gender ]) | @tsv' | sed 's/\t/#/g' | shuf -n1)"
  fi
  voice_id=$(echo "$voice" | cut -d'#' -f1)
  voice_name=$(echo "$voice" | cut -d'#' -f2)
  voice_gender=$(echo "$voice" | cut -d'#' -f3)
elif [[ "$voice_id" == *'#'* ]]; then
  full_voice=$voice_id
  voice_id=$(echo "$voice_id" | cut -d'#' -f1)
fi

require voice_id 'arg1'
shift

text=$1
require text
shift

speaking_rate=1

if [[ "$text" == none ]]; then
  echo "$voice"
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
      # not officially supported yet: https://help.elevenlabs.io/hc/en-us/articles/13416271012497-Can-I-slow-down-the-pace-of-the-voice-
      speaking_rate="${1}"
    ;;
    -*)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

body="$($ROOT/api/ai-simple-model.sh 11 "$text")"
response=$($ROOT/api/api-11labs.sh POST "text-to-speech/$voice_id" "$body")
require -f response '-MPEG ADTS, layer III'

response_ogg="${response}.ogg"
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
