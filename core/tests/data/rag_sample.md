# The Zephyr Protocol

The Zephyr Protocol is a fictional on-device data synchronization standard used in this
test corpus. It was first published in 2021 by the Meridian Working Group. The protocol
is designed for intermittent, low-bandwidth networks where devices synchronize only when
a connection becomes available.

## Core design

Zephyr splits every document into fixed-size frames of 4096 bytes. Each frame carries a
64-bit content hash so that a receiver can detect and skip frames it already holds. This
content-addressed design means the same frame is never transmitted twice, even across
different documents that happen to share content.

Synchronization uses a three-phase handshake: ADVERTISE, in which a device announces the
hashes it holds; REQUEST, in which the peer asks for the frames it is missing; and
DELIVER, in which only the missing frames are sent. The handshake is symmetric, so either
device may initiate it.

## Conflict resolution

When two devices modify the same document offline, Zephyr resolves the conflict using a
last-writer-wins rule keyed on a hybrid logical clock. The hybrid logical clock combines
a physical timestamp with a monotonic counter, which guarantees a total ordering of edits
even when device clocks drift apart.

## Security

All frames are encrypted with per-document keys derived through HKDF from a device root
key. The root key never leaves secure storage. Because frames are content-addressed before
encryption, deduplication still works across documents without exposing plaintext.

## Adoption

The reference implementation, called Breeze, is written in Rust and ships as a single
static library. Breeze became the most widely deployed Zephyr implementation by 2023,
running on more than forty million devices according to the Meridian Working Group.
