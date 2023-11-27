#!/usr/bin/env bash
#
# Runs operational tests
#
set -ex

HOST=x86_64-linux
BIN_DIR=$(realpath -m ./build/$HOST/bin)
TMP_DIR=$(mktemp -d /tmp/tagion_opsXXXX)

$BIN_DIR/tagion -s

# This file is copied over by the ci flow, if you're running this in the source repo then you need to copy it over as well
$BIN_DIR/create_wallets.sh -b $BIN_DIR -k $TMP_DIR/net -t $TMP_DIR/wallets -u $TMP_DIR/net/keys

$BIN_DIR/tagion wave $TMP_DIR/net/tagionwave.json --keys $TMP_DIR/wallets < $TMP_DIR/net/keys > $TMP_DIR/net/wave.log &

echo "waiting for network to start!"
sleep 20;

WAVE_PID=$!

$BIN_DIR/bddenv.sh $BIN_DIR/testbench operational --sendkernel -w $TMP_DIR/wallets

kill -s SIGINT $WAVE_PID
wait $WAVE_PID

echo "data files in $TMP_DIR"
