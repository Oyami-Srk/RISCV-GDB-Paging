# Usage: (gdb) so paging_debug.py
#        (gdb) help paging

import gdb

PAGE_SIZE = 4096
PTE_PER_PAGE = 512
LVL3_SIZE = PTE_PER_PAGE * PAGE_SIZE
LVL2_SIZE = PTE_PER_PAGE * LVL3_SIZE
LVL1_SIZE = PTE_PER_PAGE * LVL2_SIZE

level_total_size = [
    LVL1_SIZE,
    LVL2_SIZE,
    LVL3_SIZE,
    PAGE_SIZE
]

show_invalid = False


def print_type(type, end=' '):
    if type & 0b1:
        print('V', end=end)
    if type & 0b10:
        print('R', end=end)
    if type & 0b100:
        print('W', end=end)
    if type & 0b1000:
        print('X', end=end)
    if type & 0b10000:
        print('U', end=end)
    if type & 0b100000:
        print('G', end=end)
    if type & 0b1000000:
        print('A', end=end)
    if type & 0b10000000:
        print('D', end=end)
    if type & 0b100000000:
        print('R1', end=end)
    if type & 0b1000000000:
        print('R2', end=end)


def parse_page_table(pgdir: gdb.Value, level: int, offset: int):
    if level == 0:
        print(f"Page Table @ 0x{format(int(pgdir), 'X')}")
    last_pa = 0
    last_start = 0
    last_end = 0
    last_type = 0
    last_continue = False

    for id in range(0, PTE_PER_PAGE):
        pte = int(pgdir[id])
        if pte != 0:
            pte = format(pte, '064b')[::-1]
            pte_ppn = int(pte[10:54][::-1], 2)
            V = int(pte[0])
            R = int(pte[1])
            W = int(pte[2])
            X = int(pte[3])
            type = int(pte[0:10][::-1], 2)
            if V or show_invalid:
                entry_size = level_total_size[level + 1]
                start = offset + id * entry_size
                pa = gdb.Value(
                    pte_ppn * PAGE_SIZE).cast(gdb.lookup_type("unsigned long long *"))
                if R == W == X == 0:
                    # Dir Entry
                    print("│  " * (level) + "├", end='')
                    print(f"Directory @ 0x{format(int(pa), 'X')}")
                    parse_page_table(pa, level + 1, start)
                    last_start = last_end = last_type = last_pa = 0
                    last_continue = False
                else:
                    # Leaf node
                    pa = int(pa)
                    end = start + entry_size
                    if last_end == start and last_type == type and last_pa + (last_end - last_start) == pa:
                        # Contiune blocks
                        last_end = end
                        last_continue = True
                    else:
                        # Not continue
                        if last_continue:
                            print("│  " * (level) + "├", end='')
                            print(
                                f"0x{format(last_start, 'X')} ~ 0x{format(last_end, 'X')} => ", end='')
                            print(
                                f"0x{format(last_pa, 'X')} ~ 0x{format(last_pa + (last_end - last_start), 'X')}", end='')
                            print(' | ', end='')
                            print_type(last_type)
                            print()
                        last_start = start
                        last_end = end
                        last_pa = pa
                        last_type = type
                        last_continue = True

    if last_continue:
        print("│  " * (level) + "├", end='')
        print(
            f"0x{format(last_start, 'X')} ~ 0x{format(last_end, 'X')} => ", end='')
        print(
            f"0x{format(last_pa, 'X')} ~ 0x{format(last_pa + (last_end - last_start), 'X')}", end='')
        print(' | ', end='')
        print_type(last_type)
        print()


