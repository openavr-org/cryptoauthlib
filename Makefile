.PHONY: all libcryptoauth libateccssl libpkcs11 dist install clean

V ?= 0
ifeq ($(V),0)
  QQ = @
  Q  = @
else
  ifeq ($(V),1)
    QQ = @
    Q  =
  else
    QQ =
    Q  =
  endif
endif

OPTIONS := ATCAPRINTF
OPTIONS += ENGINE_DYNAMIC_SUPPORT
OPTIONS += USE_ECCX08
OPTIONS += ECC_DEBUG

#
# Pick one of the following:
#
OPTIONS += ATCA_HAL_I2C
#OPTIONS += ATCA_HAL_SWI
#OPTIONS += ATCA_HAL_SPI
#OPTIONS += ATCA_HAL_UART
#OPTIONS += ATCA_HAL_KIT_HID
#OPTIONS += ATCA_HAL_KIT_CDC

OPTIONS += MAX_I2C_BUSES=4

TARGET_HAL ?= I2C

SYSTEM_INCLUDES := /usr/include

# Check platform
ifeq ($(OS),Windows_NT)
# Special check for simulated windows environments
uname_S := $(shell cmd /C 'uname -s' 2>nul)
ifeq ($(uname_S),)
# Straight-up windows detected
uname_S := Windows
endif
else
uname_S := $(shell uname -s 2>/dev/null)
endif

# Define helpful macros for interacting with the specific environment
BACK2SLASH = $(subst \,/,$(1))
SLASH2BACK = $(subst /,\,$(1))

ifeq ($(uname_S),Windows)
# Windows commands
FIND = $(shell dir $(call SLASH2BACK,$(1)\$(2)) /W /B /S)
MKDIR = $(shell mkdir $(call SLASH2BACK,$(1)))
else
# Assume *nix like commands
FIND = $(shell find $(abspath $(1)) -name $(2))
MKDIR = $(shell mkdir -p $(1) 2>/dev/null)
endif

# If the target wasn't specified assume the target is the build machine
ifeq ($(TARGET_ARCH),)
ifeq ($(OS),Windows_NT)
TARGET_ARCH = Windows
endif
endif

ifeq ($(uname_S),Linux)
CFLAGS += -g -O1 -Wall -Werror -fPIC $(addprefix -D,$(OPTIONS))
TARGET_ARCH := Linux
endif
#    ifeq ($(uname_S),Darwin)
#        CCFLAGS += -D OSX
#    endif
#    UNAME_P := $(shell uname -p)
#    ifeq ($(UNAME_P),x86_64)
#        CCFLAGS += -D AMD64
#    endif
#    ifneq ($(filter %86,$(UNAME_P)),)
#        CCFLAGS += -D IA32
#    endif
#    ifneq ($(filter arm%,$(UNAME_P)),)
#        CCFLAGS += -D ARM
#    endif

OPENSSLDIR = /usr/include/openssl

OUTDIR := $(abspath ./obj)

.PHONY: $(OUTDIR)

DEPFLAGS = -MT $@ -MMD -MP -MF $(OUTDIR)/$*.d
ARFLAGS = rcs


# Wildcard all the sources and headers
SOURCES := $(call FIND,lib,*.c)
INCLUDE := $(sort $(dir $(call FIND, lib, *.h)))

# Gather OpenSSL Engine objects
LIBATECCSSL_OBJECTS := $(filter $(abspath lib/openssl)/%, $(SOURCES))
# Example if statically linking in the certificate definition
#LIBATECCSSL_OBJECTS += cert_def_1_signer.c cert_def_2_signer.c
LIBATECCSSL_OBJECTS := $(addprefix $(OUTDIR)/,$(notdir $(LIBATECCSSL_OBJECTS:.c=.o)))

# Gather PKCS11 Objects
LIBPKCS11_OBJECTS := $(filter $(abspath lib/pkcs11)/%, $(SOURCES))
LIBPKCS11_OBJECTS := $(addprefix $(OUTDIR)/,$(notdir $(LIBPKCS11_OBJECTS:.c=.o)))

# Gather libcryptoauth objects
LIBCRYPTOAUTH_OBJECTS := $(filter-out $(abspath lib/hal)/%, $(SOURCES))
LIBCRYPTOAUTH_OBJECTS := $(filter-out $(abspath lib/pkcs11)/%, $(LIBCRYPTOAUTH_OBJECTS))
LIBCRYPTOAUTH_OBJECTS := $(filter-out $(abspath lib/openssl)/%, $(LIBCRYPTOAUTH_OBJECTS))
LIBCRYPTOAUTH_OBJECTS += atca_hal.c

