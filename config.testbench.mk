
COLLIDER_ROOT?=$(DLOG)/bdd/
BDD_FLAGS+=-p
BDD_FLAGS+=-i$(BDD)/bdd_import.di
BDD_FLAGS+=${addprefix -I,$(BDD)}

BDD_DFLAGS+=${addprefix -I,$(BDD)}

export BDD_LOG=$(DLOG)/bdd/$(TEST_STAGE)/
export BDD_RESULTS=$(BDD_LOG)/results/

BDD_DFILES+=${shell find $(BDD) -name "*.d" -a -not -name "*.gen.d" -a -path "*/testbench/*" -a -not -path "*/unitdata/*" -a -not -path "*/backlog/*" $(NO_WOLFSSL) }
testbench: DFILES+=$(DSRC)/bin-wave/tagion/tools/neuewelle.d
testbench: DFILES+=${shell find $(DSRC)/bin-geldbeutel/ -name "*.d"}

testbench: DINC+=$(DSRC)/bin-wave/

#
# Binary testbench 
#
testbench: bddfiles
target-testbench: ssl nng secp256k1 libp2p
target-testbench: DFLAGS+=$(DVERSION)=ONETOOL
target-testbench: LIBS+=$(SSLIMPLEMENTATION) $(LIBSECP256K1) $(LIBP2PGOWRAPPER) $(LIBNNG)
target-testbench: DFLAGS+=$(DEBUG_FLAGS)

${call DO_BIN,testbench,$(LIB_DFILES) $(BDD_DFILES)}
