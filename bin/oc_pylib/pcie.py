
# SPDX-License-Identifier: MPL-2.0

import os
import sys
import mmap
import struct
import getpass
import re

class PCIe:

    def __init__(self, slot, bar):
        if getpass.getuser() != 'root' :
            self.error(f"PCIe access requires root, please use su or sudo")
        self.mm = None
        self.mv = None
        self.fd = None
        self.bar = bar
        m = re.match('(\w\w\w\w):(\w\w):(\w\w)\.(\w)', slot)
        if m:
            self.domain = int(m.group(1), 16)
            self.bus = int(m.group(2), 16)
            self.device = int(m.group(3), 16)
            self.function = int(m.group(4), 16)
        else:
            m = re.match('(\w\w):(\w\w)\.(\w)', slot)
            if m:
                self.domain = 0
                self.bus = int(m.group(1), 16)
                self.device = int(m.group(2), 16)
                self.function = int(m.group(3), 16)
            else:
                self.error(f"Didn't understand PCIe slot '{slot}', use xxxx:xx:xx.x or xx:xx.x")

    def error(self, txt, e=None):
        print(f"ERROR: {txt}")
        if e: print(e)
        sys.exit(-1)
        
    def mmap(self):
        pcie_config = "/sys/bus/pci/devices/%04x:%02x:%02x.%1x/config" % (self.domain, self.bus,
                                                                         self.device, self.function)
        try :
            with open(pcie_config,'rb') as p:
                p.seek(0x10 + 4*self.bar) # read the offset for this BAR
                self.phys = struct.unpack("<L",p.read(4))[0]
                self.offset = ((self.phys & 0xFFFFFFF0) % 0x1000)
        except Exception as e :
            self.error(f"Failed to open {pcie_config}", e)

        pcie_resource = "/sys/bus/pci/devices/%04x:%02x:%02x.%1x/resource%d" % (self.domain, self.bus, self.device,
                                                                               self.function, self.bar)
        try :
            self.fd = os.open( pcie_resource,  os.O_RDWR | os.O_SYNC)
        except Exception as e :
            self.error(f"Failed to open {pcie_resource}", e)
        statinfo = os.stat(pcie_resource)
        self.size = statinfo.st_size
        print(f"DEBUG: found bar0 of size {self.size}") 
        try :
            self.mm = mmap.mmap( self.fd, self.size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        except Exception as e :
            self.error(f"Failed to mmap the slot", e)
        try :
            self.mv = memoryview(self.mm).cast('I')
        except Exception as e :
            self.error(f"Failed to create memoryview", e)
        print(f"DEBUG: created memoryview") 

    def close(self):
        if self.mm :
            self.mv.release()
            self.mm.close()
        if self.fd != None :
            os.close(self.fd)

    def read32(self, address):
        if not self.mm : self.error(f"PCIe not open??")
        return self.mv[address>>2]

    def write32(self,address,val):
        if not self.mm : self.error(f"PCIe not open??")
        self.mv[address>>2] = val

