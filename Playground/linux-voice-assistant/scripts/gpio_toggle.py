#!/usr/bin/env python3
"""Toggle GPIO 13 every second."""

import gpiod
import time

CHIP = "gpiochip0"
PIN = 13

chip = gpiod.Chip(CHIP)
line = chip.get_line(PIN)
line.request(consumer="toggle", type=gpiod.LINE_REQ_DIR_OUT)

try:
    for i in range(5):
        print(f"ON")
        line.set_value(1)
        time.sleep(1)
        print(f"OFF")
        line.set_value(0)
        time.sleep(1)
finally:
    line.set_value(0)
    line.release()

print("Done")
