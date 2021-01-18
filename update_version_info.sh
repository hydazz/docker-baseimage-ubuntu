#!/bin/bash

OVERLAY_VERSION=${APP_VERSION//v/}

OLD_OVERLAY_VERSION=$(jq <version_info.json -r .overlay_version)

sed -i \
	-e "s/${OLD_OVERLAY_VERSION}/${OVERLAY_VERSION}/g" \
	README.md

NEW_VERSION_INFO="overlay_version
${OVERLAY_VERSION}"

jq -Rn '
( input  | split("|") ) as $keys |
( inputs | split("|") ) as $vals |
[[$keys, $vals] | transpose[] | {key:.[0],value:.[1]}] | from_entries
' <<<"$NEW_VERSION_INFO" >version_info.json
