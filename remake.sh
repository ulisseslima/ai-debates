#!/bin/bash -e
# @installable
# regenerates the video by processing the individual audio files again
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    info "$ME - // returned $1 at line $2"
  fi
}

source $MYDIR/_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $(real require.sh)

projectd="$1"
require -d projectd
shift

ttsregen=true

while test $# -gt 0
do
    case "$1" in
    --suspend)
      suspend=true
      info "will suspend machine when finished"
    ;;
    --tts-regen)
      ttsregen=true
      info "will regenerate tts if needed"
    ;;
    -*)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

function check_voice() {
  pfacef=$projectd/tts_${1}.dat
  if [[ ! -f pfacef ]]; then
    persona_sex=$(cat $projectd/${1}.persona | cut -d'#' -f3)
    voice $1 "${persona_sex}" elevenlabs.io
    require -f pfacef
  fi

  tts_provider=$(cat $pfacef | cut -d'|' -f1)
  tts_pvoice=$(cat $pfacef | cut -d'|' -f2)
  tts_pvoice2=$(echo $tts_pvoice | rev | cut -d' ' -f1 | rev)
  tts_pface=$(cat $pfacef | cut -d'|' -f3)
  if [[ -z "$tts_pface" ]]; then
    echo "adding $1 face for $tts_pvoice..."
    tts_psex=$(cat $MYDIR/tts/google/voices.csv | grep "$tts_pvoice2" | cut -d',' -f4)
    tts_psex=${tts_psex,,}
    echo "- tts_psex=$tts_psex"

    tts_pface=$(find $FACE_LIBRARY -name "${tts_psex:0:1}-*-p01.png" | random.sh)
    require tts_pface
    echo "- tts_pface=$tts_pface"

    echo "${tts_provider}|$tts_pvoice|$tts_pface" > "$pfacef"
  fi
}

##
# generates a tts file
function speech() {
    txt="$1"
    outf="$2"

    outfname=$(basename "$outf")
    padded_order=$(echo "$outfname" | cut -d'-' -f1)

    case "$(basename $outf)" in
        *question*)
            speed=1.4
            voicef="$projectd/tts_audience.dat"
        ;;
        *positive*)
            speed=1.1
            voicef="$projectd/tts_positive.dat"
        ;;
        *negative*)
            speed=1.1
            voicef="$projectd/tts_negative.dat"
        ;;
        *judge*)
            speed=1.5
            voicef="$projectd/tts_judge.dat"
        ;;
        *)
            speed=1.2
            voicef="$projectd/tts_mediator.dat"
        ;;
    esac

    provider=$(cat $voicef | cut -d'|' -f1)
    tts_voice=$(cat $voicef | cut -d'|' -f2)

    if [[ ! -f "$outf" ]]; then
        info "$outf: generating '$provider' tts [$tts_voice]@$speed: $txt"
        $MYDIR/tts/tts.sh "$txt" --tts-provider "$provider" --voice "$tts_voice" --speed $speed -o "$outf"
    else
        info "$outf: already created"
    fi
}

function oggcount() {
    # count the number of .ogg files in $projectd
    ls -1 $projectd/*.ogg 2>/dev/null | wc -l
}

function check_audio() {
    # check the number of .ogg files in $projectd
    oggfiles=$(oggcount)
    if [[ "$ttsregen" == true || $oggfiles -eq 0 ]]; then
        info "ttsregen=$ttsregen - re-generating .ogg in $projectd ..."
        # iterate over each section in debate.md
        while read section
        do
            # get the section title
            title=$(echo $section | cut -d' ' -f2-)
            # get the section number
            number=$(echo $title | cut -d' ' -f1)
            name=$(echo $title | cut -d' ' -f3)

            ttsf="$projectd/$number-debate-${name,,}.ogg"
            if [[ -f "$ttsf" ]]; then
                info "skipping $section: $ttsf already exists"
                continue
            fi

            if [[ $(nan.sh $number) == true ]]; then
                info "skipping $section: '$number' is not a number"
                continue
            else
                info "processing $section"
            fi

            # get all text before next section
            text=$(cat $projectd/debate.md | sed -n "/$section/,/# /p" | sed '$d' | grep -v "$section")
            info "generating tts for $section"

            speech "$text" "$ttsf"
        done < <(cat $projectd/debate.md | grep -P '^#')
        
        oggfiles=$(oggcount)
        info "audio regeneration complete: $oggfiles .ogg files created"
    else
        info "ttsregen=$ttsregen - found $oggfiles .ogg files in $projectd. skipping tts regen..."
    fi
}

speech=$projectd/debate.md

pfile=$projectd/positive.persona
require -f pfile
persona1=$(cat $pfile | cut -d'#' -f1 | xargs)

nfile=$projectd/negative.persona
require -f nfile
persona2=$(cat $nfile | cut -d'#' -f1 | xargs)

check_voice positive
check_voice negative

pscores=$projectd/persona1-scores.md
if [[ ! -f "$pscores" ]]; then
  echo "${persona1}’s Scores:" > "$pscores"
  cat "$speech" | sed "s/'/’/g" | sed "s/ out of /\//" | sed -n "/$persona1’s Scores/,/$persona2’s Scores/p" | sed '$d' | grep -P "^[\d]" >> "$pscores"
fi
require -f pscores

nscores=$projectd/persona2-scores.md
if [[ ! -f "$nscores" ]]; then
  echo "${persona2}’s Scores:" > "$nscores"
  cat "$speech" | sed "s/'/’/g" | sed "s/ out of /\//" | sed -n "/$persona2’s Scores/,\$p" | sed '$d' | grep -P "^[\d]" >> "$nscores"
fi
require -f nscores

rm -f $projectd/persona1-scores.md.tmp
rm -f $projectd/persona2-scores.md.tmp

mkdir -p $projectd/leftovers
while read video
do
  mv $video $projectd/leftovers
done < <(ls -1 $projectd/*.mp4)

rm -rf "$projectd/bkdebate"
if [[ -d "$projectd/debate" ]]; then
  mv "$projectd/debate" "$projectd/bkdebate"
fi

rm -rf "$projectd/bktmp"
if [[ -d "$projectd/tmp" ]]; then
  mv "$projectd/tmp" "$projectd/bktmp"
fi

check_audio
info "rendering audios in $projectd ..."
$MYDIR/render-audios.sh $projectd && $MYDIR/group-videos.sh $projectd debate 0
info "re-rendering complete"

if [[ $suspend == true ]]; then
    info "suspending..."
    systemctl suspend
fi