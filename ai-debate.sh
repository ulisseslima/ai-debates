#!/bin/bash -e
# @installable
# generates a debate on a topic
# let's you choose what type of person will debate, or randomize
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

##
# generates a voice code to use in TTS requests
function voice() {
  name="$1"
  sex="$2"

  cache="$projectd/tts_${name}.dat"
  if [[ -f "$cache" ]]; then
    tts_provider=$(cat $cache | cut -d'|' -f1)
    tts_voice=$(cat $cache | cut -d'|' -f2)
    info "restored $name voice: ${tts_provider}|$tts_voice"
  else
    tts_voice=$($MYDIR/tts/tts.sh --voice-only --provider $tts_provider --voice-preference "${sex}")
    echo "${tts_provider}|$tts_voice" > "$cache"
    info "generated $name voice: ${tts_provider}|$tts_voice|$sex"
  fi

  echo $tts_voice
}

##
# generates a tts file
function speech() {
  txt="$1"
  voice="$2"
  out="$3"

  padded_order=$(lpad $order)
  outf="$projectd/$padded_order-dabate-${out}.ogg"

  if [[ ! -f "$outf" ]]; then
    info "generating tts: $txt"
    $MYDIR/tts/tts.sh "$txt" --tts-provider $tts_provider --voice "$voice" -o "$outf"
    
    echo "## $padded_order - ${out^^}" | tee -a $script
    echo "$txt" >> "$script"
  else
    info "already created: $outf"
  fi
  order=$((order+1))
}

