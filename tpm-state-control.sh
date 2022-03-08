#!/bin/bash
set -e

export TPM_PATH=/tmp/vtpm

[ -z "${1}" ] && echo "${0} [rm(clear)/cp(backup&exit)/cprm(backup&clear)/rst(restore)]"

if [[ ${1} == "rst" ]]; then
	echo "restore backed up tpm state"
	rm -vrf ${TPM_PATH}
	cp -vr vtpm_bak ${TPM_PATH}
	chmod -vR 0640 ${TPM_PATH}
	chmod -v 0755 ${TPM_PATH}
elif [[ $1 == "cp" ]]; then
	echo "backup tpm state"
	rm -vrf vtpm_bak
	cp -vrp ${TPM_PATH} vtpm_bak
	exit 0
elif [[ $1 == "cprm" ]]; then
	echo "backup & clear tpm state"
	rm -vrf vtpm_bak
	cp -vrp ${TPM_PATH} vtpm_bak
	rm -vrf ${TPM_PATH}
elif [[ $1 == "rm" ]]; then
	echo "clear tpm state"
	rm -vrf ${TPM_PATH}
else
	echo "${0} [rm(clear)/cp(backup&exit)/cprm(backup&clear)/rst(restore)]"
fi

# ensure dir exists
mkdir -vp ${TPM_PATH}

pkill swtpm || true
pkill tpm2-abrmd || true
sleep 1

swtpm socket \
--daemon \
--server type=tcp,port=2321,disconnect \
--ctrl type=tcp,port=2322 \
--tpmstate dir=${TPM_PATH} \
--tpm2 \
--flags not-need-init,startup-clear \
--runas 0 \
--log file=logtpm.log,truncate

sleep 1
echo "Swtpm daemon started"

tpm2-abrmd -o --tcti "swtpm" &

sleep 1
echo "tpm2 resource manager daemon started"
