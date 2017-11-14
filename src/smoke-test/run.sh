#!/bin/bash 
#===============================================================================
#          FILE:  run.sh
# 
#   DESCRIPTION:  
# 
#       CREATED: 11/14/2017 07:11:51 AM UTC
#===============================================================================
set -x

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_PATH

docker build -t smoke .
docker run -i -t -v ~/config.json:/opt/jenkins/config.json -v ~/.ssh:/opt/jenkins/.ssh -p 8090:8080 smoke


