# -*- mode: Makefile; -*-

#-------------------------------------------------------------------------------
# 2015-08-14
#-------------------------------------------------------------------------------
SHELL=/bin/bash
BASE_DIR := $(subst /build,,$(CURDIR))
OMI_ROOT := $(shell cd ../../omi/Unix; pwd -P)
OMI_KITS := $(shell cd ../../omi-kits; pwd -P)
SCX_CORE_KITS := $(shell cd ../../scxcore-kits; pwd -P)
PAL_DIR := $(shell cd ../../pal; pwd -P)
DSC_DIR := $(shell cd ../../dsc; pwd -P)
AUOMS_DIR := $(shell cd ../../auoms; pwd -P)
AUOMS_KITS_DIR := $(shell cd ../../auoms-kits; pwd -P)
RUBY_TESTING_TARGET_NAME=test

PF_POSIX := 1
include $(BASE_DIR)/build/config.mak
include $(BASE_DIR)/build/Makefile.version
include $(PAL_DIR)/build/Makefile.pal

ifndef ENABLE_DEBUG
$(error "ENABLE_DEBUG is not set.  Please re-run configure")
endif

DSC_TARGET_DIR := $(DSC_DIR)/release
AUOMS_TARGET_DIR := $(AUOMS_DIR)/target/$(BUILD_CONFIGURATION)
AUOMS_KITS_RELEASE_DIR := $(AUOMS_KITS_DIR)/release/2.1.1-0
AUOMS_KITS_RELEASE_1_3_DIR := $(AUOMS_KITS_DIR)/release/1.3.0-3

RUBY_DIR := $(BASE_DIR)/source/ext/ruby
# This Ruby version number refers only to the major/minor version (not teeny)
#      of the Ruby installed with the OMSAgent
RUBY_VER := $(RUBY_VERSION_MAJOR_MINOR)
FLUENTD_DIR := $(BASE_DIR)/source/ext/fluentd
JEMALLOC_DIR := $(BASE_DIR)/source/ext/jemalloc
PLUGINS_DIR := $(BASE_DIR)/source/code/plugins

INTERMEDIATE_DIR=$(BASE_DIR)/intermediate/$(BUILD_CONFIGURATION)
TARGET_DIR := $(BASE_DIR)/target/$(BUILD_CONFIGURATION)

SEPOLICY_SRC_DIR=$(BASE_DIR)/installer/selinux
SEPOLICY_DIR=$(INTERMEDIATE_DIR)/selinux
SEPOLICY_DIR_EL6=$(INTERMEDIATE_DIR)/selinux.el6

ifeq ($(ULINUX),1)
# Doesn't matter what version of SSL/Ruby we use to compile or link the OMI plugin
RUBY_DEST_DIR := $(INTERMEDIATE_DIR)/100/ruby
OMI_LIBRARY_DIR := $(OMI_ROOT)/output_openssl_1.0.0/lib
else
RUBY_DEST_DIR := $(INTERMEDIATE_DIR)/ruby
OMI_LIBRARY_DIR := $(OMI_ROOT)/output/lib
endif

OMI_LIBRARY_LIB_BASE := $(OMI_LIBRARY_DIR)/libbase.a

# Version of Ruby for test purposes only
RUBY_TESTING_DIR := $(shell echo "$(RUBY_CONFIGURE_QUALS_TESTINS)" | cut -d= -f2)
RUBY_TESTING_EXE := $(RUBY_TESTING_DIR)/bin/ruby
RUBY_TESTING_PLUGIN_DIR := $(RUBY_TESTING_DIR)/../plugin/
# Compiler flags

ifeq ($(ENABLE_DEBUG),1)
DEBUG_FLAGS := -g
endif

# Need to use RUBY_COMPILE_FLAGS when compiling code that uses C Ruby interfaces
# (Note that "-Wshadow -Wredundant-decls" don't work with Ruby v2.4.0)
RUBY_COMPILE_FLAGS := $(DEBUG_FLAGS) -D_REENTRANT -fstack-protector-all -Wall -fno-nonansi-builtins -Woverloaded-virtual -Wformat -Wformat-security -Wcast-align -Wswitch-enum  -Wwrite-strings  -Werror -Wcast-qual -fPIC # -Wshadow -Wredundant-decls
PLUGIN_LINK_LIBRARIES := -Wl,-rpath=/opt/omi/lib -L$(OMI_LIBRARY_DIR) -lrt -pthread -lmi
SHARED_FLAGS := -shared

# Support for installbuilder

STAGING_DIR := $(INTERMEDIATE_DIR)/staging
INSTALLER_TMPDIR := $(INTERMEDIATE_DIR)/installer_tmp

INSTALLER_DATAFILES := base_omsagent.data linux.data ruby.data
INSTALLER_DATAFILES_RPM := $(INSTALLER_DATAFILES) linux_rpm.data
INSTALLER_DATAFILES_DPKG := $(INSTALLER_DATAFILES) linux_dpkg.data

ifeq ($(PACKAGE_SUFFIX),rpm)
INSTALLER_DATAFILES_CURRENT := $(INSTALLER_DATAFILES_RPM)
else
INSTALLER_DATAFILES_CURRENT := $(INSTALLER_DATAFILES_DPKG)
endif

ifeq ("$(wildcard /usr/bin/dpkg-deb)","")
DPKG_LOCATION="--DPKG_LOCATION=$(PAL_DIR)/installer/InstallBuilder/tools/bin/dpkg-deb-$(PF_ARCH)"
else
DPKG_LOCATION=
endif

# Other packaging support

ifeq ($(ULINUX),1)
  ifeq ($(PF_ARCH),x86)
    # OMS OSS directory doesn't include any 32-bit kits, so don't look for *.i686.sh ...
    OMS_OSS_KITS := $(shell cd $(BASE_DIR)/installer/oss-kits; ls *-oss-test.sh)
  else ifeq ($(PF_ARCH),x64)
    OMS_OSS_KITS := $(shell cd $(BASE_DIR)/installer/oss-kits; ls *-oss-test.sh *.x86_64.sh)
  endif
