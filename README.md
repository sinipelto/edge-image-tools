# edge-image-tools

Imaging tools for creating and publishing images ready for Azure IoT Edge.

Designed to be run in a pipeline, using e.g. Azure pipelines.

## About repository structure

### Directories:

* config - Directory contains all variable definitions to be used for the scripts.
* example_config - Contains template configuration files to be edited by personal requirements and copied over the `config` directory.
* image_files - Directory for storing e.g. configuration files to be copied into the created system image.
* example_image_files - Contains template image configuration files to be edited be personal requirements and copied over the `image_files` directory.


### Files:

* create-image.sh - Script to download a fresh official system image, unpack it, optionally expand it, patch and configure it, finally repack the image.
* publish-image.sh - Script for publishing the patched and packed image file into a file share / cloud storage. Currently only supports Azure File Share (Azure Storage Account). 
* local-wrapper.image.sh - A Wrapper script for creating and publishing the iot edge system image with optimal local configuration variables. Eases testing the system as whole. Acts as a local replacement for the actual pipeline 
* flash-image.sh - A script for flashing the created image into a SD card to be inserted into the target device. Designed to work also in Windows environments using a bash emulator.
* provision-image.sh - Script for provisioning the edge device at first boot to install dependencies, and configure azure iot edge. Also polls for new images and updates the system as such available.
* provisioning.service - Provides the systemd service configuration wrapper for the provisioning service script.
* wait-for-it.sh - A utility script for waiting for a specific host and port to be available over network connection. Useful for testing network access to critical services.

## Running locally

To run the scripts locally:

First, copy over the configuration example files over (see the subdirectories README files). 

Ensure all variables set correctly in `config/local_config`.

Ensure all image configuration files are configured with proper values in `image_files/`

Run the tests to see if any required parameters missing or empty:

```bash
/bin/bash local-wrapper-image.sh 'test'
```

Should respond:

```bash
Script self-test OK
...
```

for each script tested.

Ensure no errors are thrown.

Finally, execute the wrapper script:

```bash
/bin/bash local-wrapper-image.sh
```
