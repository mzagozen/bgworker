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

testenv-test-restart:
	@echo -e "\n== Verify that restart works"
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) testenv-test-counter-working
	@echo "-- Restart the worker"
	$(MAKE) testenv-runcmdJ CMD="request tbgw restart"
	$(MAKE) testenv-test-counter-working
	@echo "-- Ensure we have right number of Python processes (so we don't leak processes)"
	docker exec -t $(CNT_PREFIX)-nso bash -lc 'ps auxwww' | awk 'BEGIN {c=0} /python/ { c++ } END { print "Got", c, "Python processes (expect 3)"; if (c != 3) { exit 1 }}'

testenv-test-restart-disable:
	@echo -e "\n== Verify that restart won't start disabled worker"
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw disabled\n commit"
	$(MAKE) testenv-test-counter-stopped
	@echo "-- Restart the worker"
	$(MAKE) testenv-runcmdJ CMD="request tbgw restart" | grep "The background worker is disabled in configuration"
	$(MAKE) testenv-test-counter-stopped
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

testenv-test-emergency-stop-and-restart:
	@echo -e "\n== Verify that the emergency-stop action works"
	@echo "-- Ensure worker is enabled in configuration"
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) testenv-test-counter-working
	@echo "-- Signal the worker to stop immediately"
	$(MAKE) testenv-runcmdJ CMD="request tbgw emergency-stop"
	$(MAKE) testenv-test-counter-stopped
	@echo "-- Verify the worker was disabled"
	$(MAKE) testenv-runcmdJ CMD="show configuration tbgw enabled" | grep disabled
	@echo "-- Restart the worker"
	$(MAKE) testenv-runcmdJ CMD="request tbgw restart"
	$(MAKE) testenv-test-counter-working


testenv-test-counter-working:
	@echo "-- Verify counter is being incremented"
	diff <($(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }') <(sleep 2; $(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }'); test $$? -eq 1

testenv-test-counter-stopped:
	@echo "-- Verify counter is not being incremented"
	diff <($(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }') <(sleep 5; $(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }')
