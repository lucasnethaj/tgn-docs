#!/bin/bash

NETWORK_FOLDER=$1
neuewelle $NETWORK_FOLDER/wave/tagionwave.json --keys $NETWORK_FOLDER/wallets < $NETWORK_FOLDER/keys.txt > /tmp/neuewelle_pm2.log 2>&1