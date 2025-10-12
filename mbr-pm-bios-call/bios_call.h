// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

#ifndef BIOS_CALL_H
#define BIOS_CALL_H

#define EAX_OFFSET 0x0
#define EBX_OFFSET 0x4

#ifndef ASM
#include <stdint.h>

struct RegisterState {
  uint32_t eax;
  uint32_t ebx;
};

extern void bios_call(uint8_t irq, struct RegisterState* regs);

_Static_assert(__builtin_offsetof(struct RegisterState, eax) == EAX_OFFSET);
_Static_assert(__builtin_offsetof(struct RegisterState, ebx) == EBX_OFFSET);
#endif  // ASM

#endif  // BIOS_CALL_H
