# Dynamic template files

This directory contains examples for all files to be copied over to the SD card image created and configured.

All files should have the suffix .template to clearly distinguish the files from actual configuration files.

All variables are defined with format \<VARIABLE> and are replaced with the values provided by environment variables during the file copy process.

## Structure

90-network.yaml - For distros using Netplan network configuration system. Not used by RaspiOS distros. Network configuration file for netplan. Defines both LAN and WLAN configs if specified.

network-config - For Ubuntu distros, not used by RaspiOS distros. Similar to network config yaml but distributed using the boot partition.

user-data - For Ubuntu distros, not used by RaspiOS distros. Contains system configuration parameters, like locale, timezone, keyboard, initial users configuration.

wpa_supplicant.conf - For RaspiOS distros, not used by Ubuntu distros. Contains WLAN configuration, e.g. SSID and password to connect.

## Usage instructions

Set the corresponding environment variables values in either local/local_config file or in pipeline variables

Once done, the files are ready to be used by the image creation script.
