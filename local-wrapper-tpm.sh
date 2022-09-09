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

set -e

# Assuming either current user ROOT user or current user has SUDO
userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

# Read local variables from separate file
# shellcheck source=/dev/null
source local/local_config

bashBin='/bin/bash'

# Scripts to execute in this local wrapper
scripts=("${PWD}/tpm-device-build.sh" "${PWD}/tpm-attestation-build.sh")


################################################################################
################################	START	####################################
################################################################################

# shellcheck disable=SC2068
for script in ${scripts[@]}; do
	chmod -v +x "${script}"
	# Test all params are correctly set
	${bashBin} "${script}" 'test'
done

# If only testing, dont execute
if [[ ${1} != 'test' ]]; then
	# shellcheck disable=SC2068
	for script in ${scripts[@]}; do
		# If all ok, run the scripts
		${bashBin} "${script}"
	done
fi
