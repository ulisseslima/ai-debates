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
# checks if a section already exists in the script file
function section_exists() {
  local section_marker="$1"
  [[ -f "$script" ]] && grep -qF "$section_marker" "$script"
}

##
# writes to script file only if section doesn't exist
function write_section() {
  local section_marker="$1"
  local content="$2"
  
  if ! section_exists "$section_marker"; then
    echo -e "$content" | tee -a "$script"
  else
    info "section already exists in script: $section_marker"
  fi
}

##
# generates a tts file
function speech() {
  txt="$1"
  voice_key="$2"
  out="$3"
  speed=${4:-1.25}

  info "processing '$voice_key' ..."
  provider=$(echo $voice_key | cut -d'|' -f1)
  tts_voice=$(echo $voice_key | cut -d'|' -f2)

  require provider
  require tts_voice

  padded_order=$(lpad $order)
  outf="$projectd/$padded_order-debate-${out}.ogg"

  section_marker="# $padded_order - ${out^^}"
  
  if ! section_exists "$section_marker"; then
    echo "$section_marker" | tee -a $script
    echo -e "${txt}\n" >> "$script"
  else
    info "section already in script: $section_marker"
  fi
  
  order=$((order+1))

  if [[ "$script_only" == true ]]; then
    warn "script only, not generating tts: $outf"
    return 0
  fi

  if [[ ! -f "$outf" ]]; then
    info "generating '$provider' tts [$tts_voice]@$speed: $txt"
    $MYDIR/tts/tts.sh "$txt" --tts-provider "$provider" --voice "$tts_voice" --speed $speed -o "$outf"
  else
    info "already created: $outf"
  fi
}

start=$(elapsed.sh)
tts_provider_a=google # audience, etc
tts_provider_b=elevenlabs.io # debaters
script_only=false
order=1
suspend=false
yes=true

# generate a hot topic
#topic="should all drugs be legalized?"
topic="$1"
require topic
shift

topic_name=$(safe_name "$topic")
# Script is now fully idempotent and will resume from where it left off

while test $# -gt 0
do
    case "$1" in
    --suspend)
      suspend=true
      info "will suspend machine when finished"
    ;;
    --reset)
      $MYDIR/api/ai-chat.sh --context $topic_name --delete true
    ;;
    -y)
      yes=true
    ;;
    --confirm|-n)
      yes=no
    ;;
    --script-only)
      script_only=true
    ;;
    # all
    --tts)
      shift
      tts_provider_a="$1"
      tts_provider_b="$1"
    ;;
    # mediator, judge, audience
    --tts-a)
      shift
      tts_provider_a="$1"
    ;;
    # debater voices
    --tts-b)
      shift
      tts_provider_b="$1"
    ;;
    -*)
      err "bad option '$1'"
      exit 1
    ;;
    esac
    shift
done

projectd="$PROJECTS/$topic_name"
mkdir -p $projectd
script="$projectd/debate.md"

# Resume from last order if script exists
if [[ -f "$script" ]]; then
  last_order=$(grep -oP '^# \K\d+' "$script" | tail -1 || echo "0")
  order=$((last_order + 1))
  info "resuming from order $order (last completed: $last_order)"
else
  order=1
  info "starting new debate script"
fi

# Check if personas already exist from previous run
if [[ -f "$projectd/positive.persona" ]] && [[ -f "$projectd/negative.persona" ]]; then
  info "reusing existing personas from previous run"
  persona1=$(cat "$projectd/positive.persona" | cut -d'#' -f1 | xargs)
  persona1_class=$(cat "$projectd/positive.persona" | cut -d'#' -f2 | xargs)
  persona1_sex=$(cat "$projectd/positive.persona" | cut -d'#' -f3 | xargs)
  
  persona2=$(cat "$projectd/negative.persona" | cut -d'#' -f1 | xargs)
  persona2_class=$(cat "$projectd/negative.persona" | cut -d'#' -f2 | xargs)
  persona2_sex=$(cat "$projectd/negative.persona" | cut -d'#' -f3 | xargs)
  
  info "positive: '$persona1' ($persona1_class) $persona1_sex, negative: '$persona2' ($persona2_class) $persona2_sex"
  response=$(grep -A 100 "^# PERSONAS" "$script" | grep -v "^# PERSONAS" | head -n -1 || echo "")
