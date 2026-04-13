Firmware has a handler for each IRQ to write to GPIO

Fast IRQs (0-14) will write their number to GPIO
NMI writes 128 to GPIO
Systick writes 64 to GPIO
SW IRQ writes 32 to GPIO

main.c compiels to main.hex; it's included here for now since it shouldn't change
at some point I should automate compilation but the toolchain is a little awkward so for now I'll jut check main.hex into the repo
