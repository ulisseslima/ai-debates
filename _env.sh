#!/bin/bash -e

if [[ $EUID -eq 0 ]]; then
    echo "this script should NOT be run as root" 1>&2
    exit 2
fi

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
ROOT="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
REPO_NAME=$(basename $ROOT)

TODAY=$(now.sh -d)

CONFD=$HOME/.${REPO_NAME}
LOCAL_ENV=$CONFD/config

if [[ ! -f $LOCAL_ENV ]]; then
    >&2 echo "creating config file: $LOCAL_ENV"
    mkdir -p $CONFD
    >&2 echo "# $TODAY" > $LOCAL_ENV
fi

CACHE=/tmp/$REPO_NAME/cache
mkdir -p $CACHE

PROJECTS=$ROOT/projects
mkdir -p $ROOT/bin

LOGS="$CACHE/logs"

FFMPEG_TMP=$CACHE/ffmpeg

TTS_ELEVEN=$MYDIR/elevenlabs.io
FFMPEG=$MYDIR/ffmpeg

# logging
export verbose=off
tts_provider=google

# commom terminal colors
TCRED='\033[0;31m'
TCGREEN='\033[0;32m'
TCYELLOW='\033[0;33m'
TCBLUE='\033[0;34m'
TCPURPLE='\033[0;35m'
TCCYAN='\033[0;36m'
TCLIGHT_GRAY='\033[0;37m'
TCDARK_GRAY='\033[1;30m'
TCLIGHT_RED='\033[1;31m'
TCMAGENTA='\033[1;35m'
TCNC='\033[0m' # No Color
TCBOLD='\033[1m'

function log() {
    level="$1"
    shift

    TCindicator="$1"
    shift

    TCcolor="$1"
    shift

	if [[ "$1" == '-n' ]]; then
		echo ""
		shift
	fi

    if [[ $level == DEBUG && "$verbose" == on || $level != DEBUG ]]; then
        echo -e "${TCcolor}${TCindicator} $(now.sh -t) - ${FUNCNAME[2]}@${BASH_LINENO[1]}/$level:${TCNC} ${TCBOLD}${TCcolor}$@${TCNC}"
    fi
    echo -e "$REPO_NAME - $TCindicator $(now.sh -dt) - ${FUNCNAME[2]}@${BASH_LINENO[1]}/$level: $@" >> $LOGS
}

function info() {
    # change log color to $CYAN
    >&2 log INFO '###' "${TCCYAN}" "$@"
}

function err() {
    >&2 log ERROR '!!!' "${TCLIGHT_RED}" "$@"
}

function debug() {
    >&2 log DEBUG '<->' "${TCLIGHT_GRAY}" "$@"
}

function warn() {
    >&2 log WARN '???' "${TCMAGENTA}" "$@"
}

for var in "$@"
do
    case "$var" in
        --verbose|--debug|-v)
            shift
            >&2 echo "debug is on"
            export verbose=on
        ;;
        --quiet|-q)
            shift
            export verbose=off
        ;;
    esac
done

# APIs
# minutes before sending a repeated request. helps keeping within daily limits
API_REQUESTS_INTERVAL=1440

##
# @param $1 file to check
# @return minutes since last modification
function last_response_minutes() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		echo $API_REQUESTS_INTERVAL
		return 0
	fi

	local secs=$(echo $(($(date +%s) - $(stat -c %Y -- "$file"))))
	echo $((${secs}/60))
}

