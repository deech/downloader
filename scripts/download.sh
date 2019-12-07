#!/bin/sh
curl -G "$1"  --data-urlencode "$2" --output "$3" --location --user-agent "$4" --write-out %{http_code} --silent --show-error
