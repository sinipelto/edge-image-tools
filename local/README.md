# Scripts configuration files

This directory contains all global and shared configurations for the scripts to be run.

## Structure

local_config - Configuration file containing environment variables suitable for local execution of the repo scripts without a devops pipeline.

## Usage instructions

Copy all files over from the `../example` directory into the `../local` directory.

```bash
cp ../example/* ../local/
```

Edit the file(s) to match your requirements.

Once done, the files are ready to be used by the image creation script.
