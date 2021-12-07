# -*- mode: python; python-indent: 4 -*-
import time

import ncs

class SlowUpgrade(ncs.upgrade.Upgrade):
    def upgrade(self, cdbsock, trans):
        time.sleep(10)
