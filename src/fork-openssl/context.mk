DSRC_OPENSSL := ${call dir.resolve, openssl}
DTMP_OPENSSL := $(DTMP)/openssl

DPREFIX_OPENSSL := $(DTMP_OPENSSL)/install-lib
DEXTRA_OPENSSL := $(DTMP_OPENSSL)/install-extra

CONFIGUREFLAGS_OPENSSL += -static
CONFIGUREFLAGS_OPENSSL += --prefix=$(DPREFIX_OPENSSL)
CONFIGUREFLAGS_OPENSSL += --openssldir=$(DEXTRA_OPENSSL)

include ${call dir.resolve, cross.mk}

LIBOPENSSL+=$(DTMP_OPENSSL)/libssl.a
LIBOPENSSL+=$(DTMP_OPENSSL)/libcrypto.a

ifdef USE_SYSTEM_LIBS
LD_OPENSSL+=${shell pkg-config --libs openssl}
else
LD_OPENSSL+=$(LIBOPENSSL)
endif

ifndef WOLFSSL
LD_SSL:=$(LD_OPENSSL)
endif

ifdef USE_SYSTEM_LIBS
openssl: # NOTHING TO BUILD
else
openssl: $(LIBOPENSSL)
endif

.PHONY: openssl

LIBOPENSSL+=$(DTMP)/libcrypto.a
LIBOPENSSL+=$(DTMP)/libssl.a

proper-openssl:
	$(PRECMD)
	${call log.header, $@ :: openssl}
	$(RM) $(LIBOPENSSL)
	$(RMDIR) $(DTMP_OPENSSL)

OPENSSL_HEAD := $(REPOROOT)/.git/modules/src/wrap-openssl/openssl/HEAD 
OPENSSL_GIT_MODULE := $(DSRC_OPENSSL)/.git

$(OPENSSL_GIT_MODULE):
	git submodule update --init --depth=1 $(DSRC_OPENSSL)

$(OPENSSL_HEAD): $(OPENSSL_GIT_MODULE)
$(DTMP_OPENSSL)/.configured: $(DTMP)/.way $(OPENSSL_HEAD)
	$(PRECMD)
	$(CP) $(DSRC_OPENSSL) $(DTMP_OPENSSL)
	$(CD) $(DTMP_OPENSSL)
	./config $(CONFIGUREFLAGS_OPENSSL)
	$(MAKE) build_generated
	touch $@

$(DTMP_OPENSSL)/libcrypto.a: $(DTMP_OPENSSL)/.configured
	$(PRECMD)
	$(CD) $(DTMP_OPENSSL); $(MAKE) libcrypto.a


$(DTMP_OPENSSL)/libssl.a: $(DTMP_OPENSSL)/.configured
	$(PRECMD)
	$(CD) $(DTMP_OPENSSL); $(MAKE) libssl.a
