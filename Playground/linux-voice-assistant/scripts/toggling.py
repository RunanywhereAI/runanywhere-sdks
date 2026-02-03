#!/usr/bin/env python3
import time
import gpiod

CHIP = "/dev/gpiochip0"   # <-- change to the chip you proved works
LINE = 27                 # GPIO27 / physical pin 13

chip = gpiod.Chip(CHIP)
line = chip.get_line(LINE)

line.request(consumer="py-toggle", type=gpiod.LINE_REQ_DIR_OUT)

print("Toggling... Ctrl+C to stop.")
try:
    while True:
        line.set_value(1)
        time.sleep(0.5)
        line.set_value(0)
        time.sleep(0.5)
except KeyboardInterrupt:
    pass
finally:
    line.set_value(0)
    line.release()
    print("Released.")
