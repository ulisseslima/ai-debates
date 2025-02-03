#!/bin/bash -e
# @installable
# render waveforms into video
# to preview:
# aidb-render-audio $ogg --preview
# * https://huggingface.co/spaces/fffiloni/expression-editor
# TODO descobrir como utilizar o valor de lavfi.astats.Overall.RMS_level em tempo real para usar nas animações:
# * https://stackoverflow.com/questions/60088776/ffmpeg-how-to-pipe-rms-level-and-pts-time-metadata-without-generating-unwanted
# * https://superuser.com/questions/1225239/how-do-i-constrain-a-value-to-audio-frequency-in-ffmpeg
# * https://stackoverflow.com/questions/15792105/simulating-tv-noise
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

audio="$1"
require -f audio
shift

test=false
preview=false
projectd="$(dirname $audio)"
topic=$(basename "$projectd")
topic_txt=$(echo "${topic^}" | tr '-' ' ')
stages_overlay="/tmp/stages_overlay-$topic"
stages_overlay2="${stages_overlay}2"
rm -f ${stages_overlay}*

# point line p2p cline
mode=line

##
# a square image of a chosen bg color
function bg_square() {
  color=$1

  out="/tmp/bg${color}.png"
  if [[ ! -f "$out" ]]; then
    ffmpeg <&1- -y -v 16 -f lavfi -i color=c=${color}:s=200x200:d=1 -frames:v 1 "$out"
  fi

  echo "$out"
}

