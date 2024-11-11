#!/bin/bash -e
# converts text into speech
# https://api.elevenlabs.io/docs#/text-to-speech/Text_to_speech_v1_text_to_speech__voice_id__post
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)
API_URL='https://texttospeech.googleapis.com/v1'

source $MYDIR/../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $(real require.sh)

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    >&2 echo "$ME - returned $1 at line $2"
  fi
}
