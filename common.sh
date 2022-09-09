#!/bin/bash
# Copyright (C) 2022 Toni Blåfield
# 
# edge-image-tools is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# edge-image-tools is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
# 
# You should have received a copy of the GNU Lesser General Public License
# along with edge-image-tools. If not, see <http://www.gnu.org/licenses/>.


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
