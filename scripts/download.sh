#!/bin/sh

if [ "$#" -eq 7 ]
then
    if [ "$7" = "basic" ]
    then
        curl --proxy-basic -x "$5" -U "$6" -G "$1"  --data-urlencode "$2" --output "$3" --location --user-agent "$4" --write-out %{http_code} --silent --show-error
    elif [ "$7" = "digest" ]
    then
        curl --proxy-digest -x "$5"  -U "$6"-G "$1"  --data-urlencode "$2" --output "$3" --location --user-agent "$4" --write-out %{http_code} --silent --show-error
    else
        echo "Unknown proxy authentication." 1>&2
    fi
elif [ "$#" -eq 5 ]
then
    curl -x "$5" -G "$1"  --data-urlencode "$2" --output "$3" --location --user-agent "$4" --write-out %{http_code} --silent --show-error
else
    curl -G "$1"  --data-urlencode "$2" --output "$3" --location --user-agent "$4" --write-out %{http_code} --silent --show-error
fi
