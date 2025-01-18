#!/bin/bash

lvremove /dev/pve/data
lvresize -l +100%FREE /dev/pve/root
resize2fs -p /dev/pve/root