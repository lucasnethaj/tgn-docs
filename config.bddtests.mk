
TESTMAIN?=testbench

# BDDS+=ssl_echo_server
# BDDS+=ssl_server
# BDDS+=transaction
# BDDS+=transaction_mode_zero
# BDDS+=receive_epoch
BDDS+=dart_test

run-ssl_echo_server: sslextras

run-ssl_server: sslextras
run-ssl_server: RUNFLAGS+=$(BDD)/tagion/testbench/network/tagionwave.json


include $(BDD)/context.mk




