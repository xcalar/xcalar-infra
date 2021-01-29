# GDB commands for use with GuardRails.
# (gdb) source grgdb.py

import gdb
import gdb.printing
import re

PAGE_SIZE = 4096
NUM_GUARD_PAGES = 1
GUARD_SIZE = NUM_GUARD_PAGES * PAGE_SIZE
MAGIC_FREE  = 0xcd656727bedabb1e
MAGIC_INUSE = 0x4ef9e433f005ba11
MAGIC_GUARD = 0xfd44ba54deadbabe

def checkGr():
    try:
        gdb.parse_and_eval("grArgs")
    except gdb.error as e:
        msg = "FATAL GUARDRAILS ERROR: Program not run under guardrails"
        print(msg)
        sys.stderr.write(msg + "\n")
        raise

class GRFindDelayList (gdb.Command):
    """
        Search Guard Rails delayed free list for a given address.

        (gdb) gr-find-delay-list <delayListAddress> <addressToFind>

        Example:
        (gdb) gr-find-delay-list &memSlots[0].delay 0x7f607e24dbf0
    """

    def __init__ (self):
        super (GRFindDelayList, self).__init__ ("gr-find-delay-list", gdb.COMMAND_USER)

    def delayListCount(self, head, tail, maxDelayCt):
        if head > tail:
            return head - tail
        else:
            return maxDelayCt - (tail - head)

    def invokeHelper (self, arg, from_tty):
        argv = gdb.string_to_argv(arg)
        if len(argv) != 2:
            print("Malformed arguments; see help")
            return

        dlist = gdb.parse_and_eval('(MemFreeDelay *) ' + argv[0])
        addrToFind = int(argv[1], 16)
        dlistElms = dlist['elms']
        maxDelayCt = int(gdb.parse_and_eval('sizeof(((MemFreeDelay *)0x0)->elms)/sizeof(((MemFreeDelay *)0x0)->elms[0])'))
        head = dlist['head']
        tail = dlist['tail']
        cursor = head
        delayCount = self.delayListCount(head, tail, maxDelayCt)
        ct = 0
        while ct < delayCount:
            if not ct % 1000:
                print("Searching %7d / %d elements" % (ct, delayCount))
            elmPtr = dlistElms[cursor]
            elm = elmPtr.dereference()

            magicStr = str(elm['magic'])
            if elm['magic'] != MAGIC_FREE:
                print("Delayed free list contains invalid header magic 0x%x" % magicStr)

            elmStartAddr = int(elmPtr)

            # Consider the full allocation (not just the amount allocated for the
            # user), as the errant pointer might land anywhere in that range.
            elmEndAddr = elmStartAddr + (1 << int(elm['binNum'])) + GUARD_SIZE - 1

            if elmStartAddr <= addrToFind <= elmEndAddr:
                print("Found address 0x%x on delayed free list at index %d, header 0x%x :" % (addrToFind, cursor, elmPtr))
                # print("%x <= %x <= %x" % (elmStartAddr, addrToFind, elmEndAddr))
                print(elm)
                # An element should only appear on the list once, so return
                return

            # Search the list from the head (most recently added) backwards as
            # the element of interest is most likely recent (and search can be
            # somewhat slow)
            if cursor == 0:
                cursor = maxDelayCt
            cursor -= 1

            ct += 1

        print("Address 0x%x not found" % (addrToFind))


    def invoke(self, arg, from_tty):
        try:
            checkGr()
            self.invokeHelper(arg, from_tty)
        except Exception as e:
            print(str(e))
            traceback.print_exc()

