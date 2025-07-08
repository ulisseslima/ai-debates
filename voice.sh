#!/bin/bash -e
# @installable
# generates a voice for tts depending on the provider
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    info "$ME - //${pad_n_topic} - returned $1 at line $2"
  fi
}

source $MYDIR/_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $(real require.sh)

require -d FACE_LIBRARY
info "FACE_LIBRARY=$FACE_LIBRARY"

name="$1"
require name 'voice name'
shift

sex="${1,,}"
require sex 'voice sex'
shift

tts_provider=google

while test $# -gt 0
do
    case "$1" in
    --tts-provider)
      shift
      tts_provider="$1"
    ;;
    *)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

sexf=${sex:0:1} # f/m
info "sexf=$sexf; tts_provider=$tts_provider"

tts_face=$(find $FACE_LIBRARY -name "${sexf}-*-p01.png" | random.sh)
require tts_face "${sexf}-*-p01.png in '$FACE_LIBRARY' ($name/$sex)"
tts_voice=$($MYDIR/tts/tts.sh --voice-only --provider $tts_provider --voice-preference "${sex}")
require tts_voice

voice_key="${tts_provider}|$tts_voice|$tts_face"
echo "${voice_key}"