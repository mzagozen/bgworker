SHELL=/bin/bash
# Include standard NID (NSO in Docker) package Makefile that defines all
# standard make targets
-include nidpackage.mk

# The following are specific to this repositories packages
testenv-start-extra:
	@echo "Starting repository specific testenv"

testenv-test:
	$(MAKE) testenv-test-counter-working
	$(MAKE) testenv-runcmd CMD="configure\n set tbgw disabled\n commit"
	$(MAKE) testenv-test-counter-stopped
	$(MAKE) testenv-test-counter-stopped
	$(MAKE) testenv-runcmd CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) testenv-test-counter-working


testenv-test-counter-working:
	@echo "-- Verify counter is being incremented"
	diff <($(MAKE) testenv-runcmd CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }') <(sleep 2; $(MAKE) testenv-runcmd CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }'); test $$? -eq 1

testenv-test-counter-stopped:
	@echo "-- Verify counter is not being incremented"
	diff <($(MAKE) testenv-runcmd CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }') <(sleep 2; $(MAKE) testenv-runcmd CMD="show tbgw counter" | awk '/^tbgw counter/ { print $$3 }')
