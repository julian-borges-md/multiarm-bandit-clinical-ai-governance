# Docker (Optional)

This directory contains optional Docker configuration to support containerized execution
of the Multi Arm Bandit Governance for Clinical AI pipeline.

Docker is provided as a convenience to improve environment consistency and is not required
to reproduce results. All analyses can be run directly in a local R environment using the
script based workflow described in the main README.

The Docker container encapsulates the R runtime and system dependencies only. Users must
configure access to credentialed datasets such as MIMIC IV locally and mount them into the
container in accordance with PhysioNet data use agreements.

## Build

From the repository root:

```bash
docker build -f docker/Dockerfile -t mab-governance .
