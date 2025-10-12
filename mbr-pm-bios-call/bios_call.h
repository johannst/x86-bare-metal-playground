// SPDX-License-Identifier: MIT
//
// Copyright (c) 2025, Johannes Stoelp <dev@memzero.de>

#ifndef BIOS_CALL_H
#define BIOS_CALL_H

#define EAX_OFFSET    0x00
#define ECX_OFFSET    0x04
#define EDX_OFFSET    0x08
#define EBX_OFFSET    0x0c
#define ESP_OFFSET    0x10
#define EBP_OFFSET    0x14
#define ESI_OFFSET    0x18
#define EDI_OFFSET    0x1c
#define EFLAGS_OFFSET 0x20

#ifndef ASM
#include <stdint.h>

struct RegisterState {
  uint32_t eax;
  uint32_t ecx;
  uint32_t edx;
  uint32_t ebx;
  uint32_t esp;
  uint32_t ebp;
  uint32_t esi;
  uint32_t edi;
  uint32_t eflags;
};

extern void bios_call(uint8_t irq, struct RegisterState* regs);

_Static_assert(__builtin_offsetof(struct RegisterState, eax) == EAX_OFFSET);
_Static_assert(__builtin_offsetof(struct RegisterState, ecx) == ECX_OFFSET);
_Static_assert(__builtin_offsetof(struct RegisterState, edx) == EDX_OFFSET);
_Static_assert(__builtin_offsetof(struct RegisterState, ebx) == EBX_OFFSET);
_Static_assert(__builtin_offsetof(struct RegisterState, esp) == ESP_OFFSET);
_Static_assert(__builtin_offsetof(struct RegisterState, ebp) == EBP_OFFSET);
_Static_assert(__builtin_offsetof(struct RegisterState, esi) == ESI_OFFSET);
_Static_assert(__builtin_offsetof(struct RegisterState, edi) == EDI_OFFSET);
_Static_assert(__builtin_offsetof(struct RegisterState, eflags) == EFLAGS_OFFSET);
#endif  // ASM

#endif  // BIOS_CALL_H
