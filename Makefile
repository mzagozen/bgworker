SHELL=/bin/bash
# Include standard NID (NSO in Docker) package Makefile that defines all
# standard make targets
include nidpackage.mk

# The rest of this file is specific to this repository.

# Start extra containers or place things you want to run once, after startup of
# the containers, in testenv-start-extra.
testenv-start-extra:
	@echo "\n== Starting repository specific testenv"

# Tests go in testenv-test
testenv-test:
	$(MAKE) testenv-test-counter-working
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw disabled\n commit"
	$(MAKE) testenv-test-counter-stopped
	$(MAKE) testenv-runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) testenv-test-counter-working


testenv-test-counter-working:
	@echo "-- Verify counter is being incremented"
	diff <($(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }') <(sleep 2; $(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }'); test $$? -eq 1

testenv-test-counter-stopped:
	@echo "-- Verify counter is not being incremented"
	diff <($(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }') <(sleep 5; $(MAKE) testenv-runcmdJ CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }')
