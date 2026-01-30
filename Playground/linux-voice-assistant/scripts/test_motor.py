#!/usr/bin/env python3
"""
Billy Bass Motor Test Script
-----------------------------
Tests the L298N motor driver with and without ENA GPIO control.

Wiring:
  Pi Pin 6  (GND)    -> L298N GND
  Pi Pin 11 (GPIO17) -> L298N IN1
  Pi Pin 12 (GPIO18) -> L298N ENA (jumper cap removed)
  Pi Pin 13 (GPIO27) -> L298N IN2
  Battery +          -> L298N 12V/VIN
  Battery -          -> L298N GND
  L298N OUT1         -> Motor wire 1
  L298N OUT2         -> Motor wire 2

Usage:
  python3 scripts/test_motor.py
"""

import lgpio
import time
import sys

# GPIO pin numbers (BCM numbering)
IN1 = 17  # Pi Pin 11 -> L298N IN1
ENA = 18  # Pi Pin 12 -> L298N ENA
IN2 = 27  # Pi Pin 13 -> L298N IN2

# GPIO chip for Pi 5 header pins (RP1 controller)
GPIO_CHIP = 4


def motor_stop(h):
    """Stop the motor (both LOW = coast/stop)."""
    lgpio.gpio_write(h, IN1, 0)
    lgpio.gpio_write(h, IN2, 0)


def motor_forward(h):
    """Spin motor in direction A (IN1=HIGH, IN2=LOW)."""
    lgpio.gpio_write(h, IN1, 1)
    lgpio.gpio_write(h, IN2, 0)


def motor_reverse(h):
    """Spin motor in direction B (IN1=LOW, IN2=HIGH)."""
    lgpio.gpio_write(h, IN1, 0)
    lgpio.gpio_write(h, IN2, 1)


def run_motor_tests(h, label):
    """Run the three motor tests with a label prefix."""
    # Test 1: Forward direction
    print(f"[{label} TEST 1] Motor direction A (IN1=HIGH, IN2=LOW) for 1 second...")
    motor_forward(h)
    time.sleep(1.0)
    motor_stop(h)
    print(f"[{label} STOP]  Motor stopped.")
    print()
    time.sleep(1.0)

    # Test 2: Reverse direction
    print(f"[{label} TEST 2] Motor direction B (IN1=LOW, IN2=HIGH) for 1 second...")
    motor_reverse(h)
    time.sleep(1.0)
    motor_stop(h)
    print(f"[{label} STOP]  Motor stopped.")
    print()
    time.sleep(1.0)

    # Test 3: Quick pulses (mouth flapping)
    print(f"[{label} TEST 3] Quick pulses (0.3s on, 0.3s off) x 5 — mouth movement...")
    for i in range(5):
        motor_forward(h)
        time.sleep(0.3)
        motor_stop(h)
        time.sleep(0.3)
    print(f"[{label} STOP]  Motor stopped.")
    print()


def main():
    print("=" * 50)
    print("Billy Bass Motor Test (with ENA control)")
    print("=" * 50)
    print()
    print("Wiring:")
    print("  Pi Pin 6  (GND)    -> L298N GND")
    print("  Pi Pin 11 (GPIO17) -> L298N IN1")
    print("  Pi Pin 12 (GPIO18) -> L298N ENA")
    print("  Pi Pin 13 (GPIO27) -> L298N IN2")
    print("  Battery +          -> L298N 12V/VIN")
    print("  Battery -          -> L298N GND")
    print("  L298N OUT1/OUT2    -> Motor wires")
    print()

    # Open GPIO chip
    try:
        h = lgpio.gpiochip_open(GPIO_CHIP)
    except Exception as e:
        print(f"ERROR: Cannot open GPIO chip {GPIO_CHIP}: {e}")
        print("Try running with: sudo python3 scripts/test_motor.py")
        return 1

    try:
        # Claim pins as output, initially LOW
        lgpio.gpio_claim_output(h, IN1, 0)
        lgpio.gpio_claim_output(h, IN2, 0)
        lgpio.gpio_claim_output(h, ENA, 0)
        print("[OK] GPIO17 (IN1), GPIO18 (ENA), GPIO27 (IN2) set to OUTPUT, all LOW")
        print()

        # ---- ROUND 1: WITHOUT ENA (ENA=LOW) ----
        print("=" * 50)
        print("ROUND 1: ENA = LOW (disabled via GPIO)")
        print("  Motor should NOT move.")
        print("=" * 50)
        print()
        lgpio.gpio_write(h, ENA, 0)
        run_motor_tests(h, "NO-ENA")

        time.sleep(1.0)

        # ---- ROUND 2: WITH ENA (ENA=HIGH) ----
        print("=" * 50)
        print("ROUND 2: ENA = HIGH (enabled via GPIO)")
        print("  Motor SHOULD move.")
        print("=" * 50)
        print()
        lgpio.gpio_write(h, ENA, 1)
        run_motor_tests(h, "ENA-ON")

        # Done
        lgpio.gpio_write(h, ENA, 0)
        print("=" * 50)
        print("Test complete!")
        print()
        print("Expected results:")
        print("  Round 1 (ENA LOW):  Nothing moves")
        print("  Round 2 (ENA HIGH): Motor moves in all 3 tests")
        print()
        print("If Round 2 also didn't move:")
        print("  1. Check battery switch is ON and batteries are fresh")
        print("  2. Check ENA jumper cap is REMOVED from L298N")
        print("  3. Check GPIO18 wire is on the correct ENA pin")
        print("  4. Check all screw terminals are tight")
        print("=" * 50)

    except KeyboardInterrupt:
        print("\n[INTERRUPTED] Stopping motor...")
    finally:
        motor_stop(h)
        lgpio.gpio_write(h, ENA, 0)
        lgpio.gpio_free(h, IN1)
        lgpio.gpio_free(h, IN2)
        lgpio.gpio_free(h, ENA)
        lgpio.gpiochip_close(h)
        print("[CLEANUP] GPIO released, motor stopped.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
