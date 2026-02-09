# Container image that runs the mcix command line tool
FROM ghcr.io/mettleci/mcix:latest

# Copies the entrypoint file from the action repository to the filesystem path `/` of the container
COPY entrypoint.sh /entrypoint.sh

# File to execute when the docker container starts up
ENTRYPOINT ["/entrypoint.sh"]
