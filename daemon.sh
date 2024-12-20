#!/bin/bash

#simple script to restart run.sh when it asks to be restarted with code 2

export YOU_ARE_BEING_RUN_BY_DAEMON=1 #informed consent

while true;do
  "$(dirname "$0")/run.sh"
  exitcode=$?
  if [ $exitcode == 0 ];then
    exit 0
  elif [ $exitcode != 2 ];then
    exit 1
  fi
done
