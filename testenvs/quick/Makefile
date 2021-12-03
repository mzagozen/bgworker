SHELL=/bin/bash
include ../testenv-common.mk

# Enable IPv6 per default, set to false to disable (in Makefile, not here)
IPV6?=true
# start: start the test environment in a configuration that allows
# Python Remote Debugging. Exposes port 5678 on a random port on localhost.
# Per default, the IPv6 prefix is a randomly generated IPv6 network prefix in
# the ULA address space. Override by setting IPV6_NET variable to e.g.:
# IPV6_NET=2001:db8:1234:456:  # which becomes 2001:db8:1234:456::/64
# If the IPv6 prefix is not in the public unicast space (2000::/3), the IPv6
# default route will be removed. This makes it possible to have local IPv6
# connectivity within the network, yet not slow down attempts to reach Internet
# resources (where IPv6 would normally be tried first, and fail due to
# non-public addresses).
start:
	docker network inspect $(CNT_PREFIX) >/dev/null 2>&1 || docker network create $(CNT_PREFIX) $(shell [ "$(IPV6)" = "true" ] && LC_ALL=C && echo --ipv6 --subnet $${IPV6_NET:-fd00:$$(< /dev/urandom tr -dc a-f0-9 | head -c4):$$(< /dev/urandom tr -dc a-f0-9 | head -c4):$$(< /dev/urandom tr -dc a-f0-9 | head -c4):}:/64)
	docker run -td --name $(CNT_PREFIX)-nso --network-alias nso $(DOCKER_NSO_ARGS) $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
# You may start other containers that are part of the testenv here. For example
# a netsim container or a virtual router.
	-[ "$(IPV6)" = "true" ] && echo $$(docker network inspect --format '{{range .IPAM.Config}}{{- if (gt (split .Subnet ":"|len) 1) -}}{{.Subnet}}{{- end}}{{end}}' $(CNT_PREFIX)) | egrep "^[23]...:" || (echo "Removing IPv6 default route" && docker ps -aq --filter label=com.cisco.nso.testenv.name=$(CNT_PREFIX) | $(XARGS) -I CNT -n1 docker run --rm --net=container:CNT --cap-add=NET_ADMIN $(NSO_IMAGE_PATH)cisco-nso-base:$(NSO_VERSION) ip -6 route del default >/dev/null 2>&1 || true)

	$(MAKE) wait-started-nso

# Place your tests in test. Feel free to define a target per test case
# and call them from test in case you have more than a handful of cases.
# Sometimes when there is a "setup" or "preparation" part of a test, it can be
# useful to separate into its own target as to make it possible to run that
# prepare phase and then manually inspect the state of the system. You can
# achieve this by further refining the make targets you have.
test:
	@echo "\n== Running tests"
	@echo "-- Verify packages are operationally up"
	$(MAKE) runcmdJ CMD="show packages" | docker run -i --rm $(NSO_IMAGE_PATH)cisco-nso-dev:$(NSO_VERSION) bash -c '! grep -P "oper-status (?!up)" >/dev/null' || (echo "ERROR: packages not operationally up:" && $(MAKE) runcmdJ CMD="show packages" && false)
	$(MAKE) test-working
	$(MAKE) test-disable
	$(MAKE) test-emergency-stop
	$(MAKE) test-ha

# Which TBGW instance to test
# tbgw is the default one
# tbgw-ha-always
# tbgw-ha-slave
TEST_TBGW?=tbgw

# Tests go in test
test:

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

test-working:
	@echo -e "\n== Verify that the worker is alive by observing the increasing counter"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working

test-disable:
	@echo -e "\n== Verify that it is possible to disable and re-enable the worker"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working
	@echo "-- Disable worker"
	$(MAKE) runcmdJ CMD="configure\n set tbgw disabled\n commit"
	$(MAKE) test-counter-stopped
	@echo "-- Enable worker again"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working

test-restart:
	@echo -e "\n== Verify that restart works"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working
	@echo "-- Restart the worker"
	$(MAKE) runcmdJ CMD="request tbgw restart"
	$(MAKE) test-counter-working
	@echo "-- Ensure we have right number of Python processes (so we don't leak processes)"
	docker exec -t $(CNT_PREFIX)-nso bash -lc 'ps auxwww' | awk 'BEGIN {c=0} /python/ { c++ } END { print "Got", c, "Python processes (expect 3)"; if (c != 3) { exit 1 }}'

test-restart-disable:
	@echo -e "\n== Verify that restart won't start disabled worker"
	$(MAKE) runcmdJ CMD="configure\n set tbgw disabled\n commit"
	$(MAKE) test-counter-stopped
	@echo "-- Restart the worker"
	$(MAKE) runcmdJ CMD="request tbgw restart" | grep "The background worker is disabled in configuration"
	$(MAKE) test-counter-stopped
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working