class Paging(gdb.Command):

    """RISC-V SV39 MMU Paging Debugging tool.
Usage: 
    paging           : The shortcut of `paging satp` 
    paging satp      : Show page table from satp register.
    paging addr      : Show page table at addr.
Example:
    (gdb) paging
    (gdb) paging satp
    (gdb) paging 0x12340000"""

    def __init__(self):
        super(self.__class__, self).__init__("paging", gdb.COMMAND_USER)

    def invoke(self, args, from_tty):
        root_pgdir = None
        args = gdb.string_to_argv(args)
        if len(args) == 0 or args[0] == "satp":
            satp = gdb.selected_frame().read_register('satp')
            satp = int(satp.cast(gdb.lookup_type("unsigned long long")))
            satp = format(satp, '064b')[::-1]
            satp_ppn = int(satp[0:44][::-1], 2)
            satp_asid = int(satp[44:60][::-1], 2)
            satp_mode = int(satp[60:64][::-1], 2)
            root_pgdir = satp_ppn * PAGE_SIZE
            print(f"MMU Mode: {satp_mode}, ASID: {satp_asid}.")
            print(
                f"Page table root address: {'0x{:016X}'.format(root_pgdir)}")
            if satp_mode != 8:
                print("Only support SV39 paging mode with mode 8.")
                return
            root_pgdir = gdb.Value(
                int(root_pgdir)).cast(gdb.lookup_type("unsigned long long *"))
        else:
            if 'x' in args[0] or 'X' in args[0]:
                root_pgdir = gdb.Value(
                    int(args[0], 16)).cast(gdb.lookup_type("unsigned long long *"))
            else:
                root_pgdir = gdb.Value(
                    int(args[0], 10)).cast(gdb.lookup_type("unsigned long long *"))
        parse_page_table(root_pgdir, 0, 0)


class V2P(gdb.Command):

    """RISC-V SV39 MMU Paging Debugging tool.
Usage: 
    v2p add          : Get Physical address of a virtual address from pagetable at satp.
    v2p pg_addr addr : Get Physical address of a virtual address from pagetable at pg_addr.
Example:
    (gdb) v2p 0x12345678
    (gdb) v2p 0x81230000 0x12345678"""

    def __init__(self):
        super(self.__class__, self).__init__("v2p", gdb.COMMAND_USER)

    def invoke(self, args, from_tty):
        pgdir = None
        va = None
        args = gdb.string_to_argv(args)
        if len(args) == 1:
            satp = gdb.selected_frame().read_register('satp')
            satp = int(satp.cast(gdb.lookup_type("unsigned long long")))
            satp = format(satp, '064b')[::-1]
            satp_ppn = int(satp[0:44][::-1], 2)
            satp_mode = int(satp[60:64][::-1], 2)
            root_pgdir = satp_ppn * PAGE_SIZE
            if satp_mode != 8:
                print("Only support SV39 paging mode with mode 8.")
                return
            pgdir = gdb.Value(
                int(root_pgdir)).cast(gdb.lookup_type("unsigned long long *"))
            va = args[0]
        else:
            if 'x' in args[0] or 'X' in args[0]:
                pgdir = gdb.Value(
                    int(args[0], 16)).cast(gdb.lookup_type("unsigned long long *"))
            else:
                pgdir = gdb.Value(
                    int(args[0], 10)).cast(gdb.lookup_type("unsigned long long *"))
            va = args[1]
        if 'x' in va or 'X' in va:
            va = int(va, 16)
        else:
            va = int(va, 10)
        va_b = format(va, '064b')[::-1]
        va_offset = int(va_b[0:12][::-1], 2)
        va_vpn = []
        va_vpn.append(int(va_b[30:39][::-1], 2))
        va_vpn.append(int(va_b[21:30][::-1], 2))
        va_vpn.append(int(va_b[12:21][::-1], 2))
        for i in range(0, 3):
            pte = int(pgdir[va_vpn[i]])
            if pte & 0b1 == 0:
                print("Page not valid.")
                return
            if pte & 0b1110 != 0:
                pte = format(pte, '064b')[::-1]
                pte_ppn = int(pte[10:54][::-1], 2)
                type = int(pte[0:10][::-1], 2)
                print(
                    f"0x{format(va, 'X')} -> 0x{format(pte_ppn * PAGE_SIZE + va_offset, 'X')}", end='')
                print(" | ", end='')
                print_type(type)
                print()
                return
            else:
                pte = format(pte, '064b')[::-1]
                pte_ppn = int(pte[10:54][::-1], 2)
                pgdir = gdb.Value(
                    pte_ppn * PAGE_SIZE).cast(gdb.lookup_type("unsigned long long *"))


Paging()
V2P()