else
  # Generate new personas
  response=$($MYDIR/api/ai-chat.sh --prompt "generate two interesting, opposite personas like 'Alfred, a libertarian' or 'Guadalupe, social democrat' for a debate with the theme '$topic'")

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
  if [[ $yes != true ]]; then
    info "<y> to continue..."
    read personas
  else
    info "skipped confirmation"
    personas=y
  fi
done

  # Save personas for idempotency
  echo "$persona1#$persona1_class#${persona1_sex^^}" > $projectd/positive.persona
  echo "$persona2#$persona2_class#${persona2_sex^^}" > $projectd/negative.persona
fi

topic_section="# TOPIC
${topic} - $persona1_class vs. $persona2_class

# PERSONAS
$response
"
write_section "# TOPIC" "$topic_section"

info "generating voices..."
# TODO don't repeat voices, pitch shift 1.15
# TODO google doesn't allow rate with some languages. shift to ffmpeg
tts_voice_positive=$(voice positive "${persona1_sex^^}" $tts_provider_b)
tts_voice_negative=$(voice negative "${persona2_sex^^}" $tts_provider_b)
tts_voice_mediator=$(voice mediator random $tts_provider_a)
tts_voice_judge=$(voice judge random $tts_provider_a)
tts_voice_audience=$(voice audience random $tts_provider_a)

positions_section="# DEBATERS POSITIONS
positive: '$persona1' ($persona1_class) $persona1_sex - voiced by $tts_voice_positive
negative: '$persona2' ($persona2_class) $persona2_sex - voiced by $tts_voice_negative
"
write_section "# DEBATERS POSITIONS" "$positions_section"

##
# Introduction
# The speech() function now checks if content exists before writing and generating TTS
speech="Today, we'll debate '$topic' with $persona1, a $persona1_class; and $persona2, a $persona2_class. They're two Artificial Intelligence personas. Please introduce yourselves."
speech "$speech" "$tts_voice_mediator" introduction

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --system "$response" --prompt "$persona1, you have 1 minute to introduce yourself and your worldviews in a funny manner. No script cues, just pure dialog.")
speech "$speech" "$tts_voice_positive" positive-introduction 1.4

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, you have 1 minute to introduce yourself and your worldviews in a funny manner. No script cues, just pure dialog.")
speech "$speech" "$tts_voice_negative" negative-introduction 1.4

# Argument 1
speech="Thank you, guys. $persona1 and $persona2. Will now present their 3 rounds of arguments."
speech "$speech" "$tts_voice_mediator" arguments

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, you have 1 minute to present a positive argument about the debate topic, taking ${persona2}'s background into consideration and referencing real-life, historical examples")
speech "$speech" "$tts_voice_positive" positive_1-argument 1

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, you have 1 minute to present a negative argument about the debate topic, taking ${persona1}'s background into consideration and referencing real-life, historical examples")
speech "$speech" "$tts_voice_negative" negative_1-argument 1

# Argument 2
speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, you have 1 minute to present a second round of arguments about the debate topic, taking ${persona2}'s arguments into consideration, but include snarky comments for entertainment")
speech "$speech" "$tts_voice_positive" positive_2-argument 1

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, you have 1 minute to present a second round of arguments about the debate topic, taking ${persona1}'s arguments into consideration, but include snarky comments for entertainment")
speech "$speech" "$tts_voice_negative" negative_2-argument 1

##
# Rejoinders
speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, you have 1 minute to refute ${persona2}'s arguments. Be polite, but persuasive. Use quick humor jabs to spice the debate with some provocation. At the end, sum up key points.")
speech "$speech" "$tts_voice_positive" rejoinder_1-positive 1

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, you have 1 minute to refute ${persona1}'s arguments. Be polite, but persuasive. Use quick humor jabs to spice the debate with some provocation. At the end, sum up key points.")
speech "$speech" "$tts_voice_negative" rejoinder_2-negative 1

