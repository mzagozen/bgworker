SHELL=/bin/bash
# Include standard NID (NSO in Docker) package Makefile that defines all
# standard make targets
include nidpackage.mk

# The rest of this file is specific to this repository.

testenv-start-extra:
# NOOP

# Which TBGW instance to test
# tbgw is the default one
# tbgw-ha-always
# tbgw-ha-slave
TEST_TBGW?=tbgw

# Tests go in testenv-test
testenv-test:
	$(MAKE) testenv-test-working
	$(MAKE) testenv-test-disable
	$(MAKE) testenv-test-emergency-stop
	$(MAKE) test-ha

test-ha:
ifeq ($(shell test "$(NSO_VERSION_MAJOR)" = 4  -o  \
                   "$(NSO_VERSION_MAJOR)" = 5  -a  \
                   "$(NSO_VERSION_MINOR)" = 1 -o \
                   "$(NSO_VERSION_MINOR)" = 2 -o \
                   "$(NSO_VERSION_MINOR)" = 3 \
                   &&  printf "true"), true)
	@echo "Skipping HA tests on NSO version < 5.4"
else
	$(MAKE) test-ha-none
	$(MAKE) test-ha-master
	$(MAKE) test-ha-slave
endif

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

test-ha-none: export NSO=$@
test-ha-none:
	@echo -e "\n== Ensure bgworker behavior when in HA-mode = none"
	-docker rm -f $(CNT_PREFIX)-nso$@
	docker network inspect $(CNT_PREFIX) >/dev/null 2>&1 || docker network create $(CNT_PREFIX)
	docker run -td --name $(CNT_PREFIX)-nso$@ $(DOCKER_NSO_ARGS) -e ADMIN_PASSWORD=NsoDocker1337 -e HA_ENABLE=true $${NSO_EXTRA_ARGS} $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'ncs --wait-started 600'
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="show ncs-state ha"
	@echo "-- Per default we expect bgworker to not run"
	$(MAKE) testenv-test-counter-stopped
	@echo "-- The tbgw-ha-always instance should be running though"
	$(MAKE) testenv-test-counter-working TEST_TBGW=tbgw-ha-always
	@echo "-- The tbgw-ha-slave instance should NOT run"
	$(MAKE) testenv-test-counter-stopped TEST_TBGW=tbgw-ha-slave
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep "Background worker will not run when HA-when=master and HA-mode=none"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep "Background worker will not run when HA-when=slave and HA-mode=none"
	-docker rm -f $(CNT_PREFIX)-nso$@

test-ha-master: export NSO=$@
test-ha-master:
	@echo -e "\n== Ensure bgworker behavior when in HA-mode = master"
	docker network inspect $(CNT_PREFIX) >/dev/null 2>&1 || docker network create $(CNT_PREFIX)
	-docker rm -f $(CNT_PREFIX)-nso$@
	docker run -td --name $(CNT_PREFIX)-nso$@ $(DOCKER_NSO_ARGS) -e ADMIN_PASSWORD=NsoDocker1337 -e HA_ENABLE=true $${NSO_EXTRA_ARGS} $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'ncs --wait-started 600'
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="show ncs-state ha"
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="configure\nedit high-availability\nset token ohsosecret\nset ha-node localhost address 127.0.0.1 nominal-role master\ncommit"
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="request high-availability enable"
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="request high-availability be-master"
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="show ncs-state ha"
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="request packages reload"
	@echo "-- Per default we expect bgworker to run"
	$(MAKE) testenv-test-counter-working
	@echo "-- The tbgw-ha-always instance should be running too"
	$(MAKE) testenv-test-counter-working TEST_TBGW=tbgw-ha-always
	@echo "-- The tbgw-ha-slave instance should NOT run"
	$(MAKE) testenv-test-counter-stopped TEST_TBGW=tbgw-ha-slave
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep "Background worker will not run when HA-when=slave and HA-mode=master"
	-docker rm -f $(CNT_PREFIX)-nso$@


HA_MASTER_ADDRESS=$$(docker inspect --format '{{range $$p, $$conf := .NetworkSettings.Networks}}{{(index $$conf).IPAddress}}{{end}}' $(CNT_PREFIX)-nso$@master | head -n1 | cat)
test-ha-slave: export NSO=$@
test-ha-slave:
	@echo -e "\n== Ensure bgworker behavior when in HA-mode = slave"
	docker network inspect $(CNT_PREFIX) >/dev/null 2>&1 || docker network create $(CNT_PREFIX)
	-docker rm -f $(CNT_PREFIX)-nso$@
	-docker rm -f $(CNT_PREFIX)-nso$@master
	docker run -td --name $(CNT_PREFIX)-nso$@ $(DOCKER_NSO_ARGS) -e ADMIN_PASSWORD=NsoDocker1337 -e HA_ENABLE=true $${NSO_EXTRA_ARGS} $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
	docker run -td --name $(CNT_PREFIX)-nso$@master $(DOCKER_NSO_ARGS) -e ADMIN_PASSWORD=NsoDocker1337 -e HA_ENABLE=true $${NSO_EXTRA_ARGS} $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
	docker exec -t $(CNT_PREFIX)-nso$@master bash -lc 'ncs --wait-started 600'
	$(MAKE) testenv-runcmdJ NSO=$@master CMD="configure\nedit high-availability\nset token ohsosecret\nset ha-node master address $(HA_MASTER_ADDRESS) nominal-role master\ncommit"
	$(MAKE) testenv-runcmdJ NSO=$@master CMD="request high-availability enable"
	$(MAKE) testenv-runcmdJ NSO=$@master CMD="request high-availability be-master"
	$(MAKE) testenv-runcmdJ NSO=$@master CMD="show ncs-state ha"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'ncs --wait-started 600'
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="show ncs-state ha"
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="configure\nedit high-availability\nset token ohsosecret\nset ha-node slave address 127.0.0.1 nominal-role slave\nset ha-node master address $(HA_MASTER_ADDRESS) nominal-role master\ncommit"
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="request high-availability enable"
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="request high-availability be-slave-to node master"
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="show ncs-state ha"
	@echo "-- Give NSO some time to become slave and run tbgw + error out"
	sleep 5
	$(MAKE) testenv-runcmdJ NSO=$@ CMD="show ncs-state ha" | grep "ncs-state ha mode slave"
	@echo "-- Expect to see errors in log since we are in read-only mode (slave) and thus, trying to update counter results in error"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep -A1 "TBGW starting on YANG: tbgw-ha-always" | grep "Unhandled error in test_bgwork"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep -A1 "TBGW starting on YANG: tbgw-ha-slave" | grep "Unhandled error in test_bgwork"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep "Background worker will not run when HA-when=master and HA-mode=slave"
	-docker rm -f $(CNT_PREFIX)-nso$@
	-docker rm -f $(CNT_PREFIX)-nso$@master

testenv-test-counter-working:
	@echo "-- Verify counter is being incremented"
	diff <($(MAKE) testenv-runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }') <(sleep 2; $(MAKE) testenv-runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }'); test $$? -eq 1

testenv-test-counter-stopped:
	@echo "-- Verify counter is not being incremented"
	diff <($(MAKE) testenv-runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }') <(sleep 5; $(MAKE) testenv-runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }')
