# Example image asset files

This directory contains examples for all files to be copied over to the SD card image created and configured.

## Structure

95-network.yaml - For Ubuntu distros, not used by RaspiOS distros. Network configuration file for netplan. Defines both LAN and WLAN configs if specified.
network-config - For Ubuntu distros, not used by RaspiOS distros. Similar to network config yaml but distributed using the boot partition.
user-data - For Ubuntu distros, not used by RaspiOS distros. Contains system configuration parameters, like locale, timezone, keyboard, initial users configuration.  
wpa_supplicant.conf - For RaspiOS distros, not used by Ubuntu distros. Contains WLAN configuration, e.g. SSID and password to connect.

## Usage instructions

Copy all files over from the `../example_image_files` directory into the `../image_files` directory.

```bash
cp ../example_image_files/* ../image_files/
```

Modify the files to match your requirements.

Once done, the files are ready to be used by the image creation script.

## Devops support

If you are planning to wrap the system into a devops pipeline:

Remove the ignore entry from .gitignore for this directory.

Commit the files inside the directory into the new repository.
