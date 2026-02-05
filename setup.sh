#!/bin/bash
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)

link.sh "$MYDIR/ai-debate.sh" ai-debates
link.sh "$MYDIR/video-chapters.sh" aidb-chapters
link.sh "$MYDIR/suggest.sh" aidb-suggest
link.sh "$MYDIR/remake.sh" aidb-remake
