#!/bin/bash

for l in `ls -lrt | grep "[A-F0-9][A-F0-9]* \-> hdBoot.cfg"  | cut -d" " -f 11`; do  
  rm -i $l; 
done

