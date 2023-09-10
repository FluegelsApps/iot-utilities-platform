#!/bin/bash
###########

offline_mode=false

# Handle flags and command line arguments
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      echo "Help"
      exit 0
      ;;
    --offline)
      offline_mode=true
      ;;
  esac
  shift
done

# Pre-installation check: cURL installation
if [ "$offline_mode" = false and which curl &> /dev/null ]; then
  echo "Install curl to use this installation script or use the offline mode '--offline'"
  exit 1
fi

# Pre-installation check: Docker installation
if [ which docker &> /dev/null ]; then
  echo "Install docker (compose) to use this installation script"
  exit 1
fi