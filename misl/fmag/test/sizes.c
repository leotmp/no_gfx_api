#include "fmag.h"

#include <stddef.h>
#include <stdio.h>

static_assert(sizeof(FMAG_HDR) == 12, "FMAG_HDR");
static_assert(sizeof(FMAG_Word) == 4, "FMAG_Word");
static_assert(sizeof(FMAG_String) == 16, "FMAG_String");
static_assert(sizeof(FMAG_CGStream) == 16, "FMAG_CGStream");
static_assert(offsetof(FMAG_Program, stream) == 16, "FMAG_Program.stream");
static_assert(sizeof(FMAG_Program) == 32, "FMAG_Program");
static_assert(sizeof(FMAG_Allocator) == 32, "FMAG_Allocator");
static_assert(sizeof(FMAG_Arena) == 48, "FMAG_Arena");

int main(void) {
	puts("ok");
	return 0;
}
