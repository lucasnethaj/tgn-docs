#openssl
#LIBOPENSSL
DSRC_WOLFSSL := ${call dir.resolve, wolfssl}
DTMP_WOLFSSL := $(DTMP)/wolfssl

CONFIGUREFLAGS_WOLFSSL := --enable-static

.PHONY: wolfssl

LIBWOLFSSL := $(DTMP_WOLFSSL)/src/.libs/libwolfssl.a

proper-wolfssl:
	$(PRECMD)
	${call log.header, $@ :: wolfssl}
	$(RMDIR) $(DTMP_WOLFSSL)

proper: proper-wolfssl

wolfss: $(LIBWOLFSSL)

$(LIBWOLFSSL): $(DTMP)/.way
	$(PRECMD)
	${call log.kvp, $@}
	$(CP) $(DSRC_WOLFSSL) $(DTMP_WOLFSSL)
	$(PRECMD)cd $(DTMP_WOLFSSL); sh autogen.sh
	$(PRECMD)cd $(DTMP_WOLFSSL); ./configure $(CONFIGUREFLAGS_WOLFSSL)
	$(PRECMD)cd $(DTMP_WOLFSSL); make

env-wolfssl:
	$(PRECMD)
	${call log.header, $@ :: env}
	${call log.env, CONFIGUREFLAGS_WOLFSSL, $(CONFIGUREFLAGS_WOLFSSL)}
	${call log.kvp, LIBSECP256K1, $(LIBSECP256K1)}
	${call log.kvp, DTMP_WOLFSSL, $(DTMP_WOLFSSL)}
	${call log.kvp, DSRC_WOLFSSL, $(DSRC_WOLFSSL)}
	${call log.close}

.PHONY: env-wolfssl

env: env-wolfssl

help-wolfssl:
	$(PRECMD)
	${call log.header, $@ :: help}
	${call log.help, "make proper-wolfssl", "Remove the wolfssl build"}
	${call log.help, "make env-wolfssl", "Display environment for the wolfbuild"}
	${call log.close}