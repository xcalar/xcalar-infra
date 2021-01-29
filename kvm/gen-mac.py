#!/usr/bin/env python2.7
try:
    import virtinst.util
    print virtinst.util.randomMAC()
except ImportError:
    import random

    def randomMAC():
            mac = [ 0x00, 0x16, 0x3e,
                    random.randint(0x00, 0x7f),
                    random.randint(0x00, 0xff),
                    random.randint(0x00, 0xff) ]
            return ':'.join(map(lambda x: "%02x" % x, mac))
    print randomMAC()