endif

# Plugins
IN_PLUGINS_LIB := $(INTERMEDIATE_DIR)/Libomi.so

OMI_INCLUDES := -I$(OMI_ROOT) -I$(OMI_ROOT)/common -I$(OMI_ROOT)/common/linux -I$(OMI_ROOT)/base -I$(OMI_ROOT)/output/include
PAL_INCLUDES := -I$(PAL_DIR)/source/code/include/util
RUBY_INCLUDES := -I$(RUBY_DEST_DIR)/include/ruby-$(RUBY_VER)/$(RUBY_ARCM) -I$(RUBY_DEST_DIR)/include/ruby-$(RUBY_VER)

ifeq ($(ULINUX),1)
  OUTPUT_PACKAGE_PREFIX=omsagent-$(OMS_BUILDVERSION_MAJOR).$(OMS_BUILDVERSION_MINOR).$(OMS_BUILDVERSION_PATCH)-$(OMS_BUILDVERSION_BUILDNR).universal.$(PF_ARCH)
  OUTPUT_PACKAGE_PREFIX_RPM=omsagent-$(OMS_BUILDVERSION_MAJOR).$(OMS_BUILDVERSION_MINOR).$(OMS_BUILDVERSION_PATCH)-$(OMS_BUILDVERSION_BUILDNR).universal.rpm.$(PF_ARCH)
  OUTPUT_PACKAGE_PREFIX_DEB=omsagent-$(OMS_BUILDVERSION_MAJOR).$(OMS_BUILDVERSION_MINOR).$(OMS_BUILDVERSION_PATCH)-$(OMS_BUILDVERSION_BUILDNR).universal.deb.$(PF_ARCH)
else
  PF_DISTRO_LC := $(shell echo $(PF_DISTRO) | tr A-Z a-z)
  OUTPUT_PACKAGE_PREFIX=omsagent-$(OMS_BUILDVERSION_MAJOR).$(OMS_BUILDVERSION_MINOR).$(OMS_BUILDVERSION_PATCH)-$(OMS_BUILDVERSION_BUILDNR).$(PF_DISTRO_LC).$(PF_MAJOR).$(PF_ARCH)
endif

# Test
SYSTEST_CONFIG := $(BASE_DIR)/test/config/systest.conf

#--------------------------------------------------------------------------------
# Build targets
.PHONY: all clean clean-ruby distclean clean-status kit
.PHONY: tests test omstest unittest systemtest systemtestrb

all : $(OMI_LIBRARY_LIB_BASE) $(DSC_TARGET_DIR) $(RUBY_DEST_DIR) $(IN_PLUGINS_LIB) sepolicy kit
        # After a successful make, undo the Ruby patches for sequential builds from old branches
	@echo "Cleaning patched Ruby files..."
	cd $(BASE_DIR)/source/ext/ruby; git clean -dfx; git reset --hard

compile_only : $(OMI_LIBRARY_LIB_BASE) $(DSC_TARGET_DIR) $(RUBY_DEST_DIR) $(IN_PLUGINS_LIB) sepolicy

compile_dsc_only : $(OMI_LIBRARY_LIB_BASE) $(DSC_TARGET_DIR)

sepolicy : $(SEPOLICY_DIR_EL6)/omsagent-logrotate.pp $(SEPOLICY_DIR)/omsagent-logrotate.pp

clean : clean-status
	$(RMDIR) $(INTERMEDIATE_DIR)/source/code

	# On Debian, installer staging directory has root permissions, so sudo elevate
	sudo $(RMDIR) $(STAGING_DIR) $(INSTALLER_TMPDIR) $(BASE_DIR)/target

	# Until we can build Ruby under installation dir, clean it here
	sudo $(RMDIR) $(RUBY_TEST_DIRECTORY)

	$(RM) $(IN_PLUGINS_LIB)
	-find $(BASE_DIR) -name \*~ -exec rm {} \;

clean-ruby : clean
	sudo $(RMDIR) $(BASE_DIR)/intermediate
	sudo $(RMDIR) $(RUBY_DIR)/.ext
	#
	# Warning: This step will clean out checked out files from Ruby directory
	#
	@echo "Cleaning RUBY source directory ..."
	cd $(RUBY_DIR); git clean -dfx; git reset --hard
	#
	# Warning: This step will clean out checked out files from fluentd directory
	#
	@echo "Cleaning fluentd source directory ..."
	cd $(FLUENTD_DIR); git clean -dfx; git reset --hard
	@echo "Cleaning jemalloc source directory ..."
	cd $(JEMALLOC_DIR); git clean -dfx; git reset --hard

clean-dsc : clean
	-make -C $(DSC_DIR) clean
	-$(RMDIR) $(DSC_DIR)/config.mak $(DSC_DIR)/intermediate $(DSC_DIR)/output $(DSC_DIR)/release
	-$(RM) $(DSC_DIR)/omi-1.0.8

distclean : clean clean-ruby clean-dsc
	-$(RMDIR) $(OMI_ROOT)/output*

	# reset all submodules
	cd $(BASE_DIR); git submodule foreach --recursive git reset --hard
	cd $(BASE_DIR); git submodule foreach --recursive git clean -fdx

	-$(RM) $(BASE_DIR)/build/Makefile.version
	-$(RM) $(BASE_DIR)/build/config.mak
	-$(RM) $(PAL_DIR)/build/config.mak

clean-status :
	@$(ECHO) "========================= Performing make clean"

#--------------------------------------------------------------------------------
# Build OMI project (configured for the OMS project)

$(OMI_LIBRARY_LIB_BASE) :
	@$(ECHO) "========================= Performing Building OMI Project"
