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

	(( count >= countMax )) && echo "ERROR: Wait threshold reached. Could not access aptitude." && exit 1

	# Note: last command retcode is 1 if the test succeeds, and would be returned from the function
	# so we need to return 0 explicitly
	return 0
}

installPackages() {
	local packages=${1}

	apt-get update

	# shellcheck disable=SC2068
	apt-get install -y ${packages[@]}

	return 0
}
