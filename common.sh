#!/bin/bash

waitAptitude() {
	local count=0
	local countMax=${1:-300}
	local unit=${2:-1}

	echo "Waiting for previous apt session to finish.."

	while (( count < countMax )) && [[ $(pgrep -af apt) != "" ]]; do
		(( count += unit ))
		sleep "${unit}"
	done

	(( count >= countMax )) && echo "ERROR: Wait threshold reached. Could not access aptitude." && return 1

	# Note: last command retcode is 1 if the test succeeds, and would be returned from the function
	# so we need to return 0 explicitly
	return 0
}

installPackage() {
	local pkg=${1}

	apt-get install -y "${pkg}"

	return 0
}

installPackages() {
	local pkgs=${1}

	apt-get update

	# shellcheck disable=SC2068
	apt-get install -y ${pkgs[@]}

	return 0
}

queryImageVersion() {
	local url=${1}
	local version

	version=$(curl -f -L "${url}")
	ret=$?

	[ ${ret} -ne 0 ] && [ ${ret} -ne 22 ] && echo "ERROR: Failed to query version." && return 1

	echo "${version}"
}