ifeq ($(ULINUX),1)
	cd $(OMI_ROOT); ./configure --enable-microsoft --enable-ulinux
else
	cd $(OMI_ROOT); ./configure --enable-microsoft
endif
	$(MAKE) -C $(OMI_ROOT) all

#--------------------------------------------------------------------------------
# Build DSC project (configured for the OMS project)
#
# Note: This expects that OMI is already built! Take care of your
# ordering on the 'all' target!

$(DSC_TARGET_DIR) : $(OMI_LIBRARY_LIB_BASE)
ifeq ($(ULINUX),1)
	@$(ECHO) "========================= Performing Building DSC Project"
	cd $(DSC_DIR); ./configure --oms
	ln -fs $(OMI_ROOT) $(DSC_DIR)/omi-1.0.8
	cd $(OMI_ROOT); $(RMDIR) output; ln -s output_openssl_1.0.0 output
	$(MAKE) -C $(DSC_DIR) dsc100
	$(MAKE) -C $(DSC_DIR) dsckit100
ifeq ($(PF_ARCH),x64)
	cd $(OMI_ROOT); $(RMDIR) output; ln -s output_openssl_1.1.0 output
	$(MAKE) -C $(DSC_DIR) dsc110
	$(MAKE) -C $(DSC_DIR) dsckit110
endif
	cd $(OMI_ROOT); $(RMDIR) output
endif

#--------------------------------------------------------------------------------
# Build SELinux policy modules for omsagent-logrotate

ifeq ($(ULINUX),1)
$(SEPOLICY_DIR_EL6)/omsagent-logrotate.pp : $(SEPOLICY_SRC_DIR)/omsagent-logrotate.el6.te $(SEPOLICY_SRC_DIR)/omsagent-logrotate.fc
	@echo "========================= Building EL6 selinux policy module for omsagent-logrotate"
	$(MKPATH) $(SEPOLICY_DIR_EL6)
	$(COPY) $(SEPOLICY_SRC_DIR)/omsagent-logrotate.el6.te $(SEPOLICY_DIR_EL6)/omsagent-logrotate.te
	$(COPY) $(SEPOLICY_SRC_DIR)/omsagent-logrotate.fc $(SEPOLICY_DIR_EL6)
	cd $(SEPOLICY_DIR_EL6); make -f /usr/share/selinux/devel/Makefile

$(SEPOLICY_DIR)/omsagent-logrotate.pp : $(SEPOLICY_SRC_DIR)/omsagent-logrotate.te $(SEPOLICY_SRC_DIR)/omsagent-logrotate.fc
	@echo "========================= Building selinux policy module for omsagent-logrotate"
	$(MKPATH) $(SEPOLICY_DIR)
	$(COPY) $(SEPOLICY_SRC_DIR)/omsagent-logrotate.te $(SEPOLICY_SRC_DIR)/omsagent-logrotate.fc $(SEPOLICY_DIR)
	cd $(SEPOLICY_DIR); make -f /usr/share/selinux/devel/Makefile
else
$(SEPOLICY_DIR_EL6)/omsagent-logrotate.pp : $(SEPOLICY_SRC_DIR)/omsagent-logrotate.el6.te $(SEPOLICY_SRC_DIR)/omsagent-logrotate.fc
	@echo "========================= Building EL6 selinux policy module"
	$(MKPATH) $(SEPOLICY_DIR_EL6)
	touch $(SEPOLICY_DIR_EL6)/omsagent-logrotate.pp

$(SEPOLICY_DIR)/omsagent-logrotate.pp : $(SEPOLICY_SRC_DIR)/omsagent-logrotate.te $(SEPOLICY_SRC_DIR)/omsagent-logrotate.fc
	@echo "========================= Building selinux policy module"
	$(MKPATH) $(SEPOLICY_DIR)
	touch $(SEPOLICY_DIR)/omsagent-logrotate.pp
endif

#--------------------------------------------------------------------------------
# Build the version of Ruby that we test with
$(RUBY_TESTING_DIR) :
	#
	# Warning: This step will clean out checked out files from both Ruby and fluentd directories
	#
	@$(ECHO) "========================= Performing Building Ruby for testing: '${RUBY_TESTING_TARGET_NAME}'"
	# $(MKPATH) $(INTERMEDIATE_DIR)
	$(BASE_DIR)/build/buildRuby.sh ${RUBY_TESTING_TARGET_NAME}

# Build the version of Ruby that we distribute

$(RUBY_DEST_DIR) :
	#
	# Warning: This step will clean out checked out files from both Ruby and fluentd directories
	#
ifeq ($(ULINUX),1)
	@$(ECHO) "========================= Performing Building Ruby for SSL v1.0.0 ..."
	$(BASE_DIR)/build/buildRuby.sh 100
ifeq ($(PF_ARCH),x64)
	@$(ECHO) "========================= Performing Building Ruby for SSL v1.1.0 ..."
	$(BASE_DIR)/build/buildRuby.sh 110
endif
else
	@$(ECHO) "========================= Performing Building Ruby"
	$(BASE_DIR)/build/buildRuby.sh
endif

#================================================================================
# Internal functions
#================================================================================

# Convert a list of src files with absolute paths under BASE_DIR to corresponding
# object files under intermediate directory
# src_to_obj(list_of_cppfiles)
src_to_obj = $(patsubst $(BASE_DIR)%, $(INTERMEDIATE_DIR)%, $(patsubst %.c, %.o, $(patsubst %.cpp, %.o, $(1))))

# No default rules, please
.SUFFIX:

# Rule for compiling cpp files in source tree, ouptut in mirrored intermediate dir
$(INTERMEDIATE_DIR)/%.o : $(BASE_DIR)/%.cpp
	$(MKPATH) $(@D)
	$(CXX) -c $(CXXFLAGS) $(INCLUDES) -I$(<D) -o $@ $<

