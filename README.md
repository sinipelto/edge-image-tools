# edge-image-tools

[![Build Status](https://dev.azure.com/ThesisPoC/EdgeImageTools/_apis/build/status/EdgeImageTools?branchName=publish)](https://dev.azure.com/ThesisPoC/EdgeImageTools/_build/latest?definitionId=3&branchName=publish)

## General information

Imaging tools for creating and publishing images ready for Azure IoT Edge.

Designed to be run in a pipeline, using e.g. Azure pipelines.

## Repository structure

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

## Execution locally

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

## Execution using devops pipeline

To run the scripts in a pipeline

Ensure following requirements met:
- Compatible build agent and OS with sudo/root privileges (Currently Ubuntu 18.04/20.04 LTS supported)
- Target cloud file storage available and enough free space (Currently Azure File Share as SMB mount point supported)

Currently implemented pipelines:
- Azure DevOps Pipelines (see azure-pipelines.yml for reference)

Construct the pipeline configuration with at least following stages/jobs:
- execute script create-image.sh for creating the image file
- execute publish-image.sh for publishing the image in the cloud file share
- ensure necessary environment variables set for both scripts (see example_config/local_config file for variable reference)

In case a different publishing solution is needed, create a separate publish script
and execute it in the pipeline instead.

### Using the existing Azure Devops Pipeline configuration

Import this repo in Azure Devops Repos section.

Ensure the pipeline configuration (azure-pipelines.yml) is recognized by the Azure environment, and create a pipeline instance for it.

Set the necessary environment variables through the Azure Pipeline variables (ensure any secrets are marked as secret variables).

Configure a build agent for the pipeline (Microsoft hosted build agent with ubuntu-20.04 recommended).

Execute the pipeline to build and publish an image to a configured cloud storage.
