#!/bin/bash
set -e

waitAptitude() {
	local count=0
	local countMax=300
	local unit=1

	echo "Waiting for previous apt session to finish.."

	while (( count < countMax )) && [[ $(pgrep -af apt) != "" ]]; do
		(( count += unit ))
		sleep ${unit}
	done

	if (( count >= countMax )); then echo "ERROR: Wait threshold reached. Could not access aptitude." && exit 1; fi
}

installPackages() {
	local packages=${1}

	apt-get update

	# shellcheck disable=SC2068
	apt-get install -y ${packages[@]}
}
