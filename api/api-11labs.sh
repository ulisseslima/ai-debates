#!/bin/bash -e
# https://beta.elevenlabs.io/subscription
# https://docs.elevenlabs.io/guides/text-to-speech
# https://docs.elevenlabs.io/api-reference/voices
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)
API_URL='https://api.elevenlabs.io/v1'

trap 'catch $? $LINENO' ERR
catch() {
  if [[ "$1" != "0" ]]; then
    >&2 echo "$ME - returned $1 at line $2"
  fi
}

source $MYDIR/../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $(real require.sh)

# verbose=on
require ELEVEN_LABS_KEY
require API_REQUESTS_INTERVAL

retries=5

function do_auth_header() {
    echo "xi-api-key: $ELEVEN_LABS_KEY"
}

function do_request() {
	local method="$1"; shift
	local endpoint="$1"; shift
	local body="$1"

	body_md5=$(md5_body "$body")
    auth="$(do_auth_header)"
	format="accept: audio/mpeg"

	curl_opts="--location"
	if [[ "$verbose" == on ]]; then
		curl_opts="$curl_opts -v"
    fi

    info "-X $method $API_URL/$endpoint"
	debug "$auth"
	info "body: $body"

	request_cache="$CACHE/${method}-${endpoint}_${body_md5}.request.json"
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
			-H "$auth" \
			-H "$format" > "$out"
		
		echo "$out"
	else
		curl $curl_opts -X $method "$API_URL/$endpoint"\
			-H "$auth"
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

endpoint_name="${method}-${endpoint}"
if [[ -n "$body" ]]; then
	out="$CACHE/${endpoint_name}_${body_md5}.response.mp3"
else
	out="$CACHE/${endpoint_name}_${body_md5}.response.json"
fi
mkdir -p $(dirname "$out")
last_response=$(last_response_minutes "$out")
if [[ "$last_response" -lt $API_REQUESTS_INTERVAL && $endpoint != 'user/subscription' ]]; then
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
