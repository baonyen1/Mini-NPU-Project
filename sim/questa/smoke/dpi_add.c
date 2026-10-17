/* S2: DPI-C smoke. Built as a DLL with gcc and loaded with vsim -sv_lib. */
#include "svdpi.h"
int c_add(int a, int b) { return a + b; }
/* A packed vector cannot be a DPI return value in Questa: pass it by pointer. */
void c_xor32(const svBitVecVal *a, const svBitVecVal *b, svBitVecVal *r) { *r = *a ^ *b; }
