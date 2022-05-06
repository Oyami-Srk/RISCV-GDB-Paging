# RISCV-GDB-Paging
**SV39** Paging Debug tool for GDB using python

Reference: [riscv-privileged-v1.10.pdf](https://riscv.org/wp-content/uploads/2017/05/riscv-privileged-v1.10.pdf)

## Usage:
Place `paging_debug.py` inside your project root.

Inside gdb console:

```(gdb) so paging_debug.py```

Then you can type `help paging` or `help v2p` to show the help message.

### Paging Table Inspector
```
> (gdb) help paging
 
RISC-V SV39 MMU Paging Debugging tool.
Usage: 
    paging           : The shortcut of `paging satp` 
    paging satp      : Show page table from satp register.
    paging addr      : Show page table at addr.
Example:
    (gdb) paging
    (gdb) paging satp
    (gdb) paging 0x12340000
```

### Virtual Address To Physical Address
```
(gdb) help v2p

RISC-V SV39 MMU Paging Debugging tool.
Usage: 
    v2p add          : Get Physical address of a virtual address from pagetable at satp.
    v2p pg_addr addr : Get Physical address of a virtual address from pagetable at pg_addr.
Example:
    (gdb) v2p 0x12345678
    (gdb) v2p 0x81230000 0x12345678

```

## Example

paging:

![paging](img/paging.png)

v2p:

![v2p](img/v2p.png)
