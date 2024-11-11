#!/bin/bash -e
# https://platform.openai.com/account/usage
# https://platform.openai.com/docs/api-reference/authentication
# https://platform.openai.com/account/api-keys
# https://platform.openai.com/docs/api-reference/images
MYSELF="$(readlink -f "$0")"
MYDIR="${MYSELF%/*}"
ME=$(basename $MYSELF)
API_URL='https://api.openai.com/v1'

source $MYDIR/../_env.sh
[[ -f $LOCAL_ENV ]] && source $LOCAL_ENV 
source $(real require.sh)

# verbose=on
require OPENAI_KEY
require API_REQUESTS_INTERVAL

retries=5

function do_auth_header() {
    echo "Authorization: Bearer $OPENAI_KEY"
}

function do_request() {
	local method="$1"; shift
	local endpoint="$1"; shift
	local body="$1"; shift

	body_md5=$(md5_body "$body")
    auth="$(do_auth_header)"

	curl_opts="--location"
	if [[ "$verbose" == on ]]; then
		curl_opts="$curl_opts -v"
    fi

	# >&2 echo "verbose: $verbose"
    debug "-X $method $API_URL/$endpoint"
	debug "$auth"
	debug "body: $body"

	request_cache="$CACHE/${method}-${endpoint}_${body_md5}.request.json"
	debug "request cache: $request_cache"
	
	if [[ -f "$body" ]]; then
		cp "$body" $request_cache

		curl $curl_opts -X $method "$API_URL/$endpoint"\
			-d "@$body"\
			-H "Content-Type: application/json"\
			-H "$auth"
	elif [[ -n "$body" ]]; then
		echo "$body" > $request_cache
		
		if [[ "$endpoint" == *'speech' ]]; then
			curl $curl_opts -X $method "$API_URL/$endpoint"\
				-d "$body"\
				-H "Content-Type: application/json"\
				-H "$auth"\
				--output "$out"
			echo "$out"
		else
			curl $curl_opts -X $method "$API_URL/$endpoint"\
				-d "$body"\
				-H "Content-Type: application/json"\
				-H "$auth"
		fi
	else
		curl $curl_opts -X $method "$API_URL/$endpoint"\
			-H "$auth"
	fi
}

method="$1"; shift
endpoint="$1"; shift
body="$1"; shift

require method
require endpoint
if [[ $method != GET ]]; then
	require body 'request body'
	body_md5=$(md5_body "$body")
	info "md5: $body_md5"
fi

endpoint_name="${method}-${endpoint}"
format=json
[[ $endpoint == *'speech' ]] && format=mp3

out="$CACHE/${endpoint_name}_${body_md5}.response.$format"
mkdir -p $(dirname "$out")
last_response=$(last_response_minutes "$out")
if [[ "$last_response" -lt $API_REQUESTS_INTERVAL ]]; then
	debug "last response to $endpoint_name was $last_response minutes ago. interval is $API_REQUESTS_INTERVAL minutes. returning from cache..."
	info "[$last_response/$API_REQUESTS_INTERVAL min.] response cache: $out"

	touch "$out"
	if [[ $format == json ]]; then
		cat "$out"
	else
		echo "$out"
	fi
	exit 0
else
	debug "last response to $endpoint_name was $last_response minutes ago. cache interval is $API_REQUESTS_INTERVAL"
fi

tries=0
while [[ -z "${response}" || $error == true ]]
do
	debug "tries: $tries"
	response=$(do_request "$method" "$endpoint" "$body")

	give_up=false
	error=false
	if [[ -z "${response}" && "$endpoint" == *'images/generations' ]]; then
		echo "$response" >> /tmp/error
		err "couldn't generate image. log: /tmp/error"
	elif [[ "${response,,}" == *'<html'* && "$endpoint" != *'images/generations' ]]; then
		error=true
		err "$response"
	elif [[ "${response,,}" == *invalid_request_error* ]]; then
		error=true
		err "$response"
	elif [[ "$response" == *insufficient_quota* ]]; then
		give_up=true
		error=true
		err "$response"
	elif [[ "$response" == *rate_limit_exceeded* ]]; then
		give_up=true
		error=true
		err "$response"
	elif [[ "$response" == *server_error* || "$response" == *internal_error* ]]; then
		error=true
		err "$response"
	elif [[ "${response,,}" == *'bad gateway'* ]]; then
		error=true
		err "$response"
	elif [[ "${response,,}" == *'rate limit reached'* ]]; then
		error=true
		err "$response"
	fi

	# TODO
	# Rate limit reached for gpt-3.5-turbo-instruct in organization org-F7BPMoISHuwyZbSBMejz769D on requests per min (RPM): Limit 3500, Used 3500, Requested 1. Please try again in 17ms.
	# Rate limit reached for gpt-3.5-turbo-instruct in organization org-F7BPMoISHuwyZbSBMejz769D on tokens per min (TPM): Limit 90000, Used 89919, Requested 1144. Please try again in 708ms

	tries=$((tries+1))
	if [[ $tries -gt $retries ]]; then
		break
	fi
done

if [[ $error != true ]]; then
	if [[ $format == json ]]; then
		echo "$response" > "$out"
	fi
	debug "response cached to $out"
fi

if [[ $give_up == true ]]; then
	exit 0
fi

echo "$response"