##
# removes special characters
function safe_name() {
    # remove non ascii:
    name=$(echo "$1" | iconv -f utf8 -t ascii//TRANSLIT)
    limit=${2:-100}

    # to lower case:
    name=$(echo ${name,,})
    # replace spaces for "-", then remove anything that's non alphanumeric
    safen=$(echo ${name// /-} | sed 's/[^a-z0-9-]//g')
    echo "${safen:0:$limit}"
}

##
# removes special markdown characters for tts
function safe_md() {
    echo "${1}" | sed 's/[*#`]//g' | replace.sh '\/' ' out of '
}

function lpad() {
    value=$1
    length=${2:-2}
    printf "%0${length}d\n" $value
}

function rpad() {
    string="$1"
    length=${2}

    printf "%-${length}s ...\n" "${string}"
}

##
# for math ops
function op() {
    expression="$1"
    round=2
    result=0.00

    while [[ $result == 0.00 ]]; do
        result=$(op.sh "$expression" --round $round)
        round=$((round+2))
    done

    echo $result
}

##
# for date ops
function interval() {
    op="$1"
    interval="$2"

    op.sh "select now() $op interval '$interval'"
}

##
# percentage difference between two values
function diff_percentage() {
    v1="$1"
    v2="$2"

    op "($v2 * 100) / $v1"
}

##
# removes and returns the last line from a file
function popf() {
    local file="$1"
    require -f file

    sed -e $(wc -l <"$file")$'{w/dev/stdout\n;d}' -i "$file"
}

function rotate_tts11_api_key() {
    max_tries=$(grep -c ELEVEN_LABS_KEY $LOCAL_ENV)
    tries=1
    # around 1k words or 6k chars for one of the debaters
    # credits in 11labs are variable
    min_chars_required=1200

    remaining=$($TTS_ELEVEN/tts-11-remaining-chars.sh)
    while [[ -z "$remaining" || $remaining -lt $min_chars_required ]]
    do
        if [[ $tries -gt $max_tries ]]; then
            echo "remaining: '$remaining' chars. can't use 11labs-tts."
            exit 1
        fi

        in_use=$(grep ELEVEN_LABS_KEY $LOCAL_ENV | grep -v '#' || true)
        if [[ -n "$in_use" ]]; then
            info "in_use=$in_use"
            sed -i "s/$in_use/#$in_use/g" $LOCAL_ENV
        fi

        key_line=$(grep -m $tries ELEVEN_LABS_KEY $LOCAL_ENV | tail -1)
        new_key=${key_line:1}
        sed -i "s/$key_line/$new_key/g" $LOCAL_ENV
        
        remaining=$($TTS_ELEVEN/tts-11-remaining-chars.sh)
        info "[$tries] trying new_key: $new_key ($remaining remaining)"

        tries=$((tries+1))
    done

    info "[$new_key] tts11 remaining chars: $remaining"
}

function duration() {
    ffmpeg-info.sh "$1" duration | cut -d'.' -f1
}

function md5_body() {
	local body="$1"

	if [[ -f "$body" ]]; then
		md5sum "$body" | cut -d' ' -f1
	elif [[ -n "$body" ]]; then
		echo "$body" | md5sum | cut -d' ' -f1
	else
		echo "-"
	fi
}

function wait_all() {
	while test $# -gt 0
	do
        [[ -z "$1" ]] && continue
		
        info "waiting pid $1..."
		wait $1
		shift
	done
}

function random_transition() {
    ffmpeg-random-transition.sh
}

# sanitize input for json values
# * escapes line breaks
# * replaces quotes with curly quotes
function sanitize_json() {
    echo "$1" | sed -z 's/\n/\\\\n/g' | sed "s/\"/”/g" | sed "s/'/‘/g"
}

##
# generates a voice code to use in TTS requests
function voice() {
  name="$1"
  sex="${2,,}"
  provider=${3:-$tts_provider}

  ttscache="$projectd/tts_${name}.dat"
  if [[ -f "$ttscache" ]]; then
    provider=$(cat $ttscache | cut -d'|' -f1)
    tts_voice=$(cat $ttscache | cut -d'|' -f2)
    tts_face=$(cat $ttscache | cut -d'|' -f3)

    voice_key="${provider}|$tts_voice|$tts_face"
    info "restored $name voice: ${voice_key}"
  else
    if [[ -n "$sex" && "$sex" != "random" ]]; then
        sex="${sex/nonbinary/female}"
        sex="${sex/non-binary/female}"
        sexf=${sex:0:1} # f/m
        
        tts_face=$(find $FACE_LIBRARY -name "${sexf}-*-p01.png" | random.sh)
        require tts_face "${sexf}-*-p01.png in '$FACE_LIBRARY' ($name/$sex)"
    fi
    
    tts_voice=$($MYDIR/tts/tts.sh --voice-only --provider $provider --voice-preference "${sex}")
    require tts_voice

    voice_key="${provider}|$tts_voice|$tts_face"
    echo "${voice_key}" > "$ttscache"
    info "${name^^} generated voice: ${voice_key}"
  fi

  echo $voice_key
}