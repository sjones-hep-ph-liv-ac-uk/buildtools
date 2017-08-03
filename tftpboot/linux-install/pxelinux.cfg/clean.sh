#!/bin/bash
pattern="hdBoot"
if [ $# > 0 ]; then
  if [ "$1" == "all" ]; then
    pattern=".*"
  fi
fi

for link in `ls C0*`; do
  ls -lrt $link | grep "$pattern" > /dev/null
  if [ $? == 0 ]; then
    rm $link
  fi
done