class GRPrintAddrInfo (gdb.Command):
    """
        Try to print GuardRails info about an address.

        The address must be either the beginning of a header or beginning of a
        user allocation.  If the address is a random memory address not known
        to point to a header or beginning allocation, first try to find the
        associated header address using gr-find-header.

        If GuardRails was run with -t and/or -T options, traces will also be
        dumped for allocations/frees.

        (gdb) gr-print-addr-info <address>

        Example:
        (gdb) gr-print-addr-info 0x7fc6aa5f2000
    """

    def __init__ (self):
        super (GRPrintAddrInfo, self).__init__ ("gr-print-addr-info", gdb.COMMAND_USER)

    def isValid(self, magic):
        return magic == MAGIC_INUSE or magic == MAGIC_FREE

    def dumpSymTrace(self, trace, offset, maxFrames):
        if not maxFrames:
            print("Memory tracking not enabled; to enable rerun GuardRails with -t/-T options")
            return

        for i in range(offset, maxFrames + offset):
            addr = str(trace[i]).split(' ')[0]

            addrInt = int(addr, 0)
            if not addrInt:
                continue
            sym = str(gdb.execute('info line *' + str(addrInt), to_string=True))
            sym = re.sub(r' and ends at .*', r'', sym)
            print(sym[0:-1])

    def invokeHelper(self, arg, from_tty):
        argv = gdb.string_to_argv(arg)
        if len(argv) != 1:
            print("Malformed arguments; see help")
            return

        hdrPtr = gdb.parse_and_eval('(ElmHdr *) ' + argv[0])
        hdr = hdrPtr.dereference()
        grArgs = gdb.parse_and_eval("grArgs")
        maxAllocFrames = int(grArgs['maxTrackFrames'])
        maxFreeFrames = int(grArgs['maxTrackFreeFrames'])

        if self.isValid(hdr['magic']):
            print("Address %s is a header" % argv[0])
        else:
            hdrPtr = gdb.parse_and_eval('*(ElmHdr **)((char *)' + argv[0] + ' - sizeof(void *))')
            hdr = hdrPtr.dereference()
            if self.isValid(hdr['magic']):
                print("Address %s is a user address" % argv[0])
            else:
                print("Address %s doesn't look valid" % argv[0])
                return

        if hdr['magic'] == MAGIC_INUSE:
            print("Address %s is in-use" % argv[0])
        elif hdr['magic'] == MAGIC_FREE:
            print("Address %s is free" % argv[0])

        print("Header:")
        print(hdr)

        trace = hdr['allocBt']

        print("================ Allocation Trace: ================")
        self.dumpSymTrace(trace, 0, maxAllocFrames)
        print("================ Free Trace: ================")
        self.dumpSymTrace(trace, maxAllocFrames + 1, maxFreeFrames)

    def invoke(self, arg, from_tty):
        try:
            checkGr()
            self.invokeHelper(arg, from_tty)
        except Exception as e:
            print(str(e))
            traceback.print_exc()

class GRFindHeader(gdb.Command):
    """
        Try to find the GuardRails header address for an arbitrary address

        Use this to find the header address associated with an arbitrary memory
        address.  The output address of this command can be used with
        gr-print-addr-info.

        (gdb) gr-find-header <address>

        Example:
        (gdb) gr-find-header 0x7fc6aa5f2327
    """

    def __init__ (self):
        super (GRFindHeader, self).__init__ ("gr-find-header", gdb.COMMAND_USER)

    def isValid(self, magic):
        return magic == MAGIC_INUSE or magic == MAGIC_FREE

    def invokeHelper(self, arg, from_tty):
        argv = gdb.string_to_argv(arg)
        if len(argv) != 1 and (len(argv) == 2 and argv[1] != 'quiet') or len(argv) > 2:
            print("Malformed arguments; see help")
            return

        addr = int(argv[0], 16)
        quiet = False
        if len(argv) == 2:
            quiet = argv[1] == 'quiet'
        mask = 0xffffffffffffffff - PAGE_SIZE + 1
        headerStart = addr & mask

        currHeader = headerStart
        while (True):
            hdrPtr = gdb.parse_and_eval('((ElmHdr *) ' + str(currHeader) + ')')
            hdr = hdrPtr.dereference()
            if self.isValid(hdr['magic']):
                # XXX: Add header sanity checks here
                if quiet:
                    print("0x%x" % currHeader)
                else:
                    print("Found valid header at: 0x%x" % currHeader)
                break

            assert(currHeader > PAGE_SIZE)
            currHeader -= PAGE_SIZE

    def invoke(self, arg, from_tty):
        try:
            checkGr()
            self.invokeHelper(arg, from_tty)
        except Exception as e:
            print(str(e))
            traceback.print_exc()

