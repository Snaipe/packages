# vim: set ft=make:

maintainer ?= $(shell echo "<$$(whoami)@$$(hostname)>")
vendor ?= $(maintainer)
license ?= unknown
category ?= unknown
description ?= no description
homepage ?= http://example.com/no-uri-given

getvar_kind = $(shell if [ -n '$($2_$1)' ]; then echo "$($2_$1)"; else echo "$($1)"; fi)
getvar = $(call getvar_kind,$1,$(BUILD_KIND))

FPM_DEPENDS   = $(shell [ -n '$(call getvar,depends)'   ] && echo '$(call getvar,depends)'   | xargs printf '-d "%s" ')
FPM_PROVIDES  = $(shell [ -n '$(call getvar,provides)'  ] && echo '$(call getvar,provides)'  | xargs printf '--provides "%s" ')
FPM_CONFLICTS = $(shell [ -n '$(call getvar,conflicts)' ] && echo '$(call getvar,conflicts)' | xargs printf '--conflicts "%s" ')
FPM_REPLACES  = $(shell [ -n '$(call getvar,replaces)'  ] && echo '$(call getvar,replaces)'  | xargs printf '--replaces "%s" ')

bin_files ?= usr/bin usr/lib
dev_files ?= usr/include
doc_files ?= usr/share/man

bin_name ?= $(name)
dev_name ?= $(name)-dev
doc_name ?= $(name)-doc

configure ?= --prefix=/usr
md5sum    ?= SKIP

FPM_NAME        = $(call getvar,name)
FPM_VERSION     = $(call getvar,version)
FPM_MAINTAINER  = $(call getvar,maintainer)
FPM_VENDOR      = $(call getvar,vendor)
FPM_MAINTAINER  = $(call getvar,maintainer)
FPM_DESCRIPTION = $(call getvar,description)
FPM_LICENSE     = $(call getvar,license)
FPM_CATEGORY    = $(call getvar,category)
FPM_HOMEPAGE    = $(call getvar,homepage)

ARCHIVE_NAME = $(notdir $(call getvar,source))
WORKDIR = pkg
ARCHIVE_PATH = $(WORKDIR)/$(ARCHIVE_NAME)

ARCHIVEDIR   = $(WORKDIR)/$(name)-$(version)
BASEDIR      = $(ARCHIVEDIR)_$(BUILD_ARCH)_$(BUILD_TARGET)
SRCDIR       = $(BASEDIR)_src
INSTALLDIR   = $(BASEDIR)_install

CONFIG_STATUS  = $(SRCDIR)/config.status
CONFIGURE_FILE = $(abspath $(ARCHIVEDIR)/configure)

targetof     = $(shell echo "$1" | cut -d/ -f1)
archof       = $(shell echo "$1" | cut -d/ -f2)
kindof       = $(shell echo "$1" | cut -d/ -f3)
basedirof    = $(ARCHIVEDIR)_$2_$1
installdirof = $(addsuffix _install,$1)
srcdirof     = $(addsuffix _src,$1)
configof     = $(addsuffix _src/config.status,$1)
outputof     = $(call getvar_kind,name,$3)-$(version)_$2.$1

extension    = $(shell echo "$(suffix $1)" | cut -c2-)

BUILD_MATRIX_DEF = $(foreach X,$(targets),$(foreach Y,$(archs),$X/$Y))
BUILD_MATRIX_BIN = $(addsuffix /bin,$(BUILD_MATRIX_DEF))
BUILD_MATRIX_DEV = $(addsuffix /dev,$(BUILD_MATRIX_DEF))
BUILD_MATRIX_DOC = $(addsuffix /doc,$(BUILD_MATRIX_DEF))

BUILD_MATRIX = $(BUILD_MATRIX_BIN) $(BUILD_MATRIX_DEV) $(BUILD_MATRIX_DOC)
BUILD_MATRIX_LOCAL = $(addsuffix -local,$(BUILD_MATRIX))

matrix_files = $(foreach X,$(targets),$(foreach Y,$(archs),$(call outputof,$X,$Y,$1)))
BUILD_MATRIX_FILES_BIN = $(call matrix_files,bin)
BUILD_MATRIX_FILES_DEV = $(call matrix_files,dev)
BUILD_MATRIX_FILES_DOC = $(call matrix_files,doc)
BUILD_MATRIX_FILES = $(BUILD_MATRIX_FILES_BIN) $(BUILD_MATRIX_FILES_DEV) $(BUILD_MATRIX_FILES_DOC)

