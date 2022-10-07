

bddtest: bddexec bddfiles 

.PHONY: bddtest bddfiles

bddfiles: behaviour
	$(PRECMD)
	echo $(BEHAVIOUR) $(BDD_FLAGS)
	$(BEHAVIOUR) $(BDD_FLAGS)

bddexec:
	$(PRECMD)
	echo "WARRING!!! Not impemented yet"

.PHONY: bddexec

env-bdd:
	$(PRECMD)
	${call log.header, $@ :: env}
	${call log.env, BDD_FLAGS, $(BDD_FLAGS)}
	${call log.close}

.PHONY: env-bdd

env: env-bdd

help-bdd:
	$(PRECMD)
	${call log.header, $@ :: help}
	${call log.help, "make help-bdd", "Will display this part"}
	${call log.help, "make bddtest", "Builds and executes all BDD's"}
	${call log.help, "make bddexec", "Compiles and links all the BDD executables"}
	${call log.help, "make bddreport", "Produce visualization of the BDD-reports"}
	${call log.help, "make bddfiles", "Generated the bdd files"}
	${call log.help, "make behaviour", "Builds the BDD tool"}
	${call log.help, "make clean-bddtest", "Will remove the bdd log files"}
	${call log.close}

.PHONY: help-bdd

help: help-bdd

clean-bddtest:
	$(PRECMD)
	echo "WARNING!! Not implemented yet"

.PHONY: help-bdd

clean: clean-bddtest


