---

## Containerization (Optional)

This project includes an optional Dockerfile to support containerized execution and improve
environment consistency. Use of Docker is not required to reproduce the results.

The Docker container encapsulates the R runtime and package dependencies only. Users must
configure access to credentialed datasets such as MIMIC IV locally and mount them into the
container in accordance with PhysioNet data use agreements.

Docker is provided as a convenience and does not replace the primary script based
reproducibility workflow described above.
