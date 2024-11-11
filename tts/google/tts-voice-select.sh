#!/bin/bash -e
# converts text into speech
# https://cloud.google.com/text-to-speech/docs/voices
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $MYDIR/../../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $(real require.sh)

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    >&2 echo "$ME - returned $1 at line $2"
  fi
}

# en-us doesn't have neural2 B so it's removed:
RANGE="ACDEFGHIJ"
TYPES="Standard,Neural2"
TYPE=Neural2
GENDERS="MALE,FEMALE"

while test $# -gt 0
do
    case "$1" in
    --random-american)
      lang=en-US
      lang_code=${lang,,}
      voice=$lang-$TYPE-$(echo "$RANGE" | fold -w1 | shuf -n1)
      gender=$(random-csv-val.sh "$GENDERS")

      # echo "--lang-code $lang_code --voice $voice --gender $gender"
      echo "--lang-code $lang_code --voice $voice"
      exit 0
    ;;
    --random)
      shift
      filter="$1"

      lang_voice=$(cat $MYDIR/voices.csv | random.sh "$filter" 2,3)

      lang_code=$(echo "$lang_voice" | cut -d',' -f1)
      voice=$(echo "$lang_voice" | cut -d',' -f2)
      echo "--lang-code $lang_code --voice $voice"
      exit 0
    ;;
    -*)
      err "bad option '$1'"
    ;;
    esac
    shift
done
