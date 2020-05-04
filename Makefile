SHELL=/bin/bash
# Include standard NID (NSO in Docker) package Makefile that defines all
# standard make targets
include nidpackage.mk

# The rest of this file is specific to this repository.

testenv-start-extra:
	@echo "\n== Starting repository specific testenv"
# Start extra things, for example a netsim container by doing:
# docker run -td --name $(CNT_PREFIX)-my-netsim --network-alias mynetsim1 $(DOCKER_ARGS) $(IMAGE_PATH)my-ned-repo/netsim:$(DOCKER_TAG)
# Note how it becomes available under the name 'mynetsim1' from the NSO
# container, i.e. you can set the device address to 'mynetsim1' and it will
# magically work.

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
