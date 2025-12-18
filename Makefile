CROSS_COMPILE	?= 
ARCH		?= x86
KERNEL_DIR	?= /usr/src/linux
DEBUG		?= 1

CC		:= $(CROSS_COMPILE)gcc
KERNEL_INCLUDE	:= -I$(KERNEL_DIR)/include -I$(KERNEL_DIR)/arch/$(ARCH)/include

# Base flags
CFLAGS_BASE := -W -Wall -O3 $(KERNEL_INCLUDE)

# Debug flags: DEBUG=1 enables debug output (default), DEBUG=0 disables it
ifeq ($(DEBUG),0)
    CFLAGS := $(CFLAGS_BASE) -DDISABLE_DEBUG
else
    CFLAGS := $(CFLAGS_BASE)
endif

LDFLAGS   := -O3g -lpthread

# Build targets:
#   make              - Build with debug output enabled (default)
#   make DEBUG=0      - Build with debug output disabled (no overhead)
#   make DEBUG=1      - Build with debug output enabled (explicit)

all: uvc-gadget

uvc-gadget: uvc-gadget.o
	$(CC) $(LDFLAGS) -o $@ $^

clean:
	rm -f *.o
	rm -f uvc-gadget
