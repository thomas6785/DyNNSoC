#!/bin/bash

push firmware

ssh ws2 -t "cd ~/storage/firmware ; PATH=\$PATH:/opt/riscv/bin ; make | grep -i error"

pull /mnt/storage/local/users/thomas/firmware
