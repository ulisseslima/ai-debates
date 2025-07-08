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

debug=false
start=$(elapsed.sh)

text="$1"
require text "text to speech"
shift

start=1
end=1
speed=1.25
pitch=1

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
    --pitch)
        shift
        pitch=$1
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
    --debug)
        debug=true
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
    case ${tts_provider,,} in
        google)
            if [[ -z "$voice_preference" || "$voice_preference" == "random" ]]; then
                voice=$($MYDIR/google/tts-voice-select.sh --random-american)
            else
                voice=$($MYDIR/google/tts-voice-select.sh --random ",${voice_preference^^}")
            fi

            pitch=$(random-float.sh 0.8 1.10)
            info "random pitch: $pitch"
        ;;
        openai)
            if [[ -z "$voice_preference" || "$voice_preference" == "random" ]]; then
                voice=$($MYDIR/openai/tts-openai.sh random none)
            else
                voice=$($MYDIR/openai/tts-openai.sh random-${voice_preference,,} none)
            fi
        ;;
        elevenlabs.io|eleven)
            if [[ -z "$voice_preference" || "$voice_preference" == "random" ]]; then
                voice=$($MYDIR/elevenlabs.io/tts-11.sh random none)
            else
                voice=$($MYDIR/elevenlabs.io/tts-11.sh random-${voice_preference,,} none)
            fi
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

info "- read by '$voice' from '$tts_provider'"

##
# replaces: 
# * line breaks with spaces
# * em dashes with periods
# * removes emojis
# * removes asterisks
# * replaces quotes with curly quotes
# * replaces single quotes with curly single quotes
function sanitize_tts() {
    txt="$1"
    echo "$txt" | sed 's/\\\\n/ /g' | sed "s/—/. /g" | strip-emoji.sh | sed 's/\*//g' | sed "s/\"/”/g" | sed "s/'/‘/g"
}

function tts() {
    text="$1"
    ttsf="$2"

    require text
    require ttsf

    text=$(sanitize_json "$text")
    if [[ "$debug" == true ]]; then
        info "sanitize_json: $text"
    fi
    text=$(sanitize_tts "$text")
    if [[ "$debug" == true ]]; then
        info "sanitize_tts: $text"
    fi
    
    tries=0
    max_retries=5
    while [[ ! -f "$ttsf" && $tries -lt $max_retries ]]; do
        if [[ "$tries" -gt 0 ]]; then
            >&2 echo "└ ${ttsf} - retrying tts [$tries] ..."
            sleep 60
        fi

        >&2 echo "└ ${ttsf} - generating $tts_provider tts..."
        case ${tts_provider,,} in
            openai)
                ttsf=$($MYDIR/openai/tts-openai.sh $voice "$text" -o "${ttsf}" -x $speed)
            ;;
            elevenlabs.io|eleven)
                voice_gender=$(echo "$voice" | cut -d'#' -f3)

                set +e
                error=$(rotate_tts11_api_key)
                set -e

                if [[ -n "$error" ]]; then
                    tts_provider=google
                    voice=$($MYDIR/tts.sh --voice-only --provider $tts_provider --voice-preference $voice_gender)
                    err "falling back to google tts with $voice ..."
                    continue
                fi

                set +e
                ttsf=$($MYDIR/elevenlabs.io/tts-11.sh "$voice" "$text" -o "${ttsf}" -x $speed)
                return_code=$?
                set -e

                if [[ "$return_code" != 0 ]]; then
                    tts_provider=google
                    voice=$($MYDIR/tts.sh --voice-only --provider $tts_provider --voice-preference $voice_gender)
                    err "falling back to google tts with $voice ..."
                fi
            ;;
            google)
                ttsf=$($ROOT/api/api-gcloud-tts.sh "$text" -o "$ttsf" -x $speed $voice)
                if [[ "$ttsf" == *'check sentence lengths'* ]]; then
                    last_response=$($ROOT/last-response.sh completions)
                    err "manual check required on: $last_response"
                    break
                fi
            ;;
            *)
                err "unrecognized tts_provider: $tts_provider"
                break
            ;;
        esac

        tries=$((tries+1))
    done

    require -f ttsf

    if [[ $pitch != 1 ]]; then
        info "$ME: $ttsf - changing pitch: $pitch"
        pitched=$(ffmpeg-pitch.sh "$ttsf" $pitch)
        require -f pitched
        mv "$pitched" "$ttsf"
    fi
    
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