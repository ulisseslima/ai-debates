#!/bin/bash -e
# converts text into speech
# https://cloud.google.com/text-to-speech/docs/reference/rest/v1/text/synthesize
# https://cloud.google.com/text-to-speech/docs/voices
# https://cloud.google.com/text-to-speech/pricing
# https://console.cloud.google.com/apis/api/texttospeech.googleapis.com/metrics?project=dvl-tts
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

verbose=off
prefix=0

text="${1}"; shift
token=$(gcloud auth print-access-token)
project_id="$GOOG_TTS_PROJECT_ID"

lang_code=en-us
voice=en-US-Neural2-H # 16 usd per mb of input
# voice=en-US-Standard-H # 4 usd per million chars of input
gender=FEMALE

# MP3, OGG_OPUS, MULAW (contains WAV header, check API docs)
audioEncoding=OGG_OPUS
OGG_OPUS=ogg
MP3=mp3

speaking_rate=1

require text
require token

hash=$(echo "${voice}-${text}-${audioEncoding}" | md5sum | awk '{print $1}')
require hash

# returns: 1 == true
function is_audio() {
  local f="$1"

  debug "checking if $f is a valid file..."

  if [[ ! -f "$f" ]]; then
    echo 0
    return 0
  fi
  
  file "$f" | grep -Pc '(MPEG ADTS, layer III|Ogg)' || true
}

while test $# -gt 0
do
    case "$1" in
    --verbose|-v)
      verbose=true
    ;;
    --lang-code|-c)
      shift
      lang_code="$1"
    ;;
    --voice)
      shift
      voice="$1"
    ;;
    --gender|-g)
      shift
      gender="${1^^}"
    ;;
    --rate|-x)
      shift
      speaking_rate="${1}"
    ;;
    --prefix)
      shift
      prefix="$1"
    ;;
    --project)
      shift
      project_id="${1}"
    ;;
    --out|-o)
      shift
      outf="$1"
    ;;
    --play)
      play=true
    ;;
    -*)
      err "bad option '$1'"
    ;;
    esac
    shift
done

require project_id

cached=$CACHE/$project_id/$hash
mkdir -p $cached
require -d cached

if [[ -z "$outf" ]]; then
  outf=$cached/${prefix}-$gender-$voice.${!audioEncoding}
fi
debug "project: $project_id"
debug "token: $token"
debug "hash: $hash"

# removed from voice object: 'ssmlGender':'${gender}'
if [[ $(is_audio "$outf") != 1 ]]; then
  debug "requesting tts..."

  sane_text="$(echo "$text" | sed "s/'/\\\'/g")"

  # pitch: -20.0, 20.0
  # speakingRate: 0.25, 4.0
  jsonf=$cached/$gender-$voice.json
  request="{
  	 'input':{
    	  'text':'$sane_text'
  	 },
  	 'voice':{
    	  'languageCode':'${lang_code}',
    	  'name':'${voice}'
  	 },
  	 'audioConfig':{
    	  'audioEncoding':'$audioEncoding',
        'speakingRate': $speaking_rate
  	 }
	}"

	curl -H "X-Goog-User-Project: $project_id" -H "Authorization: Bearer $token" -H "Content-Type: application/json; charset=utf-8"\
   --data "$request" "$API_URL/text:synthesize" > $jsonf
  
  debug "ttsrequest=$request"
  debug "response_jsonf=$jsonf"

  if [[ "$(cat $jsonf)" == *'sentences that are too long'* ]]; then
    # ~281 characters before period limit: https://github.com/googleapis/google-cloud-node/issues/4074
    echo "check sentence lengths:"
    check-sentence-lengths.sh "$sane_text"
    exit 1
  elif [[ "$(cat $jsonf)" == *error* ]]; then
    err "couldn't generate tts: $jsonf"
    exit 1
  fi

  cat $jsonf | jq -r .audioContent | base64 -d > "$outf"
  if [[ $(is_audio "$outf") == 0 ]]; then
    err "$(cat $jsonf)"
    err "$(file "$outf")"
    rm "$outf"
  fi
else
  info "returning from cache..."
fi

echo $outf
if [[ "$play" == true ]]; then
  play $outf
fi
