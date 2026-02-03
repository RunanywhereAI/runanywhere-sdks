#!/usr/bin/env python3
"""Simple L298N motor test script for Raspberry Pi.

Wiring:
  - GPIO 17 -> IN1
  - GPIO 22 -> IN2
  - ENA jumpered (full speed)
  - Motor power from Pi 5V
"""

import gpiod
import time

# GPIO pins
IN1_PIN = 17
IN2_PIN = 22

CHIP = "gpiochip0"


def main():
    chip = gpiod.Chip(CHIP)

    in1 = chip.get_line(IN1_PIN)
    in2 = chip.get_line(IN2_PIN)

    in1.request(consumer="motor", type=gpiod.LINE_REQ_DIR_OUT)
    in2.request(consumer="motor", type=gpiod.LINE_REQ_DIR_OUT)

    try:
        print("Motor forward...")
        in1.set_value(1)
        in2.set_value(0)
        time.sleep(2)

        print("Motor stop...")
        in1.set_value(0)
        in2.set_value(0)
        time.sleep(1)

        print("Motor reverse...")
        in1.set_value(0)
        in2.set_value(1)
        time.sleep(2)

        print("Motor stop...")
        in1.set_value(0)
        in2.set_value(0)

        print("Done!")

    finally:
        in1.set_value(0)
        in2.set_value(0)
        in1.release()
        in2.release()


if __name__ == "__main__":
    main()
