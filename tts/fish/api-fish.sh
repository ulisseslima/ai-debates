#!/bin/bash -e
# https://fish.audio/app/api-keys/
# https://docs.fish.audio/api-reference/endpoint/openapi-v1/text-to-speech
# https://docs.fish.audio/api-reference/endpoint/model/list-models
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)
API_URL='https://api.fish.audio'

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    >&2 echo "$ME - returned $1 at line $2"
  fi
}

source $MYDIR/../../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV
source $(real require.sh)

# verbose=on
require FISH_AUDIO_KEY
require API_REQUESTS_INTERVAL

retries=5
# model used for tts synthesis. one of: s1, s2-pro, s2.1-pro, s2.1-pro-free, drama-3
fish_tts_model="${FISH_AUDIO_MODEL:-s2.1-pro-free}"

function do_request() {
	local method="$1"; shift
	local endpoint="$1"; shift
	local body="$1"

	body_md5=$(md5_body "$body")
	format="accept: audio/mpeg"

	# --oauth2-bearer lets curl build the auth header itself from the api key
	curl_opts="--location --oauth2-bearer $FISH_AUDIO_KEY"
	if [[ "$verbose" == on ]]; then
		curl_opts="$curl_opts -v"
	fi

	info "-X $method $API_URL/$endpoint"
	info "body: $body"

	request_cache="$CACHE/${method}-${endpoint//\//_}_${body_md5}.request.json"
	debug "request cache: $request_cache"

	if [[ -n "$body" && ! -f "$body" ]]; then
		tmpf=/tmp/$body_md5
		echo "$body" > $tmpf
		body=$tmpf
	fi

	if [[ -f "$body" ]]; then
		cp "$body" $request_cache

		curl $curl_opts -X $method "$API_URL/$endpoint" \
			-d "@$body" \
			-H "Content-Type: application/json" \
			-H "model: $fish_tts_model" \
			-H "$format" > "$out"

		echo "$out"
	else
		curl $curl_opts -X $method "$API_URL/$endpoint"
	fi
}

method="$1"; shift
endpoint="$1"; shift
body="$1"

require method
require endpoint
if [[ $method != GET ]]; then
	require body 'request body'
	body_md5=$(md5_body "$body")
	info "md5: $body_md5"
fi

endpoint_name="${method}-${endpoint//\//_}"
if [[ -n "$body" ]]; then
	out="$CACHE/${endpoint_name}_${body_md5}.response.mp3"
else
	out="$CACHE/${endpoint_name}_${body_md5}.response.json"
fi
mkdir -p $(dirname "$out")
last_response=$(last_response_minutes "$out")
if [[ "$last_response" -lt $API_REQUESTS_INTERVAL ]]; then
	debug "last response to $endpoint_name was $last_response minutes ago. interval is $API_REQUESTS_INTERVAL minutes. returning from cache..."
	info "[$last_response/$API_REQUESTS_INTERVAL min.] response cache: $out"

	if [[ "$out" == *json ]]; then
		cat "$out"
	else
		echo "$out"
	fi

	exit 0
else
	debug "last response to $endpoint_name was $last_response minutes ago. cache interval is $API_REQUESTS_INTERVAL"
fi

tries=0
while [[ -z "${response}" || "${response,,}" == *'bad gateway'* ]]
do
	response=$(do_request "$method" "$endpoint" "$body")
	tries=$((tries+1))
	if [[ $tries -gt $retries ]]; then
		break
	fi
done

if [[ -f "$response" ]]; then
	debug "response cached to $out"
else
	if [[ "$response" == *html* ]]; then
		err "$response"
	elif [[ "$response" == *'insufficient_quota'* || "$response" == *'quota_exceeded'* ]]; then
		err "$response"
	elif [[ "$response" == *'server_error'* ]]; then
		err "$response"
	elif [[ "$response" == *'heavy traffic'* ]]; then
		err "$response"
	else
		echo "$response" > "$out"
		debug "response cached to $out"
	fi
fi

echo "$response"
