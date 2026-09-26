package misl

import "core:fmt"
import "core:slice"
import "core:time"

Helper_Timing :: struct {
	name: string,
	dur:  time.Duration,
}

Entry_Timing :: struct {
	name:         string,
	total:        time.Duration, // wall time of compile_checked_gpu_entity
	setup:        time.Duration, // debug source, bindless, type maps, helper collect
	helpers:      time.Duration, // sum of reachable helper emit
	entry:        time.Duration, // entry proc emit
	assemble:     time.Duration,
	validate:     time.Duration,
	optimize:     time.Duration,
	disassemble:  time.Duration,
	helper_count: int,
	words:        int, // after assemble, before opt
	words_opt:    int, // after spirv-opt (same as words if -o:none)
	helper_emits: []Helper_Timing,
}

Timings :: struct {
	// basic — module-scoped except spirv_*
	init:          time.Duration, // misl_init
	parse:         time.Duration,
	check:         time.Duration,
	spirv_codegen: time.Duration, // sum of all entry totals
	spirv_direct_codegen: time.Duration,
	spirv_validate:       time.Duration,
	spirv_assemble:       time.Duration,
	spirv_optimize:       time.Duration,
	spirv_disassemble:    time.Duration,

	entry_count: int,
	entries:     [dynamic]Entry_Timing,

	// more detail
	misl_init:      time.Duration,
}

session_timings_reset :: proc(session: ^Session) {
	if session == nil do return
	clear(&session.timings.entries)
	entries := session.timings.entries
	session.timings = {}
	session.timings.entries = entries
}

timings_sync_init :: proc(t: ^Timings) {
	if t == nil do return
	t.init = t.misl_init
}

timings_total :: proc(t: Timings) -> time.Duration {
	return t.init + t.parse + t.check + t.spirv_codegen
}

@(private)
Timing_Row :: struct {
	label: string,
	dur:   time.Duration,
}

@(private)
HELPER_TIMING_MIN :: time.Millisecond
@(private)
HELPER_TIMING_MAX :: 15

timings_print :: proc(t: Timings, more := false) {
	rows := make([dynamic]Timing_Row, context.temp_allocator)

	if more {
		append(&rows, Timing_Row{"misl init", t.misl_init})
	} else {
		append(&rows, Timing_Row{"initialization", t.init})
	}
	append(&rows, Timing_Row{"parse files", t.parse})
	append(&rows, Timing_Row{"type check", t.check})
	if more {
		for e in t.entries {
			append(&rows, Timing_Row{fmt.tprintf("SPIRV %s", e.name), e.total})
		}
	} else if t.spirv_codegen > 0 || t.entry_count > 0 {
		append(&rows, Timing_Row{fmt.tprintf("SPIRV codegen (% 4d entries )", t.entry_count), t.spirv_codegen})
	}

	total: time.Duration
	for r in rows {
		total += r.dur
	}
	if total <= 0 {
		total = 1
	}

	label_width := len("Total Time")
	for r in rows {
		if len(r.label) > label_width {
			label_width = len(r.label)
		}
	}
	if more {
		if 2 + len("disassemble") > label_width {
			label_width = 2 + len("disassemble")
		}
		for e in t.entries {
			for h in e.helper_emits {
				if h.dur < HELPER_TIMING_MIN do continue
				n := 2 + len("helper ") + len(h.name)
				if n > label_width {
					label_width = n
				}
			}
		}
	}

	print_row :: proc(label: string, dur: time.Duration, total: time.Duration, label_width: int) {
		ms := time.duration_milliseconds(dur)
		pct := 100.0 * f64(dur) / f64(total)
		fmt.printf("%-*s - % 9.3f ms - % 6.2f%%\n", label_width, label, ms, pct)
	}
	print_sub :: proc(label: string, dur: time.Duration, parent: time.Duration, label_width: int) {
		if dur <= 0 do return
		ms := time.duration_milliseconds(dur)
		pct := 100.0 * f64(dur) / f64(parent if parent > 0 else 1)
		fmt.printf("  %-*s - % 9.3f ms - % 6.2f%%\n", label_width - 2, label, ms, pct)
	}

	print_row("Total Time", total, total, label_width)
	ei := 0
	for r in rows {
		print_row(r.label, r.dur, total, label_width)
		if !more || ei >= len(t.entries) do continue
		want := fmt.tprintf("SPIRV %s", t.entries[ei].name)
		if r.label != want do continue
		e := t.entries[ei]
		ei += 1
		parent := e.total if e.total > 0 else 1
		print_sub("setup", e.setup, parent, label_width)
		print_sub("helpers", e.helpers, parent, label_width)
		print_sub("entry", e.entry, parent, label_width)
		print_sub("assemble", e.assemble, parent, label_width)
		print_sub("validate", e.validate, parent, label_width)
		print_sub("optimize", e.optimize, parent, label_width)
		print_sub("disassemble", e.disassemble, parent, label_width)
		if e.helper_count > 0 || e.words > 0 {
			fmt.printf("  %-*s - %d helpers, %d words", label_width - 2, "size", e.helper_count, e.words)
			if e.words_opt > 0 && e.words_opt != e.words {
				fmt.printf(" -> %d after opt", e.words_opt)
			}
			fmt.printf("\n")
		}
		ranked := slice.clone(e.helper_emits, context.temp_allocator)
		slice.sort_by(ranked, proc(a, b: Helper_Timing) -> bool { return a.dur > b.dur })
		shown := 0
		for h in ranked {
			if h.dur < HELPER_TIMING_MIN do continue
			print_sub(fmt.tprintf("helper %s", h.name), h.dur, parent, label_width)
			shown += 1
			if shown >= HELPER_TIMING_MAX do break
		}
	}
}
