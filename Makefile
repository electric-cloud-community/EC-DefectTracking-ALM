# Makefile

SRCTOP=..
include $(SRCTOP)/build/vars.mak

build: buildJavaPlugin package

unittest:

systemtest: test-setup test-run

NTESTFILES  ?= systemtest

test-setup:
	$(INSTALL_PLUGINS) EC-DefectTracking EC-DefectTracking-ALM

test-run: systemtest-run

include $(SRCTOP)/build/rules.mak

test: build install promote

install:
	ectool installPlugin ../../../out/common/nimbus/EC-DefectTracking-ALM/EC-DefectTracking-ALM.jar
 
promote:
	ectool promotePlugin EC-DefectTracking-ALM