BUILD_MATRIX_BASEDIRS = $(foreach X,$(targets),$(foreach Y,$(archs),$(call basedirof,$X,$Y)))
BUILD_MATRIX_SRCDIRS = $(call srcdirof,$(BUILD_MATRIX_BASEDIRS))
BUILD_MATRIX_INSTALLDIRS = $(call installdirof,$(BUILD_MATRIX_BASEDIRS))
BUILD_MATRIX_CONFIGS = $(call configof,$(BUILD_MATRIX_BASEDIRS))

all: $(BUILD_MATRIX)

$(ARCHIVE_PATH):
	curl --create-dirs -Lo $(ARCHIVE_PATH) $(source)

$(ARCHIVEDIR):
	mkdir -p $(ARCHIVEDIR)

$(ARCHIVE_PATH).extracted: $(ARCHIVE_PATH).validated $(ARCHIVEDIR)
	tar -xzf $(ARCHIVE_PATH) -C $(ARCHIVEDIR) --strip 1
	@touch $(ARCHIVE_PATH).extracted

$(ARCHIVE_PATH).validated: $(ARCHIVE_PATH)
	[ "$(md5sum)" = "SKIP" ] || [ "$(md5sum)" = "$(shell md5sum $(ARCHIVE_PATH))" ]
	@touch $(ARCHIVE_PATH).validated

$(BUILD_MATRIX): BUILD_TARGET=$(call targetof,$@)
$(BUILD_MATRIX): BUILD_ARCH=$(call archof,$@)
$(BUILD_MATRIX): BUILD_KIND=$(call kindof,$@)
$(BUILD_MATRIX_LOCAL): BUILD_TARGET=$(call targetof,$@)
$(BUILD_MATRIX_LOCAL): BUILD_ARCH=$(call archof,$@)
$(BUILD_MATRIX_LOCAL): BUILD_KIND=$(call kindof,$@)

$(addsuffix .installed,$(BUILD_MATRIX_INSTALLDIRS)): %_install.installed: %_src
	(cd $^; $(MAKE) DESTDIR=$(abspath $(INSTALLDIR)) install)
	@touch $@

$(CONFIGURE_FILE):
	(cd $(ARCHIVEDIR); ./autogen.sh)

$(BUILD_MATRIX_CONFIGS): $(ARCHIVE_PATH).extracted $(CONFIGURE_FILE)
	mkdir -p $(dir $@) && cd $(dir $@) && $(CONFIGURE_FILE) $(configure)

$(BUILD_MATRIX_SRCDIRS): %: %/config.status
	cd $@ && $(MAKE)

$(BUILD_MATRIX_FILES_BIN): PKG_DIRECTORIES=$(bin_files)
$(BUILD_MATRIX_FILES_DEV): PKG_DIRECTORIES=$(dev_files)
$(BUILD_MATRIX_FILES_DOC): PKG_DIRECTORIES=$(doc_files)

$(BUILD_MATRIX_FILES): $(INSTALLDIR).installed
	fpm \
		-f \
		-n $(FPM_NAME) \
		-v $(FPM_VERSION) \
		$(FPM_DEPENDS) \
		$(FPM_PROVIDES) \
		$(FPM_CONFLICTS) \
		$(FPM_REPLACES) \
		--url "$(FPM_HOMEPAGE)" \
		--description "$(FPM_DESCRIPTION)" \
		--vendor "$(FPM_VENDOR)" \
		--license "$(FPM_LICENSE)" \
		--category "$(FPM_CATEGORY)" \
		-m "$(FPM_MAINTAINER)" \
		-a $(BUILD_ARCH) \
		-s dir -t $(BUILD_TARGET) \
		-p NAME-VERSION_$(BUILD_ARCH).$(BUILD_TARGET) \
		-C $(INSTALLDIR) $(PKG_DIRECTORIES)

$(BUILD_MATRIX_DEF): %: $(addprefix %/,$(kinds))

$(BUILD_MATRIX): %: %-local
	@$(MAKE) \
		BUILD_TARGET=$(BUILD_TARGET) \
		BUILD_ARCH=$(BUILD_ARCH) \
		BUILD_KIND=$(BUILD_KIND) \
		$(call outputof,$(BUILD_TARGET),$(BUILD_ARCH),$(BUILD_KIND))

clean:
	$(RM) -r $(WORKDIR)

distclean:
	$(RM) $(BUILD_MATRIX_FILES)

.PHONY: $(BUILD_MATRIX) $(BUILD_MATRIX_LOCAL) clean distclean
