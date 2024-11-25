#!/bin/bash -e
# @installable
# generates speech from text using the available APIs
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
debug "sourced"

start=$(elapsed.sh)

text="$1"
require text "text to speech"
shift

start=1
end=1
speed=1.25

while test $# -gt 0
do
    case "$1" in
    --out|-o)
        shift
        out=$1
    ;;
    --start|-s)
      shift
      start=$1
    ;;
    --end|-e)
      shift
      end=$1
    ;;
    --speed)
      shift
      speed=$1
    ;;
    --tts-provider|--provider)
      shift
      tts_provider=$1
    ;;
    --voice)
        shift
        voice="$1"
    ;;
    --voice-preference)
        shift
        voice_preference="$1"
    ;;
    -*)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

require tts_provider

if [[ -z "$voice" ]]; then
    case $tts_provider in
        google)
            if [[ -z "$voice_preference" ]]; then
                voice=$($MYDIR/google/tts-voice-select.sh --random-american)
            else
                voice=$($MYDIR/google/tts-voice-select.sh --random "$voice_preference")
            fi
        ;;
        OpenAI|openai)
            voice=$($MYDIR/tts-openai.sh random none)
        ;;
        elevenlabs.io|eleven)
            voice=$($MYDIR/tts-11.sh random none)
        ;;
        *)
            err "unreognized tts provider: $tts_provider"
            exit 1
        ;;
    esac
fi

if [[ "$text" == --voice-only ]]; then
    echo "$voice"
    exit 0
fi

if [[ -z "$out" ]]; then
    out=/tmp/$(safe_name "$text")
fi

info "- read by $voice"

function tts() {
    text="$1"
    ttsf="$2"

    require text
    require ttsf
    
    tries=0
    max_retries=5
    while [[ ! -f "$ttsf" && $tries -lt $max_retries ]]; do
        if [[ "$tries" -gt 0 ]]; then
            >&2 echo "└ ${ttsf} - retrying tts [$tries] ..."
            sleep 60
        fi

        >&2 echo "└ ${ttsf} - generating $tts_provider tts..."
        case $tts_provider in
            OpenAI)
                ttsf=$($MYDIR/openai/tts-openai.sh $voice "$text" -o "${ttsf}" -x $speed)
            ;;
            elevenlabs.io)
                set +e
                ttsf=$($MYDIR/elevenlabs.io/tts-11.sh "$voice" "$text" -o "${ttsf}" -x $speed)
                return_code=$?
                set -e

                if [[ "$return_code" != 0 ]]; then
                    tts_provider=google
                    voice=$($MYDIR/tts.sh --voice-only --provider $tts_provider)
                    err "falling back to google tts with $voice ..."
                fi
            ;;
            *)
                ttsf=$($ROOT/api/api-gcloud-tts.sh "$text" -o "$ttsf" -x $speed $voice)
                if [[ "$ttsf" == *'check sentence lengths'* ]]; then
                    last_response=$($ROOT/last-response.sh completions)
                    err "manual check required on: $last_response"
                    break
                fi
            ;;
        esac

        tries=$((tries+1))
    done

    require -f ttsf
    
    if [[ $start == 0 && $end == 0 ]]; then
        echo "$ttsf"
    else
        info "$ME start: $start, end: $end"
        edited_audio=$(ffmpeg-silence.sh "$ttsf" --start $start --end $end)
        require -f edited_audio
        echo "$edited_audio"
    fi
}

tts "$text" "$out"