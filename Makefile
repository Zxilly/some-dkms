KERNEL_RELEASE  ?= $(shell uname -r)
KERNEL_DIR      ?= /lib/modules/$(KERNEL_RELEASE)/build
DKMS_TARBALL    ?= dkms.tar.gz
TAR             ?= tar
obj-m           += alg.o

.PHONY: all clean load unload

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules

clean: clean-dkms-tarball
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean

.PHONY: dkms-tarball clean-dkms-tarball

$(DKMS_TARBALL): dkms.conf Makefile alg.c
	$(TAR) zcf $(DKMS_TARBALL) \
		--transform 's,^,./dkms_source_tree/,' \
		dkms.conf \
		Makefile \
		alg.c

dkms-tarball: $(DKMS_TARBALL)

clean-dkms-tarball:
	$(RM) $(DKMS_TARBALL)