##
# render audio waveforms
function render() {
  info "creating waveform video: $audio ..."
  n=$(echo "$audio" | cut -d'-' -f1)
  
  fname=$(basename "$audio" | rev | cut -d'.' -f2- | rev)
  fixedname=$(echo "${fname/-with-pause/}" | cut -d'-' -f3)

  out="$projectd/${fname}.mp4"
  if [[ -f "${out}" && $preview == false ]]; then
    info "already rendered: ${out}"
    exit 0
  else
    info "$n rendering $audio to $out (preview=$preview)"
  fi

  tmp_wav_out="$projectd/tmp-wav-${fname}.mp4"
  tmp_fx_out="$projectd/tmp-fx-${fname}.mp4"

  tmpd="$projectd/tmp"
  mkdir -p "$tmpd"

  right_panel_offx=50
  clock=false
  emoticon=false
  footer_bg='#4f5d48'
  
  face_resolution=300:300
  facex=400
  facey=339
  
  case "$fname" in
    *question*)
      bg=1d1f1c
      fg=4f5d48
      mode=point
      person=Audience
    ;;
    *positive*)
      facex=400
      facey=239
      facedat=positive

      bg=252525
      fg=007bce
      mode=line
      person=$(cat "$projectd/positive.persona")
      clock=true
      emoticon=true
      positive=true
      footer_bg='#10456f'
    ;;
    *negative*)
      facex=1370
      facey=539
      facextra=",hflip"
      facedat=negative

      bg=252525
      fg=533d38
      mode=cline
      person=$(cat "$projectd/negative.persona")
      clock=true
      emoticon=true
      positive=false
      footer_bg='#5f342b'
    ;;
    *judge*)
      bg=252525
      footer_bg='#4f5d48'
      fg=4f5d48
      mode=point
      person=Judge
    ;;
    *)
      bg=252525
      fg=4f5d48
      mode=p2p
      person=Mediator
    ;;
  esac

  ttscache="$projectd/tts_${facedat}.dat"
  if [[ -f "$ttscache" ]]; then
    info "using face from tts: $ttscache"
    tts_face1=$(cat $ttscache | cut -d'|' -f3)
    tts_face2="${tts_face1/-p01/-p02}"

    require -f tts_face1
    require -f tts_face2
  else
    info "$ttscache - generating solid background: $bg"
    tts_face1=$(bg_square $bg)
    info "tts_face1: $tts_face1"
    tts_face2=$(bg_square $bg)
    info "tts_face2: $tts_face2"
  fi

  waveform_offx=25
  if [[ ! -f "$tmp_fx_out" ]]; then
    fxfilter="
    [2:v]scale=${face_resolution}${facextra}[scaled1];
    [3:v]scale=${face_resolution}${facextra}[scaled2];
    [0:a]aformat=channel_layouts=mono,showwaves=size=1280x720:mode=$mode:rate=30:colors=$fg[wav];
    [1:v][scaled1]overlay=x=${facex}:y=${facey}:enable='lt(mod(floor(t*2),2), 1)'[face1];
    [face1][scaled2]overlay=x=${facex}:y=${facey}:enable='gt(mod(floor(t*2),2), 0)'[face2];
    [face2][wav]overlay=format=auto:x=((W-w)/2)+${right_panel_offx}+${waveform_offx}:y=(H-h)/2,format=yuv420p[vfx];
    "

    ffmpeg <&1- -y -v 16 -i $audio\
    -f lavfi -i color=size=1920x1080:rate=30:color=$bg\
    -i $tts_face1 -i $tts_face2\
    -filter_complex "$fxfilter"\
    -map "[vfx]" -map 0:a -c:v libx264 -c:a copy -shortest "${tmp_wav_out}"

    if [[ "$clock" == true ]]; then
      ffmpeg-render-countdown.sh "$tmp_wav_out"\
       --offset-y -50 --offset-x +150 --font-size 64\
       -o "$tmp_fx_out"
    else
      cp "$tmp_wav_out" "$tmp_fx_out"
    fi
  fi
  # else
  #   ffmpeg -v 16 -i $audio\
  #   -f lavfi -i color=size=1920x1080:rate=30:color=$bg\
  #   -filter_complex "[0:a]aformat=channel_layouts=mono,showwaves=size=1280x720:mode=$mode:rate=30:colors=$fg[v];[1:v][v]overlay=format=auto:x=((W-w)/2)+${right_panel_offx}+${waveform_offx}:y=(H-h)/2,format=yuv420p[outv]"\
  #   -map "[outv]" -map 0:a -c:v libx264 -c:a copy -shortest -f matroska - | ffplay -
  # fi

  stage=$(echo "${fname}" | cut -d'-' -f3 | tr '_' ' ')
  stage="| ${stage^}"
  info "# stage: $stage"

  padding_size=18
  while read stage_name
  do
    if [[ "$stage_name" != "$stage"* ]]; then
      echo "$stage_name" >> $stages_overlay
      rpad "| " $padding_size >> $stages_overlay2
    else
      rpad "| " $padding_size >> $stages_overlay
      echo "$stage_name" >> $stages_overlay2
    fi
  done < <(echo "$chapters")

  info "generating style..."
  chapters_bg='#1d1f1c'
  chapters_fg='#dfdfdf'
  chapters_fg_unselected='#4f5d48'
  box_opacity=1

  chapters_text=$(ffmpeg-text.sh $stages_overlay --font monospace --color "$chapters_fg_unselected" --font-border-color "$chapters_bg" --medium --box-color "$chapters_bg" --y-offset +200)
  chapters_over=$(ffmpeg-text.sh $stages_overlay2 --font monospace --color "$chapters_fg" --font-border-color "$chapters_bg" --medium --box-color "$chapters_bg" --y-offset +200)

  header=$(ffmpeg-box.sh "$topic_txt" --font Roboto --color "$chapters_fg" --font-border-width 0 --font-border-color "$chapters_fg_unselected" --medium --top-center --page-width 150 --box-color "$chapters_fg_unselected" --box-opacity $box_opacity)
  
  panel_args="--font "FreeSerif" --color '${chapters_fg_unselected}' --font-border-color '$footer_bg' --size 90 --box-size 250 --right ${right_panel_offx} --box-color '$chapters_bg' --box-opacity $box_opacity --text-bottom-right"
  right_panel=$(ffmpeg-box.sh " " $panel_args)
  if [[ $emoticon == false ]]; then
    right_panel_close=$(ffmpeg-box.sh "•. °" $panel_args --enable "lt(mod(t*2,2), 1)")
    right_panel_open=$(ffmpeg-box.sh "° .•" $panel_args --enable "gt(mod(t*2,2), 1)")
  else
    if [[ "$positive" == true ]]; then
      info "positive $positive"
      right_panel_close=$(ffmpeg-box.sh "(°◡°)" $panel_args --enable "lt(mod(t*2,2), 1)")
      right_panel_open=$(ffmpeg-box.sh "(°o°)" $panel_args --enable "gt(mod(t*2,2), 1)")
      # (mod() is modulo)
    elif [[ "$positive" == false ]]; then
      info "positive $positive"
      right_panel_close=$(ffmpeg-box.sh "(ง'̀-'́)ง" $panel_args --enable "lt(mod(t*2,2), 1)")
      right_panel_open=$(ffmpeg-box.sh "(ง'̀•'́)ง" $panel_args --enable "gt(mod(t*2,2), 1)")
    fi
  fi
  
  footer=$(ffmpeg-box.sh "$person" --font Roboto --color "$chapters_fg" --font-border-color "$footer_bg" --medium --bottom-center --page-width 150 --box-color "$footer_bg" --box-opacity $box_opacity)

  if [[ "$person" == Judge ]]; then
    duration=$(ffmpeg-info.sh "$audio" duration)
    duration_half=$(op.sh "$duration/2")

    score_args="--medium --page-width 50 --x-offset +300 --y-offset +300 --color '$chapters_fg' --font-border-color '$chapters_bg' --box-color '$chapters_fg_unselected'"
    score1=$(ffmpeg-text.sh "$projectd/persona1-scores.md" $score_args --animate x 1 $duration_half)
    score2=$(ffmpeg-text.sh "$projectd/persona2-scores.md" $score_args --animate x $duration_half $duration)
    score_overlay=",${score1},${score2}"
  fi

  command="${chapters_text},${chapters_over},${footer},${header}${score_overlay}"
  command="${command},${right_panel},${right_panel_close},${right_panel_open}"

  if [[ "$preview" == false ]]; then
    ffmpeg-text.sh --command "$command" --in "${tmp_fx_out}" --out "$out"
    rm -f ${stages_overlay}*

    mv "${tmp_wav_out}" "$tmpd"
    mv "${tmp_fx_out}" "$tmpd"
    echo "$out"
  else
    info "previewing source: $tmp_fx_out"
    ffmpeg-text.sh --command "$command" --preview "$tmp_fx_out"
  fi

  if [[ $test == true ]]; then
    info "$tmp_fx_out"
  fi
}

while test $# -gt 0
do
    case "$1" in
    --chapters)
      shift
      chapters="$1"
    ;;
    --preview)
      # shift
      preview=true
      
      # previewf="$1"
      # require -f previewf
    ;;
    --mode)
      shift
      mode=$1
    ;;
    --clear)
      rm -f "$stages_overlay"*
    ;;
    --test)
      test=true
    ;;
    -*)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

if [[ -z "$chapters" ]]; then
  if [[ ! -f "$projectd/raw-chapters.md" ]]; then
    chapters=$($MYDIR/render-audios.sh "$(dirname $audio)" --chapters-only)
  else
    chapters=$(cat "$projectd/raw-chapters.md")
  fi
fi

render "$audio"