##
# Audience Questions
speech="Thank you for your speeches. Someone from the audience will now make a question to $persona1 and $persona2."
speech "$speech" "$tts_voice_mediator" 'questions'

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --system "you're a person from the audience watching the debate" --prompt "Introduce yourself briefly and ask a question about a point that wasn't touched before in ${persona1}'s arguments")
speech "$speech" "$tts_voice_audience" qa_positive-audience-question 1.4

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, reply to the question")
speech "$speech" "$tts_voice_positive" qap_answer-audience-positive 1.3

##
# question 2
speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "Ask a question about a point that wasn't touched before in ${persona2}'s arguments.")
speech "$speech" "$tts_voice_audience" qa_negative-audience-question 1.4

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, reply to the question.")
speech "$speech" "$tts_voice_negative" qan_answer-audience-negative 1.3

speech="The debaters now have a minute to talk about something they regret not bringing up to the discussion."
speech "$speech" "$tts_voice_mediator" closing-regrets

##
# Closing Considerations
speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona1, in a relaxed manner, joke about something you regret not bringing up to the discussion, and a terrible argument brought up by $persona2")
speech "$speech" "$tts_voice_positive" r_positive-closing 1.4

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --prompt "$persona2, in a relaxed manner, joke about something you regret not bringing up to the discussion, and a terrible argument brought up by $persona1")
speech "$speech" "$tts_voice_negative" r_negative-closing 1.4

##
# Judges
speech="Thank you, folks. Let's go over to our judges."
speech "$speech" "$tts_voice_mediator" scoring

prompt="Generate 3 scores for $persona1 and 3 scores for $persona2, based on formal debate metrics. Explain your scoring logic and parameters.
Use the following format for the output:
# ${persona1}’s Scores:
1. <score 1 summary>
<details>
2. <score 2 summary>
<details>
3. <score 3 summary>
<details>

# ${persona2}’s Scores:
1. <score 1 summary>
<details>
2. <score 2 summary>
<details>
3. <score 3 summary>
<details>"

speech=$($MYDIR/api/ai-chat.sh --context $topic_name --system "you're the debate's judge" --prompt "$prompt")
speech "$(safe_md "$speech")" "$tts_voice_judge" judge-scoring 1.5

echo "${persona1}’s Scores:" > "$projectd/persona1-scores.md"
echo "$speech" | sed -n "/$persona1’s Scores/,/$persona2’s Scores/p" | sed '$d' | grep -P "^[\d]" >> "$projectd/persona1-scores.md"

echo "${persona2}’s Scores:" > "$projectd/persona2-scores.md"
echo "$speech" | sed -n "/$persona2’s Scores/,\$p" | sed '$d' | grep -P "^[\d]" >> "$projectd/persona2-scores.md"

##
# ask the viwers to suggest a debate topic
speech="What are your opinions about the debate? What would you like to see AI's debate next? Keep questioning!"
speech "$speech" "$tts_voice_mediator" end

$MYDIR/api/ai-chat.sh --context $topic_name --delete true

total_time=$(elapsed.sh $start --minutes)
info "debate+tts time: $total_time minutes"

if [[ "$script_only" == true ]]; then
    info "$script - to generate the video, run: "
    echo aidb-remake $projectd
    exit 0
fi

$MYDIR/render-audios.sh "$projectd"

total_time=$(elapsed.sh $start --minutes)
info "rendering time: $total_time minutes"

$MYDIR/group-videos.sh "$projectd" debate 0

if ! section_exists "# Video Chapters"; then
  echo "" >> $script
  echo "# Video Chapters" >> $script
  $MYDIR/video-chapters.sh "$projectd" >> $script
else
  info "video chapters already in script"
fi

ai-thumbnail "$topic" -o "$projectd/thumbnail.jpg"

info "done"
if [[ $suspend == true ]]; then
    info "suspending..."
    systemctl suspend
fi
