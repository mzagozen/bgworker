SHELL=/bin/bash
# Include standard NID (NSO in Docker) package Makefile that defines all
# standard make targets
include nidpackage.mk

# The rest of this file is specific to this repository.

testenv-start-extra:
# NOOP

# Tests go in testenv-test
testenv-test:
	$(MAKE) testenv-test-working
	$(MAKE) testenv-test-disable
	$(MAKE) testenv-test-emergency-stop

testenv-test-working:
	@echo -e "\n== Verify that the worker is alive by observing the increasing counter"
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) testenv-test-counter-working

testenv-test-disable:
	@echo -e "\n== Verify that it is possible to disable and re-enable the worker"
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) testenv-test-counter-working
	@echo "-- Disable worker"
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw disabled\n commit"
	$(MAKE) testenv-test-counter-stopped
	@echo "-- Enable worker again"
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) testenv-test-counter-working

testenv-test-emergency-stop:
	@echo -e "\n== Verify that the emergency-stop action works"
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) testenv-test-counter-working
	@echo "-- Signal the worker to stop immediately"
	$(MAKE) testenv-runcmdJ CMD="request tbgw emergency-stop"
	sleep 1
	$(MAKE) testenv-test-counter-stopped
	@echo "-- Enable worker again by redeploying"
	$(MAKE) testenv-runcmdJ CMD="request packages reload"
	$(MAKE) testenv-test-counter-working

testenv-test-counter-working:
	@echo "-- Verify counter is being incremented"
	diff <($(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }') <(sleep 2; $(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }'); test $$? -eq 1

testenv-test-counter-stopped:
	@echo "-- Verify counter is not being incremented"
	diff <($(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }') <(sleep 5; $(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }')
