# Utility to check the disassembly for sse instructions.  This uses a
# simple heuristic by checking if there are any usaged of xmm, ymm or
# zmm register.
#
# We want to build our kernel w/o sse instruction, as those first need
# to be enabled in the cpus control register as well the sse state
# needs to be initialized.

/[xyz]mm[0-9]/ {
    print "FAIL: no sse insns allowed in binary, found: "$0
    exit 1
}
