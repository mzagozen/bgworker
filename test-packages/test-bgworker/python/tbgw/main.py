# -*- mode: python; python-indent: 4 -*-
# An applicaton for testing the bgworker library.
# We set up three different background processes
# - tbgw - uses default config to only run when HA is disabled or HA-mode=master
# - tbgw-ha-always: should always run, even when HA-mode=none
# - tbgw-ha-secondary: runs when HA-mode=secondary/slave
import logging
import time

import ncs

from bgworker import background_process


def test_bgwork(yang_path):
    log = logging.getLogger()
    log.info(f"TBGW starting on YANG: {yang_path}")

    while True:
        with ncs.maapi.single_write_trans('tbgw', 'system', db=ncs.OPERATIONAL) as oper_trans_write:
            root = ncs.maagic.get_root(oper_trans_write)
            tb = root[yang_path]
            cur_val = tb.counter
            tb.counter += 1
            oper_trans_write.apply()

        #log.debug(f"Hello from {yang_path} background worker process, increment counter from {cur_val} to {cur_val+1}")
        log.info(f"Hello from {yang_path} background worker process, increment counter from {cur_val} to {cur_val+1}")
        #log.warning(f"Hello from {yang_path} background worker process, increment counter from {cur_val} to {cur_val+1}")
        #log.error(f"Hello from {yang_path} background worker process, increment counter from {cur_val} to {cur_val+1}")
        #log.critical(f"Hello from {yang_path} background worker process, increment counter from {cur_val} to {cur_val+1}")
#        if random.randint(0, 10) == 9:
#            log.error("Bad dice value")
#            sys.exit(1)
        time.sleep(1)

class Main(ncs.application.Application):
    def setup(self):
        self.log.info('Main RUNNING')
        self.worker = background_process.Process(self, test_bgwork, ["tbgw"], config_path='/tbgw/enabled', ha_when=background_process.HaWhen.PRIMARY)
        self.register_action('tbgw-restart', background_process.RestartWorker, init_args=self.worker)
        self.register_action('tbgw-emergency-stop', background_process.EmergencyStop, init_args=self.worker)
        self.worker_ha_always = background_process.Process(self, test_bgwork, ["tbgw-ha-always"], config_path='/tbgw-ha-always/enabled', ha_when=background_process.HaWhen.ALWAYS)
        self.worker_ha_secondary = background_process.Process(self, test_bgwork, ["tbgw-ha-secondary"], config_path='/tbgw-ha-secondary/enabled', ha_when=background_process.HaWhen.SECONDARY)
        self.worker.start()
        self.worker_ha_always.start()
        self.worker_ha_secondary.start()

    def teardown(self):
        self.log.info('Main FINISHED')
        self.worker.stop()
        self.worker_ha_always.stop()
        self.worker_ha_secondary.stop()
