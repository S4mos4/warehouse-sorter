CC ?= cc
CFLAGS ?= -std=c17 -O2 -Wall -Wextra -Wpedantic
GHDL ?= ghdl

.PHONY: all demo simulate demo-full test-c test-sim test clean

all: build/sorter-analyze

build/sorter-analyze: src/analyze_trace.c
	mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) $< $(LDFLAGS) $(LDLIBS) -o $@

demo: build/sorter-analyze
	@./build/sorter-analyze examples/demo.csv

simulate:
	mkdir -p build
	cd build && "$(GHDL)" -a --std=08 ../hdl/sorter.vhd ../hdl/tb_sorter.vhd
	cd build && "$(GHDL)" -e --std=08 tb_sorter
	cd build && "$(GHDL)" -r --std=08 tb_sorter --assert-level=error --vcd=trace.vcd

demo-full: simulate build/sorter-analyze
	@./build/sorter-analyze build/trace.csv

test-c: build/sorter-analyze
	@sh tests/analyzer.sh ./build/sorter-analyze

test-sim: simulate build/sorter-analyze
	@diff -u examples/demo.csv build/trace.csv
	@./build/sorter-analyze build/trace.csv > build/simulation-output.txt
	@diff -u examples/expected-output.txt build/simulation-output.txt
	@printf '%s\n' "Simulation trace and C report matched the expected results."

test: test-c test-sim

clean:
	rm -rf build