ifeq ($(TARGET_ARCH),Windows)
# Only kit protocol hals are available on windows
LIBCRYPTOAUTH_OBJECTS += hal_win_kit_cdc.c hal_win_timer.c hal_win_os.c kit_protocol.c
endif

ifeq ($(TARGET_ARCH),Linux)
# General Linux Support
LIBCRYPTOAUTH_OBJECTS += hal_linux_timer.c

ifeq ($(TARGET_HAL),I2C)
# Native I2C hardware/driver
LIBCRYPTOAUTH_OBJECTS += hal_linux_i2c_userspace.c
else
# Assume Kit Protocol
LIBCRYPTOAUTH_OBJECTS += hal_linux_kit_cdc.c kit_protocol.c
endif
endif

TEST_SOURCES := $(call FIND,test,*.c)
#TEST_INCLUDE := $(sort $(dir $(call FIND, test, *.h)))
TEST_INCLUDE := $(abspath .)
TEST_OBJECTS := $(addprefix $(OUTDIR)/,$(notdir $(TEST_SOURCES:.c=.o)))

LIBCRYPTOAUTH_OBJECTS := $(addprefix $(OUTDIR)/,$(notdir $(LIBCRYPTOAUTH_OBJECTS:.c=.o)))

CFLAGS += $(addprefix -I, $(INCLUDE) $(TEST_INCLUDE) $(SYSTEM_INCLUDES))

# Regardless of platform set the vpath correctly
vpath %.c $(call BACK2SLASH,$(sort $(dir $(SOURCES) $(TEST_SOURCES))))

$(info TARGET_ARCH=$(TARGET_ARCH))
$(info TARGET_HAL=$(TARGET_HAL))

#all: $(LIBCRYPTOAUTH_OBJECTS) $(LIBATECCSSL_OBJECTS) $(LIBPKCS11_OBJECTS) | $(OUTDIR)
all: libpkcs11 libateccssl libcryptoauth | $(OUTDIR)

info:
	-@for src in $(SOURCES); do echo $$src; done

$(OUTDIR):
	$(call MKDIR, $(OUTDIR))

$(OUTDIR)/%.o : %.c $(OUTDIR)/%.d | $(OUTDIR)
	-@echo "CC $@"
	$(Q)$(CC) $(DEPFLAGS) $(CFLAGS) -c $< -o $@

$(OUTDIR)/%.d: ;
.PRECIOUS: $(OUTDIR)/%.d

$(OUTDIR)/libcryptoauth.a: $(LIBCRYPTOAUTH_OBJECTS) | $(OUTDIR)
	-@echo "AR $@"
	$(Q)$(AR) $(ARFLAGS) $@ $(LIBCRYPTOAUTH_OBJECTS)

$(OUTDIR)/libateccssl.so.1: $(LIBATECCSSL_OBJECTS) $(LIBCRYPTOAUTH_OBJECTS) | $(OUTDIR)
	-@echo "LD $@"
	$(Q)$(CC) -shared -Wl,-soname,libateccssl.so.1 -o $@ $(LIBATECCSSL_OBJECTS) $(LIBCRYPTOAUTH_OBJECTS) -lcrypto -lrt
	-$(Q)rm -f $(OUTDIR)/libateccssl.so
	$(Q)ln -s libateccssl.so.1 $(OUTDIR)/libateccssl.so

$(OUTDIR)/test: $(OUTDIR)/libateccssl.so.1 $(TEST_OBJECTS) | $(OUTDIR)
	-@echo "LINK $@"
	$(Q)$(CC) -o $@ $(TEST_OBJECTS) -L$(OUTDIR) -lateccssl -lcrypto -lssl

include $(wildcard $(patsubst %,$(OUTDIR)/%.d,$(basename $(SOURCES))))

libpkcs11: $(LIBPKCS11_OBJECTS) | $(OUTDIR)

libateccssl: $(OUTDIR)/libateccssl.so.1 | $(OUTDIR)

libcryptoauth: $(OUTDIR)/libcryptoauth.a | $(OUTDIR)

test: $(OUTDIR)/test | $(OUTDIR)

run-test: test
	env LD_LIBRARY_PATH=$(OUTDIR) $(OUTDIR)/test

clean:
	rm -rf $(OUTDIR)
