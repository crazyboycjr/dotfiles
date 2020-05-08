set history save on
set history size unlimited
set history filename

set print pretty
set print union
set max-value-size unlimited
#target remote :1234
#symbol-file boot/boot.elf
#b *0x7c00
#c
#file ~/misc/xv6-public/kernel
#b main
#symbol-file kern/vmaim.elf
#b master_early_init_after
#c
#b smp_startup
#c
#b test_kmalloc
#b 195
#c
#c
#thread 2
#b mpmain
#c
#x/20i $eip
#layout src