##
# groups files intro a single one
function group() {
  pattern="$1"
  order=$(lpad "$2")

  outn="$order-${pattern}_cut"
  outf="$projectd/${outn}.mp4"
  out="$projectd/${outn}-w_soundtrack.mp4"

  if [[ ! -f "$outf" ]]; then
    info "grouping: $pattern..."
    mkdir $projectd/$pattern && mv $projectd/*${pattern}*.mp4 $projectd/$pattern

    find "$projectd/$pattern" -maxdepth 1 -type f -name "*$pattern*.mp4" -printf "file '%p'\n" | sort | ffmpeg-concat.sh -o "$outf"
    require -f outf
  fi

  if [[ ! -f "$out" ]]; then
    faceless-soundtrack "$outf" -o "$out" --volume 0.2 --lib "$SONG_LIBRARY"
    readlink -f $out
    require -f out
    info "soundtrack ok: $out"
    if [[ -f "$outf" ]]; then
      mv "$outf" $projectd/$pattern
    fi
  fi

  echo "grouped $pattern: $out"
}

start=$(elapsed.sh)
tts_provider=google
order=1
suspend=true

# generate a hot topic
# topic="should all drugs be legalized?"
topic="$1"
require topic
shift

while test $# -gt 0
do
    case "$1" in
    --suspend)
        suspend=true
        info "will suspend machine when finished"
    ;;
    -*)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

topic_name=$(safe_name "$topic")
# TODO check if topic was already started and replace or resume

projectd="$PROJECTS/$topic_name"
mkdir -p $projectd
script="$projectd/debate.md"

response=$($MYDIR/api/ai-chat.sh --prompt "generate two interesting, opposite personas like 'Alfred, a libertarian' or 'Guadalupe, social democrat' for a debate with the theme '$topic'")
echo "$response"
info "<enter> to continue..."
read confirmation

prompt="Extract the name, denomination, and sex of the personas into the following format for each line: 
persona name#persona denomination#sex

Example:
Alfred#Libertarian#MALE
Guadalupe#Social Democrat#FEMALE

Important: considering the debate topic ($topic), the persona most suited for the positive argument must come first, while the persona most suited to argument against the topic should come last.
"

personas="$($MYDIR/api/ai-chat.sh --system "$response" --prompt "$prompt")"
while [[ "$personas" != y* ]]
do
  info "raw personas: $personas"
  persona1=$(echo -e "$personas" | head -1 | cut -d'#' -f1 | xargs)
  persona1_class=$(echo -e "$personas" | head -1 | cut -d'#' -f2 | xargs)
  persona1_sex=$(echo -e "$personas" | head -1 | cut -d'#' -f3 | xargs)

  persona2=$(echo -e "$personas" | tail -1 | cut -d'#' -f1 | xargs)
  persona2_class=$(echo -e "$personas" | tail -1 | cut -d'#' -f2 | xargs)
  persona2_sex=$(echo -e "$personas" | tail -1 | cut -d'#' -f3 | xargs)

  info "positive: '$persona1' ($persona1_class) $persona1_sex, negative: '$persona2' ($persona2_class) $persona2_sex"
  info "<y> to continue..."
  read personas
done

info "generating voices..."
# TODO don't repeat voices, pitch shift 1.15
tts_voice_positive=$(voice positive ",${persona1_sex}")
tts_voice_negative=$(voice negative ",${persona2_sex}")
tts_voice_mediator=$(voice mediator)
tts_voice_judge=$(voice judge)
tts_voice_audience=$(voice audience)

echo "# DEBATERS POSITIONS
positive: '$persona1' ($persona1_class) $persona1_sex - voiced by $tts_voice_positive
negative: '$persona2' ($persona2_class) $persona2_sex - voiced by $tts_voice_negative
" | tee -a "$script"

# introduction
speech="Today, we'll debate '$topic' with $persona1, a $persona1_class; and $persona2, a $persona2_class. They're two AI-generated personas. Please introduce yourselves."
speech "$speech" "$tts_voice_mediator" introduction

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --system "$response" --prompt "$persona1, you have 1 minute to introduce yourself and your worldviews")
speech "$speech" "$tts_voice_positive" introduction-positive

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, you have 1 minute to introduce yourself and your worldviews")
speech "$speech" "$tts_voice_negative" introduction-negative

# argument 1
speech="Thank you, guys. $persona1 and $persona2. Will now present their 3 rounds of arguments."
speech "$speech" "$tts_voice_mediator" arguments

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, you have 1 minute to present a positive argument about the debate topic")
speech "$speech" "$tts_voice_positive" argument1-positive

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, you have 1 minute to present a negative argument about the debate topic")
speech "$speech" "$tts_voice_negative" argument1-negative

# argument 2
speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, you have 1 minute to present a second round of arguments about the debate topic, taking ${persona2}'s arguments into consideration")
speech "$speech" "$tts_voice_positive" argument2-positive

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, you have 1 minute to present a second round of arguments about the debate topic, taking ${persona1}'s arguments into consideration")
speech "$speech" "$tts_voice_negative" argument2-negative

# rejoinders
speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, you have 1 minute to refute ${persona2}'s arguments. Be polite, but persuasive. Use quick humor jabs to spice the debate with some provocation. At the end, sum up key points.")
speech "$speech" "$tts_voice_positive" argument3-positive

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, you have 1 minute to refute ${persona1}'s arguments. Be polite, but persuasive. Use quick humor jabs to spice the debate with some provocation. At the end, sum up key points.")
speech "$speech" "$tts_voice_negative" argument3-negative

# question 1
speech="Someone from the audience will now make a question to $persona1 and $persona2."
speech "$speech" "$tts_voice_mediator" audience

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --system "you're a person from the audience watching the debate" --prompt "Introduce yourself briefly and ask a question about a point that wasn't touched before in ${persona1}'s arguments")
speech "$speech" "$tts_voice_audience" audience-positive-question

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, reply to the question")
speech "$speech" "$tts_voice_positive" audience-positive-answer

# question 2
speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "Ask a question about a point that wasn't touched before in ${persona2}'s arguments.")
speech "$speech" "$tts_voice_audience" audience-negative-question

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, reply to the question.")
speech "$speech" "$tts_voice_negative" audience-negative-answer

speech="The debaters now have a minute to talk about something they regret not bringing up to the discussion."
speech "$speech" "$tts_voice_mediator" closing-regrets

# closing considerations
speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, talk about something you regret not bringing up to the discussion")
speech "$speech" "$tts_voice_positive" closing-positive

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, talk about something you regret not bringing up to the discussion")
speech "$speech" "$tts_voice_negative" closing-negative

# score
speech=$($MYDIR/api/ai-chat.sh --context $topic_name --system "you're the debate's judge" --prompt "Generate 3 scores for $persona1 and 3 scores for $persona2, based on formal debate metrics. Explain your scoring logic and parameters.")
speech "$(safe_md "$speech")" "$tts_voice_judge" closing-judge

# 7
# ask the viwers to suggest a debate topic
speech="What are your opinions about the debate? What would you like to see AI's debate next? Keep questioning!"
speech "$speech" "$tts_voice_mediator" closing

total_time=$(elapsed.sh $start --minutes)
info "debate+tts time: $total_time minutes"

##
# render speeches
# TODO:
# * include a countdown timer
# * include all the parts of the debate, with the current one highlighted
# * include the name of the persona speaking
info "creating speech videos..."
while read audio
do
  n=$(echo "$audio" | cut -d'-' -f1)
  fname=$(basename "$audio")
  out="$projectd/$(echo "$fname" | rev | cut -d'-' -f3- | rev).mp4"
  if [[ -f "${out}" ]]; then
    info "already rendered: ${out}"
    continue
  fi

  case "$fname" in
    *question*)
      bg=1d1f1c
      fg=4f5d48
    ;;
    *positive*)
      bg=007bce
      fg=dfdfdf
    ;;
    *negative*)
      bg=533d38
      fg=dfdfdf
    ;;
    *)
      bg=252525
      fg=4f5d48
    ;;
  esac

  ffmpeg <&1- -y -v 16 -i $audio\
   -f lavfi -i color=size=1920x1080:rate=30:color=$bg\
   -filter_complex "[0:a]aformat=channel_layouts=mono,showwaves=size=1280x720:mode=cline:rate=30:colors=$fg[v];[1:v][v]overlay=format=auto:x=(W-w)/2:y=(H-h)/2,format=yuv420p[outv]"\
   -map "[outv]" -map 0:a -c:v libx264 -c:a copy -shortest "${out}"
done < <(ls -1tr $projectd/*with-pause.ogg)

total_time=$(elapsed.sh $start --minutes)
info "rendering time: $total_time minutes"

group debate 0
# group closing 99

# concat
# final_cut="$projectd/final_cut.mp4"
# find $projectd -maxdepth 1 -type f -name "*-*.mp4" -printf "file '%p'\n" | sort | ffmpeg-concat.sh -o "$final_cut"

# total_time=$(elapsed.sh $start --minutes)
# info "final time: $total_time minutes"

info "done: $final_cut"
if [[ $suspend == true ]]; then
    info "suspending..."
    systemctl suspend
fi