$(INTERMEDIATE_DIR)/%.o : $(BASE_DIR)/%.c
	$(MKPATH) $(@D)
	$(CXX) -c $(CFLAGS) $(INCLUDES) -I$(<D) -o $@ $<

#--------------------------------------------------------------------------------
# Build the plugins that we require for our agent

STATIC_PLUGINS_SRCFILES = $(PLUGINS_DIR)/omi_interface.cpp
STATIC_PLUGINS_OBJFILES = $(call src_to_obj,$(STATIC_PLUGINS_SRCFILES))

$(IN_PLUGINS_LIB) : CXXFLAGS = $(RUBY_COMPILE_FLAGS)
$(IN_PLUGINS_LIB) : INCLUDES = $(RUBY_INCLUDES) $(OMI_INCLUDES) $(PAL_INCLUDES)
$(IN_PLUGINS_LIB) : $(STATIC_PLUGINS_OBJFILES)
	@echo "========================= Performing Building input plugins"
	$(MKPATH) $(INTERMEDIATE_DIR)
	$(MKPATH) $(TARGET_DIR)
	g++ $(SHARED_FLAGS) $(RUBY_INCLUDES) $(OMI_INCLUDES) $(PAL_INCLUDES) -o $@ $(STATIC_PLUGINS_OBJFILES) $(PLUGIN_LINK_LIBRARIES)

#--------------------------------------------------------------------------------
# Build the distribution kit
#
# Build the packages via installbuilder
#
# While the "formal build" only builds ULINUX, we may build something else for DEV purposes.
# Assume we ALWAYS build RPM, but only build DPKG if --enable-ulinux is speified in configure.

ifeq ($(ULINUX),1)

kit : $(TARGET_DIR)/$(OUTPUT_PACKAGE_PREFIX).sh $(TARGET_DIR)/dsc \
      $(TARGET_DIR)/$(OUTPUT_PACKAGE_PREFIX_RPM).sh $(TARGET_DIR)/$(OUTPUT_PACKAGE_PREFIX_DEB).sh