class GRHeapMetaCorruption(gdb.Command):
    """
        Try to determine if a faulting address would cause heap corruption.

        This command indicates if accessing a given address would cause
        corruption by determining if the access falls on a guard page.

        (gdb) gr-heap-meta-corruption <address>

        Example:
        (gdb) gr-heap-meta-corruption 0x7fc6aa5f2327
    """

    def __init__ (self):
        super (GRHeapMetaCorruption, self).__init__ ("gr-heap-meta-corruption", gdb.COMMAND_USER)

    def invokeHelper(self, arg, from_tty):
        argv = gdb.string_to_argv(arg)
        if len(argv) != 1:
            print("Malformed arguments; see help")
            return

        addr = int(argv[0], 16)
        currHeader = gdb.execute("gr-find-header 0x%x quiet" % (addr), to_string=True)
        hdrPtr = gdb.parse_and_eval('((ElmHdr *) ' + str(currHeader) + ')')
        hdr = hdrPtr.dereference()
        hdrPtrAddr = int(hdrPtr)
        guardStartAddr = hdrPtrAddr + (1 << hdr['binNum'])
        guardEndAddr = guardStartAddr + GUARD_SIZE - 1

        verifyGuard = gdb.parse_and_eval("*((uint64_t *) 0x%x)" % guardStartAddr)
        assert(verifyGuard == MAGIC_GUARD)
        if guardStartAddr <= addr <= guardEndAddr:
            print("CORRUPTION: Access of 0x%x appears to corrupt the heap metadata and/or overrun the buffer" % addr)
        else:
            print("Access of 0x%x doesn't appear to be heap metadata corruption or overrun" % addr)

    def invoke(self, arg, from_tty):
        try:
            checkGr()
            self.invokeHelper(arg, from_tty)
        except Exception as e:
            print(str(e))
            traceback.print_exc()

class GRPrintSegv(gdb.Command):
    """
        Print address of access that caused the current segfault.

        (gdb) gr-print-segv

        Example:
        (gdb) gr-print-segv
    """

    def __init__ (self):
        super (GRPrintSegv, self).__init__ ("gr-print-segv", gdb.COMMAND_USER)

    def invokeHelper(self, arg, from_tty):
        argv = gdb.string_to_argv(arg)
        if len(argv) != 0:
            print("Malformed arguments; see help")
            return

        sigInfo = gdb.parse_and_eval("$_siginfo")
        if sigInfo['si_signo'] == 7 or sigInfo['si_signo'] == 11:
            print("Memory fault at: " + str(sigInfo['_sifields']['_sigfault']['si_addr']))
        else:
            print("Unknown fault, signal %d" % sigInfo['si_signo'])

    def invoke(self, arg, from_tty):
        try:
            self.invokeHelper(arg, from_tty)
        except Exception as e:
            print(str(e))
            traceback.print_exc()

class GRDumpInFlight(gdb.Command):
    """
        Dump allocator metadata.

        WARNING: This is mostly for dumping in-flight allocations to a file
        for subsequent post-processing with grdump.py.  This is NOT recommended
        for interactive debugging.

        (gdb) gr-dump-in-flight

        Example:
        (gdb) gr-dump-in-flight
    """

    def __init__ (self):
        super (GRDumpInFlight, self).__init__ ("gr-dump-in-flight", gdb.COMMAND_USER)

    def getTraceCsv(self, trace, offset, maxFrames):
        if not maxFrames:
            print("Memory tracking not enabled; to enable rerun GuardRails with -t/-T options")
            return

        ret = ""
        for i in range(offset, maxFrames + offset):
            addrInt = int(trace[i])
            if addrInt:
                ret += "0x%x," % addrInt
            else:
                ret += ","

        return ret

    def invokeHelper(self, arg, from_tty):
        argv = gdb.string_to_argv(arg)
        if len(argv) != 0:
            print("Malformed arguments; see help")
            return

        grArgs = gdb.parse_and_eval("grArgs")
        numSlots = int(grArgs['numSlots'])
        maxAllocFrames = int(grArgs['maxTrackFrames'])
        maxFreeFrames = int(grArgs['maxTrackFreeFrames'])
        memSlots = gdb.parse_and_eval("memSlots")

        print("===== START TRACES =====")
        for slotNum in range(0, numSlots):
            memBins = memSlots[slotNum]['memBins']
            numBins = int(gdb.parse_and_eval('sizeof(((MemSlot *)0x0)->memBins)/sizeof(((MemSlot *)0x0)->memBins)[0]'))
            for binNum in range(0, numBins):
                memBin = memBins[binNum]
                hdr = memBin['headInUse']
                while hdr != 0x0:
                    csvTrace = self.getTraceCsv(hdr['allocBt'], 0, maxAllocFrames)
                    elmSize = hdr['usrDataSize']
                    print(str(elmSize) + "," + csvTrace)
                    hdr = hdr['next']

    def invoke(self, arg, from_tty):
        try:
            checkGr()
            self.invokeHelper(arg, from_tty)
        except Exception as e:
            print(str(e))
            traceback.print_exc()


GRFindDelayList()
GRPrintAddrInfo()
GRFindHeader()
GRHeapMetaCorruption()
GRPrintSegv()
GRDumpInFlight()
