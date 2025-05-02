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
    if [[ -n "$sex" ]]; then
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
    info "generated $name voice: ${voice_key}"
  fi

  echo $voice_key
}

##
# generates a tts file
function speech() {
  txt="$1"
  voice_key="$2"
  out="$3"
  speed=${4:-1.25}

  provider=$(cat $voice_key | cut -d'|' -f1)
  tts_voice=$(cat $voice_key | cut -d'|' -f2)

  padded_order=$(lpad $order)
  outf="$projectd/$padded_order-debate-${out}.ogg"

  if [[ "$script_only" == true ]]; then
    info "script only, not generating tts: $outf"
    return 0
  fi

  if [[ ! -f "$outf" ]]; then
    info "generating '$provider' tts [$tts_voice]@$speed: $txt"
    $MYDIR/tts/tts.sh "$txt" --tts-provider "$provider" --voice "$tts_voice" --speed $speed -o "$outf"
    
    echo "# $padded_order - ${out^^}" | tee -a $script
    echo -e "${txt}\n" >> "$script"
  else
    info "already created: $outf"
  fi
  order=$((order+1))
}

start=$(elapsed.sh)
tts_provider=google
script_only=false
order=1
suspend=false
yes=true

# generate a hot topic
# topic="should all drugs be legalized?"
topic="$1"
require topic
shift

topic_name=$(safe_name "$topic")
# TODO
# * check if topic was already started and replace or resume

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

echo -e "# TOPIC
${topic} $persona1, a $persona1_class vs. $persona2_class

# PERSONAS
$response
\n" | tee -a "$script"

info "generating voices..."
# TODO don't repeat voices, pitch shift 1.15
# TODO google doesn't allow rate with some languages. shift to ffmpeg
tts_voice_positive=$(voice positive "${persona1_sex^^}" elevenlabs.io)
tts_voice_negative=$(voice negative "${persona2_sex^^}" elevenlabs.io)
tts_voice_mediator=$(voice mediator)
tts_voice_judge=$(voice judge)
tts_voice_audience=$(voice audience)

echo -e "# DEBATERS POSITIONS
positive: '$persona1' ($persona1_class) $persona1_sex - voiced by $tts_voice_positive
negative: '$persona2' ($persona2_class) $persona2_sex - voiced by $tts_voice_negative
\n" | tee -a "$script"

echo "$persona1 ($persona1_class)" > $projectd/positive.persona
echo "$persona2 ($persona2_class)" > $projectd/negative.persona

##
# Introduction
# TODO ver o que fazer pra não chamar o ai-chat se já tiver o arquivo. hoje depende de estar no cache pra não repetir a chamada e bugar tudo
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

$MYDIR/render-audios.sh "$projectd"

total_time=$(elapsed.sh $start --minutes)
info "rendering time: $total_time minutes"

$MYDIR/group-videos.sh "$projectd" debate 0

echo "" >> $script
$MYDIR/video-chapters.sh "$projectd" >> $script

info "done"
if [[ $suspend == true ]]; then
    info "suspending..."
    systemctl suspend
fi
