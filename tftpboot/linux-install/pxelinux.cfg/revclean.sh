#!/bin/bash
pattern="hdBoot"

for link in `ls C0*`; do
  ls -lrt $link | grep -v "$pattern" > /dev/null
  if [ $? == 0 ]; then
    rm      $link
  fi
done