test-emergency-stop:
	@echo -e "\n== Verify that the emergency-stop action works"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working
	@echo "-- Signal the worker to stop immediately"
	$(MAKE) runcmdJ CMD="request tbgw emergency-stop"
	sleep 1
	$(MAKE) test-counter-stopped
	@echo "-- Enable worker again by redeploying"
	$(MAKE) runcmdJ CMD="request packages reload"
	$(MAKE) test-counter-working

test-emergency-stop-and-restart:
	@echo -e "\n== Verify that the emergency-stop action works"
	@echo "-- Ensure worker is enabled in configuration"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working
	@echo "-- Signal the worker to stop immediately"
	$(MAKE) runcmdJ CMD="request tbgw emergency-stop"
	$(MAKE) test-counter-stopped
	@echo "-- Verify the worker was disabled"
	$(MAKE) runcmdJ CMD="show configuration tbgw enabled" | grep disabled
	@echo "-- Restart the worker"
	$(MAKE) runcmdJ CMD="request tbgw restart"
	$(MAKE) test-counter-working

test-ha-none: export NSO=$@
test-ha-none:
	@echo -e "\n== Ensure bgworker behavior when in HA-mode = none"
	-docker rm -f $(CNT_PREFIX)-nso$@
	docker network inspect $(CNT_PREFIX) >/dev/null 2>&1 || docker network create $(CNT_PREFIX)
	docker run -td --name $(CNT_PREFIX)-nso$@ $(DOCKER_NSO_ARGS) -e ADMIN_PASSWORD=NsoDocker1337 -e HA_ENABLE=true $${NSO_EXTRA_ARGS} $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'ncs --wait-started 600'
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state ha"
	@echo "-- Per default we expect bgworker to not run"
	$(MAKE) test-counter-stopped
	@echo "-- The tbgw-ha-always instance should be running though"
	$(MAKE) test-counter-working TEST_TBGW=tbgw-ha-always
	@echo "-- The tbgw-ha-slave instance should NOT run"
	$(MAKE) test-counter-stopped TEST_TBGW=tbgw-ha-slave
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
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state ha"
	$(MAKE) runcmdJ NSO=$@ CMD="configure\nedit high-availability\nset token ohsosecret\nset ha-node localhost address 127.0.0.1 nominal-role master\ncommit"
	$(MAKE) runcmdJ NSO=$@ CMD="request high-availability enable"
	$(MAKE) runcmdJ NSO=$@ CMD="request high-availability be-master"
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state ha"
	$(MAKE) runcmdJ NSO=$@ CMD="request packages reload"
	@echo "-- Per default we expect bgworker to run"
	$(MAKE) test-counter-working
	@echo "-- The tbgw-ha-always instance should be running too"
	$(MAKE) test-counter-working TEST_TBGW=tbgw-ha-always
	@echo "-- The tbgw-ha-slave instance should NOT run"
	$(MAKE) test-counter-stopped TEST_TBGW=tbgw-ha-slave
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
	$(MAKE) runcmdJ NSO=$@master CMD="configure\nedit high-availability\nset token ohsosecret\nset ha-node master address $(HA_MASTER_ADDRESS) nominal-role master\ncommit"
	$(MAKE) runcmdJ NSO=$@master CMD="request high-availability enable"
	$(MAKE) runcmdJ NSO=$@master CMD="request high-availability be-master"
	$(MAKE) runcmdJ NSO=$@master CMD="show ncs-state ha"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'ncs --wait-started 600'
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state ha"
	$(MAKE) runcmdJ NSO=$@ CMD="configure\nedit high-availability\nset token ohsosecret\nset ha-node slave address 127.0.0.1 nominal-role slave\nset ha-node master address $(HA_MASTER_ADDRESS) nominal-role master\ncommit"
	$(MAKE) runcmdJ NSO=$@ CMD="request high-availability enable"
	$(MAKE) runcmdJ NSO=$@ CMD="request high-availability be-slave-to node master"
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state ha"
	@echo "-- Give NSO some time to become slave and run tbgw + error out"
	sleep 5
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state ha" | grep "ncs-state ha mode slave"
	@echo "-- Expect to see errors in log since we are in read-only mode (slave) and thus, trying to update counter results in error"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep -A1 "TBGW starting on YANG: tbgw-ha-always" | grep "Unhandled error in test_bgwork"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep -A1 "TBGW starting on YANG: tbgw-ha-slave" | grep "Unhandled error in test_bgwork"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep "Background worker will not run when HA-when=master and HA-mode=slave"
	-docker rm -f $(CNT_PREFIX)-nso$@
	-docker rm -f $(CNT_PREFIX)-nso$@master

test-counter-working:
	@echo "-- Verify counter is being incremented"
	diff <($(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }') <(sleep 2; $(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }'); test $$? -eq 1

test-counter-stopped:
	@echo "-- Verify counter is not being incremented"
	diff <($(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }') <(sleep 5; $(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }')
