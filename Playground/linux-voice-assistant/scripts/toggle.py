#!/usr/bin/env python3
import time
import gpiod
from gpiod.line import Direction, Value

CHIP = "gpiochip0"   # <-- replace with the chip that contains GPIO27 from `gpioinfo`
LINE = 27            # BCM GPIO number

settings = gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.INACTIVE)

with gpiod.request_lines(
    CHIP,
    consumer="toggle",
    config={LINE: settings},
) as req:
    for _ in range(5):
        req.set_value(LINE, Value.ACTIVE)
        time.sleep(1)
        req.set_value(LINE, Value.INACTIVE)
        time.sleep(1)