$(TARGET_DIR)/dsc : $(DSC_TARGET_DIR)
	@echo "========================= Performing Copying DSC resources"
	$(MKPATH) $(TARGET_DIR)/dsc; $(COPY) $(DSC_TARGET_DIR)/*.zip $(TARGET_DIR)/dsc/


$(TARGET_DIR)/$(OUTPUT_PACKAGE_PREFIX).sh : $(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX).tar
	@echo "========================= Performing Building shell bundle"
	../installer/bundle/create_bundle.sh $(TARGET_DIR) $(INTERMEDIATE_DIR) $(OUTPUT_PACKAGE_PREFIX).tar
	@echo "========================= Generating SHA256SUM of shell bundle: $(OUTPUT_PACKAGE_PREFIX).sh"
	cd $(TARGET_DIR)/; sha256sum $(OUTPUT_PACKAGE_PREFIX).sh > $(OUTPUT_PACKAGE_PREFIX).sha256sums
	cd $(BASE_DIR)/build


$(TARGET_DIR)/$(OUTPUT_PACKAGE_PREFIX_RPM).sh : $(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX_RPM).tar
	@echo "========================= Performing Building RPM shell bundle"
	../installer/bundle/create_bundle.sh $(TARGET_DIR) $(INTERMEDIATE_DIR) $(OUTPUT_PACKAGE_PREFIX_RPM).tar "RPM"


$(TARGET_DIR)/$(OUTPUT_PACKAGE_PREFIX_DEB).sh : $(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX_DEB).tar
	@echo "========================= Performing Building DEB shell bundle"
	../installer/bundle/create_bundle.sh $(TARGET_DIR) $(INTERMEDIATE_DIR) $(OUTPUT_PACKAGE_PREFIX_DEB).tar "DPKG"

ifeq ($(PF_ARCH),x64)
$(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX).tar : $(RUBY_DEST_DIR) $(IN_PLUGINS_LIB) \
	$(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).rpm $(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).deb \
	$(INTERMEDIATE_DIR)/110/$(OUTPUT_PACKAGE_PREFIX).rpm $(INTERMEDIATE_DIR)/110/$(OUTPUT_PACKAGE_PREFIX).deb

	@echo "========================= Performing Building .tar file"

	# Gather the DSC bits that we need
	$(RM) $(INTERMEDIATE_DIR)/100/omsconfig-*.{rpm,deb} $(INTERMEDIATE_DIR)/110/omsconfig-*.{rpm,deb}

	cd $(DSC_DIR)/release; $(COPY) `ls omsconfig-*.ssl_100.*.rpm | sort | tail -1` $(INTERMEDIATE_DIR)/100
	cd $(DSC_DIR)/release; $(COPY) `ls omsconfig-*.ssl_100.*.deb | sort | tail -1` $(INTERMEDIATE_DIR)/100
	cd $(INTERMEDIATE_DIR)/100; for f in omsconfig-*.{rpm,deb}; do SOURCE=$$f; DEST=`echo $$SOURCE | sed 's/.ssl_100././'` ; $(MV) $$SOURCE $$DEST; done

	cd $(DSC_DIR)/release; $(COPY) `ls omsconfig-*.ssl_110.*.rpm | sort | tail -1` $(INTERMEDIATE_DIR)/110
	cd $(DSC_DIR)/release; $(COPY) `ls omsconfig-*.ssl_110.*.deb | sort | tail -1` $(INTERMEDIATE_DIR)/110
	cd $(INTERMEDIATE_DIR)/110; for f in omsconfig-*.{rpm,deb}; do SOURCE=$$f; DEST=`echo $$SOURCE | sed 's/.ssl_110././'` ; $(MV) $$SOURCE $$DEST; done

	# Pick up the OSS (Open Source) providers
	$(RMDIR) $(INTERMEDIATE_DIR)/oss-kits
	$(MKPATH) $(INTERMEDIATE_DIR)/oss-kits
	cd $(BASE_DIR)/installer/oss-kits; $(COPY) $(OMS_OSS_KITS) $(INTERMEDIATE_DIR)/oss-kits
	chmod +x $(INTERMEDIATE_DIR)/oss-kits/*.sh

	# Pick up other bundled packages
	$(RMDIR) $(INTERMEDIATE_DIR)/bundles
	$(MKPATH) $(INTERMEDIATE_DIR)/bundles
	cd $(AUOMS_KITS_RELEASE_DIR); $(COPY) `ls auoms-*.universal.$(PF_ARCH).sh | sort | tail -1` $(INTERMEDIATE_DIR)/bundles
	$(COPY) $(AUOMS_KITS_RELEASE_DIR)/auoms-bundle-test.sh $(INTERMEDIATE_DIR)/bundles

	# adding auoms 1.3 for older distros (SLES11)
	$(MKPATH) $(INTERMEDIATE_DIR)/bundles/v1
	cd $(AUOMS_KITS_RELEASE_1_3_DIR); $(COPY) `ls auoms-*.universal.$(PF_ARCH).sh | sort | tail -1` $(INTERMEDIATE_DIR)/bundles/v1
	$(COPY) $(AUOMS_KITS_RELEASE_1_3_DIR)/auoms-bundle-test.sh $(INTERMEDIATE_DIR)/bundles/v1

	# Gather the SCX bits that we need
	# Note: We take care to only copy the latest version if there are multiple versions
	cd $(SCX_CORE_KITS)/release; $(COPY) `ls scx-*.$(PF_ARCH).sh | sort | tail -1` $(INTERMEDIATE_DIR)

	# Extract SCX bundle script
	$(RMDIR) $(INTERMEDIATE_DIR)/scxbundle.*
	cd $(INTERMEDIATE_DIR); $(SHELL) scx-*.sh --extract

	# Gather SCX packages
	cd $(INTERMEDIATE_DIR)/scxbundle.*; $(COPY) 100/scx-*.universal.$(PF_ARCH).{deb,rpm} $(INTERMEDIATE_DIR)/100
	cd $(INTERMEDIATE_DIR)/scxbundle.*; $(COPY) 110/scx-*.universal.$(PF_ARCH).{deb,rpm} $(INTERMEDIATE_DIR)/110

	# Gather apache and mysql cimprov bundle scripts from SCX
	cd $(INTERMEDIATE_DIR)/scxbundle.*; $(COPY) *.sh $(INTERMEDIATE_DIR)/oss-kits

	# Gather OMI packages from omi-kits
	cd $(OMI_KITS); $(COPY) release/omi-*.ssl_100.ulinux.$(PF_ARCH).{deb,rpm} $(INTERMEDIATE_DIR)/100
	cd $(OMI_KITS); $(COPY) release/omi-*.ssl_110.ulinux.$(PF_ARCH).{deb,rpm} $(INTERMEDIATE_DIR)/110

	# Remove ssl_100 and ssl_110 from omi filenames
	cd $(INTERMEDIATE_DIR)/100; mv omi-*.deb `ls omi-*.deb | sed "s/\.ssl_100\./\./g"`
	cd $(INTERMEDIATE_DIR)/100; mv omi-*.rpm `ls omi-*.rpm | sed "s/\.ssl_100\./\./g"`
	cd $(INTERMEDIATE_DIR)/110; mv omi-*.deb `ls omi-*.deb | sed "s/\.ssl_110\./\./g"`
	cd $(INTERMEDIATE_DIR)/110; mv omi-*.rpm `ls omi-*.rpm | sed "s/\.ssl_110\./\./g"`

	chmod +x $(INTERMEDIATE_DIR)/bundles/**/*.sh

	# Build the tar file containing both .rpm and .deb packages
	cd $(INTERMEDIATE_DIR); tar cvf $(OUTPUT_PACKAGE_PREFIX).tar 100/*.{deb,rpm} 110/*.{deb,rpm} oss-kits/* bundles/*

$(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX_RPM).tar : $(RUBY_DEST_DIR) $(IN_PLUGINS_LIB) \
	$(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).rpm $(INTERMEDIATE_DIR)/110/$(OUTPUT_PACKAGE_PREFIX).rpm 

	@echo "========================= Performing Building RPM .tar file"

	# Build the tar file containing .rpm packages
	cd $(INTERMEDIATE_DIR); tar cvf $(OUTPUT_PACKAGE_PREFIX_RPM).tar 100/*.rpm 110/*.rpm oss-kits/*

$(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX_DEB).tar : $(RUBY_DEST_DIR) $(IN_PLUGINS_LIB) \
	$(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).deb $(INTERMEDIATE_DIR)/110/$(OUTPUT_PACKAGE_PREFIX).deb

	@echo "========================= Performing Building DEB .tar file"

	# Build the tar file containing .deb packages
	cd $(INTERMEDIATE_DIR); tar cvf $(OUTPUT_PACKAGE_PREFIX_DEB).tar 100/*.deb 110/*.deb oss-kits/*

else
$(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX).tar : $(RUBY_DEST_DIR) $(IN_PLUGINS_LIB) \
	$(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).rpm $(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).deb

	@echo "========================= Performing Building .tar file"

	# Gather the DSC bits that we need
	$(RM) $(INTERMEDIATE_DIR)/100/omsconfig-*.{rpm,deb}

	cd $(DSC_DIR)/release; $(COPY) `ls omsconfig-*.ssl_100.*.rpm | sort | tail -1` $(INTERMEDIATE_DIR)/100
	cd $(DSC_DIR)/release; $(COPY) `ls omsconfig-*.ssl_100.*.deb | sort | tail -1` $(INTERMEDIATE_DIR)/100
	cd $(INTERMEDIATE_DIR)/100; for f in omsconfig-*.{rpm,deb}; do SOURCE=$$f; DEST=`echo $$SOURCE | sed 's/.ssl_100././'` ; $(MV) $$SOURCE $$DEST; done

	# Pick up the OSS (Open Source) providers
	$(RMDIR) $(INTERMEDIATE_DIR)/oss-kits
	$(MKPATH) $(INTERMEDIATE_DIR)/oss-kits
	cd $(BASE_DIR)/installer/oss-kits; $(COPY) $(OMS_OSS_KITS) $(INTERMEDIATE_DIR)/oss-kits
	chmod +x $(INTERMEDIATE_DIR)/oss-kits/*.sh

	# Pick up other bundled packages
	$(RMDIR) $(INTERMEDIATE_DIR)/bundles
	$(MKPATH) $(INTERMEDIATE_DIR)/bundles
	cd $(AUOMS_KITS_RELEASE_DIR); $(COPY) `ls auoms-*.universal.$(PF_ARCH).sh | sort | tail -1` $(INTERMEDIATE_DIR)/bundles
	$(COPY) $(AUOMS_KITS_RELEASE_DIR)/auoms-bundle-test.sh $(INTERMEDIATE_DIR)/bundles

	# adding auoms 1.3 for older distros (SLES11)
	$(MKPATH) $(INTERMEDIATE_DIR)/bundles/v1
	cd $(AUOMS_KITS_RELEASE_1_3_DIR); $(COPY) `ls auoms-*.universal.$(PF_ARCH).sh | sort | tail -1` $(INTERMEDIATE_DIR)/bundles/v1
	$(COPY) $(AUOMS_KITS_RELEASE_1_3_DIR)/auoms-bundle-test.sh $(INTERMEDIATE_DIR)/bundles/v1

	# Gather the SCX bits that we need
	# Note: We take care to only copy the latest version if there are multiple versions
	cd $(SCX_CORE_KITS)/release; $(COPY) `ls scx-*.$(PF_ARCH).sh | sort | tail -1` $(INTERMEDIATE_DIR)

	# Extract SCX bundle script
	$(RMDIR) $(INTERMEDIATE_DIR)/scxbundle.*
	cd $(INTERMEDIATE_DIR); $(SHELL) scx-*.sh --extract

	# Gather SCX packages
	cd $(INTERMEDIATE_DIR)/scxbundle.*; $(COPY) 100/scx-*.universal.$(PF_ARCH).{deb,rpm} $(INTERMEDIATE_DIR)/100

	# Gather apache and mysql cimprov bundle scripts from SCX
	cd $(INTERMEDIATE_DIR)/scxbundle.*; $(COPY) *.sh $(INTERMEDIATE_DIR)/oss-kits

	# Gather OMI packages from omi-kits
	cd $(OMI_KITS); $(COPY) release/omi-*.ssl_100.ulinux.$(PF_ARCH).{deb,rpm} $(INTERMEDIATE_DIR)/100

	# Remove ssl_100 from omi filenames
	cd $(INTERMEDIATE_DIR)/100; mv omi-*.deb `ls omi-*.deb | sed "s/\.ssl_100\./\./g"`
	cd $(INTERMEDIATE_DIR)/100; mv omi-*.rpm `ls omi-*.rpm | sed "s/\.ssl_100\./\./g"`

	chmod +x $(INTERMEDIATE_DIR)/bundles/**/*.sh

	# Build the tar file containing both .rpm and .deb packages
	cd $(INTERMEDIATE_DIR); tar cvf $(OUTPUT_PACKAGE_PREFIX).tar 100/*.{deb,rpm} oss-kits/* bundles/*

$(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX_RPM).tar : $(RUBY_DEST_DIR) $(IN_PLUGINS_LIB) \
	$(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).rpm 

	@echo "========================= Performing Building RPM .tar file"

	# Build the tar file containing .rpm packages
	cd $(INTERMEDIATE_DIR); tar cvf $(OUTPUT_PACKAGE_PREFIX_RPM).tar 100/*.rpm oss-kits/*

$(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX_DEB).tar : $(RUBY_DEST_DIR) $(IN_PLUGINS_LIB) \
	$(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).deb

	@echo "========================= Performing Building DEB .tar file"

	# Build the tar file containing .deb packages
	cd $(INTERMEDIATE_DIR); tar cvf $(OUTPUT_PACKAGE_PREFIX_DEB).tar 100/*.deb oss-kits/*
endif

$(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).rpm:
	@echo "========================= Performing Building RPM package (SSL 1.0)"
	$(MKPATH) $(INSTALLER_TMPDIR)
	$(MKPATH) $(INTERMEDIATE_DIR)/100

	sudo $(RMDIR) $(STAGING_DIR)
	python $(PAL_DIR)/installer/InstallBuilder/installbuilder.py \
		--BASE_DIR=$(BASE_DIR) \
		--TARGET_DIR=$(INTERMEDIATE_DIR) \
		--INTERMEDIATE_DIR=$(INSTALLER_TMPDIR) \
		--STAGING_DIR=$(STAGING_DIR) \
		--BUILD_TYPE=$(BUILD_TYPE) \
		--BUILD_CONFIGURATION=$(BUILD_CONFIGURATION) \
		--RUBY_INT=intermediate/$(BUILD_CONFIGURATION)/100/ruby \
		--RUBY_ARCH=$(RUBY_ARCH) \
		--RUBY_ARCM=$(RUBY_ARCM) \
		--PFARCH=$(PF_ARCH) \
		--PFDISTRO=$(PF_DISTRO) \
		--PFMAJOR=$(PF_MAJOR) \
		--PFMINOR=$(PF_MINOR) \
		--VERSION=$(OMS_BUILDVERSION_MAJOR).$(OMS_BUILDVERSION_MINOR).$(OMS_BUILDVERSION_PATCH) \
		--RELEASE=$(OMS_BUILDVERSION_BUILDNR) \
		--VERSION_IDENT="$(OMS_BUILDVERSION_DATE) $(OMS_BUILDVERSION_STATUS)" \
		--DATAFILE_PATH=$(BASE_DIR)/installer/datafiles \
		--OUTPUTFILE=$(OUTPUT_PACKAGE_PREFIX) \
		$(INSTALLER_DATAFILES_RPM)
	mv $(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX).rpm $(INTERMEDIATE_DIR)/100

$(INTERMEDIATE_DIR)/100/$(OUTPUT_PACKAGE_PREFIX).deb:
	@echo "========================= Performing Building DEB package (SSL 1.0)"
	$(MKPATH) $(INSTALLER_TMPDIR)
	$(MKPATH) $(INTERMEDIATE_DIR)/100

	sudo $(RMDIR) $(STAGING_DIR)
	python $(PAL_DIR)/installer/InstallBuilder/installbuilder.py \
		--BASE_DIR=$(BASE_DIR) \
		--TARGET_DIR=$(INTERMEDIATE_DIR) \
		--INTERMEDIATE_DIR=$(INSTALLER_TMPDIR) \
		--STAGING_DIR=$(STAGING_DIR) \
		--BUILD_TYPE=$(BUILD_TYPE) \
		--BUILD_CONFIGURATION=$(BUILD_CONFIGURATION) \
		--RUBY_INT=intermediate/$(BUILD_CONFIGURATION)/100/ruby \
		--RUBY_ARCH=$(RUBY_ARCH) \
		--RUBY_ARCM=$(RUBY_ARCM) \
		--PFARCH=$(PF_ARCH) \
		--PFDISTRO=$(PF_DISTRO) \
		--PFMAJOR=$(PF_MAJOR) \
		--PFMINOR=$(PF_MINOR) \
		--VERSION=$(OMS_BUILDVERSION_MAJOR).$(OMS_BUILDVERSION_MINOR).$(OMS_BUILDVERSION_PATCH) \
		--RELEASE=$(OMS_BUILDVERSION_BUILDNR) \
		--VERSION_IDENT="$(OMS_BUILDVERSION_DATE) $(OMS_BUILDVERSION_STATUS)" \
		$(DPKG_LOCATION) \
		--DATAFILE_PATH=$(BASE_DIR)/installer/datafiles \
		--OUTPUTFILE=$(OUTPUT_PACKAGE_PREFIX) \
		$(INSTALLER_DATAFILES_DPKG)
	mv $(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX).deb $(INTERMEDIATE_DIR)/100

ifeq ($(PF_ARCH),x64)
$(INTERMEDIATE_DIR)/110/$(OUTPUT_PACKAGE_PREFIX).rpm:
	@echo "========================= Performing Building RPM package (SSL 1.1)"
	$(MKPATH) $(INSTALLER_TMPDIR)
	$(MKPATH) $(INTERMEDIATE_DIR)/110

	sudo $(RMDIR) $(STAGING_DIR)
	python $(PAL_DIR)/installer/InstallBuilder/installbuilder.py \
		--BASE_DIR=$(BASE_DIR) \
		--TARGET_DIR=$(INTERMEDIATE_DIR) \
		--INTERMEDIATE_DIR=$(INSTALLER_TMPDIR) \
		--STAGING_DIR=$(STAGING_DIR) \
		--BUILD_TYPE=$(BUILD_TYPE) \
		--BUILD_CONFIGURATION=$(BUILD_CONFIGURATION) \
		--RUBY_INT=intermediate/$(BUILD_CONFIGURATION)/110/ruby \
		--RUBY_ARCH=$(RUBY_ARCH) \
		--RUBY_ARCM=$(RUBY_ARCM) \
		--PFARCH=$(PF_ARCH) \
		--PFDISTRO=$(PF_DISTRO) \
		--PFMAJOR=$(PF_MAJOR) \
		--PFMINOR=$(PF_MINOR) \
		--VERSION=$(OMS_BUILDVERSION_MAJOR).$(OMS_BUILDVERSION_MINOR).$(OMS_BUILDVERSION_PATCH) \
		--RELEASE=$(OMS_BUILDVERSION_BUILDNR) \
		--VERSION_IDENT="$(OMS_BUILDVERSION_DATE) $(OMS_BUILDVERSION_STATUS)" \
		--DATAFILE_PATH=$(BASE_DIR)/installer/datafiles \
		--OUTPUTFILE=$(OUTPUT_PACKAGE_PREFIX) \
		$(INSTALLER_DATAFILES_RPM)
	mv $(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX).rpm $(INTERMEDIATE_DIR)/110

$(INTERMEDIATE_DIR)/110/$(OUTPUT_PACKAGE_PREFIX).deb:
	@echo "========================= Performing Building DEB package (SSL 1.1)"
	$(MKPATH) $(INSTALLER_TMPDIR)
	$(MKPATH) $(INTERMEDIATE_DIR)/110

	sudo $(RMDIR) $(STAGING_DIR)
	python $(PAL_DIR)/installer/InstallBuilder/installbuilder.py \
		--BASE_DIR=$(BASE_DIR) \
		--TARGET_DIR=$(INTERMEDIATE_DIR) \
		--INTERMEDIATE_DIR=$(INSTALLER_TMPDIR) \
		--STAGING_DIR=$(STAGING_DIR) \
		--BUILD_TYPE=$(BUILD_TYPE) \
		--BUILD_CONFIGURATION=$(BUILD_CONFIGURATION) \
		--RUBY_INT=intermediate/$(BUILD_CONFIGURATION)/110/ruby \
		--RUBY_ARCH=$(RUBY_ARCH) \
		--RUBY_ARCM=$(RUBY_ARCM) \
		--PFARCH=$(PF_ARCH) \
		--PFDISTRO=$(PF_DISTRO) \
		--PFMAJOR=$(PF_MAJOR) \
		--PFMINOR=$(PF_MINOR) \
		--VERSION=$(OMS_BUILDVERSION_MAJOR).$(OMS_BUILDVERSION_MINOR).$(OMS_BUILDVERSION_PATCH) \
		--RELEASE=$(OMS_BUILDVERSION_BUILDNR) \
		--VERSION_IDENT="$(OMS_BUILDVERSION_DATE) $(OMS_BUILDVERSION_STATUS)" \
		$(DPKG_LOCATION) \
		--DATAFILE_PATH=$(BASE_DIR)/installer/datafiles \
		--OUTPUTFILE=$(OUTPUT_PACKAGE_PREFIX) \
		$(INSTALLER_DATAFILES_DPKG)
	mv $(INTERMEDIATE_DIR)/$(OUTPUT_PACKAGE_PREFIX).deb $(INTERMEDIATE_DIR)/110
endif
else

kit : $(TARGET_DIR)/$(OUTPUT_PACKAGE_PREFIX).$(PACKAGE_SUFFIX)

$(TARGET_DIR)/$(OUTPUT_PACKAGE_PREFIX).$(PACKAGE_SUFFIX) : $(RUBY_DEST_DIR) $(IN_PLUGINS_LIB)

	@echo "========================= Performing Building installation package"
	$(MKPATH) $(INSTALLER_TMPDIR)
	sudo $(RMDIR) $(STAGING_DIR)
	python $(PAL_DIR)/installer/InstallBuilder/installbuilder.py \
		--BASE_DIR=$(BASE_DIR) \
		--TARGET_DIR=$(TARGET_DIR) \
		--INTERMEDIATE_DIR=$(INSTALLER_TMPDIR) \
		--STAGING_DIR=$(STAGING_DIR) \
		--BUILD_TYPE=$(BUILD_TYPE) \
		--BUILD_CONFIGURATION=$(BUILD_CONFIGURATION) \
		--RUBY_INT=intermediate/$(BUILD_CONFIGURATION)/ruby \
		--RUBY_ARCH=$(RUBY_ARCH) \
		--RUBY_ARCM=$(RUBY_ARCM) \
		--PFARCH=$(PF_ARCH) \
		--PFDISTRO=$(PF_DISTRO) \
		--PFMAJOR=$(PF_MAJOR) \
		--PFMINOR=$(PF_MINOR) \
		--VERSION=$(OMS_BUILDVERSION_MAJOR).$(OMS_BUILDVERSION_MINOR).$(OMS_BUILDVERSION_PATCH) \
		--RELEASE=$(OMS_BUILDVERSION_BUILDNR) \
		--VERSION_IDENT="$(OMS_BUILDVERSION_DATE) $(OMS_BUILDVERSION_STATUS)" \
		--DATAFILE_PATH=$(BASE_DIR)/installer/datafiles \
		--OUTPUTFILE=$(OUTPUT_PACKAGE_PREFIX) \
		$(INSTALLER_DATAFILES_CURRENT)

endif

#--------------------------------------------------------------------------------
# Run unit tests
#
# Note: With the upgrade to Ruby 2.4, rake needs the temporary $PATH (system
#       environment variable) change to execute using the correct Ruby (the
#       OMSAgent test Ruby)

set_ruby_test_ssl_100:
	$(eval RUBY_TESTING_TARGET_NAME = test_100)
	@echo "RUBY_TESTING_TARGET_NAME=${RUBY_TESTING_TARGET_NAME}"

set_ruby_test_ssl_110:
	$(eval RUBY_TESTING_TARGET_NAME = test_110)
	@echo "RUBY_TESTING_TARGET_NAME=${RUBY_TESTING_TARGET_NAME}"

tests : test

unittest : $(RUBY_TESTING_DIR)
	@echo "========================= Performing Running MSFT Unit Tests"
	cp $(PLUGINS_DIR)/* $(RUBY_TESTING_PLUGIN_DIR)
	cd $(BASE_DIR); PATH=$(RUBY_TESTING_DIR)/bin:$(PATH) $(RUBY_TESTING_DIR)/bin/rake --trace -f $(BASE_DIR)/test/Rakefile.rb test \
		BASE_DIR=$(BASE_DIR) \
		PLUGINS_TEST_DIR=$(BASE_DIR)/test/code/plugins \
		RUBY_DEST_DIR=$(RUBY_TESTING_DIR)

systemtest: systemtestrb

ifneq (,$(wildcard $(SYSTEST_CONFIG)))
systemtestrb : $(RUBY_TESTING_DIR)
	# Any tests that are slow or communicate with a remote server
	@echo "========================= Performing System Test"
	cp $(PLUGINS_DIR)/* $(RUBY_TESTING_PLUGIN_DIR)
	. $(SYSTEST_CONFIG); \
	cd $(BASE_DIR); PATH=$(RUBY_TESTING_DIR)/bin:$(PATH) $(RUBY_TESTING_DIR)/bin/rake -f $(BASE_DIR)/test/Rakefile.rb systemtest \
		BASE_DIR=$(BASE_DIR) \
		PLUGINS_TEST_DIR=$(BASE_DIR)/test/code/plugins \
		RUBY_TESTING_DIR=$(RUBY_TESTING_DIR) \
		RUBY_DEST_DIR=$(RUBY_TESTING_DIR)
else
systemtestrb:
	@echo "Warning: ruby system tests will not run without $(SYSTEST_CONFIG)" >&2
endif

omstest : unittest systemtest

test : omstest

tests_100: set_ruby_test_ssl_100 tests
tests_110: set_ruby_test_ssl_110 tests

unittest_100: set_ruby_test_ssl_100 unittest
unittest_110: set_ruby_test_ssl_110 unittest

systemtest_100: set_ruby_test_ssl_100 systemtest
systemtest_110: set_ruby_test_ssl_110 systemtest

omstest_100: set_ruby_test_ssl_100 omstest
omstest_110: set_ruby_test_ssl_110 omstest

test_100: set_ruby_test_ssl_100 test
test_110: set_ruby_test_ssl_110 test
