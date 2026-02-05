#!/bin/bash
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

source $(real require.sh)

topic="$1"
require topic "Please provide a topic for debate suggestions."

ai-chat "suggest a few hot topics (on the comic/absurd side) for debates on '$topic' in the format of 'AI debates: Is X better than Y? Protagonist vs Antagnonist' where X and Y are two opposing views on the topic and protagonist and antagonist are the respective debaters' personas, like 'libertarian vs socialist'. Make sure the topics are engaging and relevant to current events. Keep the theme short and catchy."
