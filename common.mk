#########################################################################################
# set default shell for make
#########################################################################################
SHELL=/bin/bash

ifndef RISCV
$(error RISCV is unset. You must set RISCV yourself, or through the Chipyard auto-generated env file)
else
$(info Running with RISCV=$(RISCV))
endif

#########################################################################################
# specify user-interface variables
#########################################################################################
HELP_COMPILATION_VARIABLES += \
"   EXTRA_GENERATOR_REQS   = additional make requirements needed for the main generator" \
"   EXTRA_SIM_CXXFLAGS     = additional CXXFLAGS for building simulators" \
"   EXTRA_SIM_LDFLAGS      = additional LDFLAGS for building simulators" \
"   EXTRA_SIM_SOURCES      = additional simulation sources needed for simulator" \
"   EXTRA_SIM_REQS         = additional make requirements to build the simulator"

EXTRA_GENERATOR_REQS ?=
EXTRA_SIM_CXXFLAGS   ?=
EXTRA_SIM_LDFLAGS    ?=
EXTRA_SIM_SOURCES    ?=
EXTRA_SIM_REQS       ?=

#----------------------------------------------------------------------------
HELP_SIMULATION_VARIABLES += \
"   EXTRA_SIM_FLAGS        = additional runtime simulation flags (passed within +permissive)" \
"   NUMACTL                = set to '1' to wrap simulator in the appropriate numactl command"

EXTRA_SIM_FLAGS ?=
NUMACTL         ?= 0

NUMA_PREFIX = $(if $(filter $(NUMACTL),0),,$(shell $(base_dir)/scripts/numa_prefix))

#----------------------------------------------------------------------------
HELP_COMMANDS += \
"   run-binary             = run [./$(shell basename $(sim))] and log instructions to file" \
"   run-binary-fast        = run [./$(shell basename $(sim))] and don't log instructions" \
"   run-binary-debug       = run [./$(shell basename $(sim_debug))] and log instructions and waveform to files" \
"   verilog                = generate intermediate verilog files from chisel elaboration and firrtl passes" \
"   run-tests              = run all assembly and benchmark tests"

#########################################################################################
# include additional subproject make fragments
# see HELP_COMPILATION_VARIABLES
#########################################################################################
include $(base_dir)/generators/ariane/ariane.mk
include $(base_dir)/generators/tracegen/tracegen.mk
include $(base_dir)/generators/nvdla/nvdla.mk
include $(base_dir)/tools/dromajo/dromajo.mk

#########################################################################################
# Prerequisite lists
#########################################################################################
# Returns a list of files in directory $1 with file extension $2.
lookup_srcs = $(shell find -L $(1)/ -name target -prune -o -iname "*.$(2)" -print 2> /dev/null)

SOURCE_DIRS = $(addprefix $(base_dir)/,generators sims/firesim/sim tools/barstools/iocell)
SCALA_SOURCES = $(call lookup_srcs,$(SOURCE_DIRS),scala)
VLOG_SOURCES = $(call lookup_srcs,$(SOURCE_DIRS),sv) $(call lookup_srcs,$(SOURCE_DIRS),v)
# This assumes no SBT meta-build sources
SBT_SOURCE_DIRS = $(addprefix $(base_dir)/,generators sims/firesim/sim tools)
SBT_SOURCES = $(call lookup_srcs,$(SBT_SOURCE_DIRS),sbt) $(base_dir)/build.sbt $(base_dir)/project/plugins.sbt

#########################################################################################
# jar creation variables and rules
#########################################################################################
FIRRTL_JAR := $(base_dir)/lib/firrtl.jar
FIRRTL_TEST_JAR := $(base_dir)/test_lib/firrtl-test.jar

$(FIRRTL_JAR): $(call lookup_srcs,$(CHIPYARD_FIRRTL_DIR),scala)
	$(MAKE) -C $(CHIPYARD_FIRRTL_DIR) SBT="$(SBT)" root_dir=$(CHIPYARD_FIRRTL_DIR) build-scala
	mkdir -p $(@D)
	cp -p $(CHIPYARD_FIRRTL_DIR)/utils/bin/firrtl.jar $@
	touch $@

$(FIRRTL_TEST_JAR): $(call lookup_srcs,$(CHIPYARD_FIRRTL_DIR),scala)
	cd $(CHIPYARD_FIRRTL_DIR) && $(SBT) "test:assembly"
	mkdir -p $(@D)
	cp -p $(CHIPYARD_FIRRTL_DIR)/utils/bin/firrtl-test.jar $@
	touch $@

#########################################################################################
# Bloop Project Definitions
#########################################################################################
$(BLOOP_CONFIG_DIR)/TIMESTAMP: $(SBT_SOURCES)
	cd $(base_dir) && $(SBT) "project chipyardRoot" "bloopInstall"
	touch $@

#########################################################################################
# create list of simulation file inputs
#########################################################################################
$(sim_files): $(call lookup_srcs,$(base_dir)/generators/utilities/src/main/scala,scala) $(FIRRTL_JAR) $(SCALA_BUILDTOOL_DEPS)
	$(call run_scala_main,utilities,utilities.GenerateSimFiles,-td $(build_dir) -sim $(sim_name))

#########################################################################################
# create firrtl file rule and variables
#########################################################################################
.INTERMEDIATE: generator_temp
$(FIRRTL_FILE) $(ANNO_FILE): generator_temp
	@echo "" > /dev/null

# AG: must re-elaborate if ariane sources have changed... otherwise just run firrtl compile
generator_temp: $(SCALA_SOURCES) $(sim_files) $(EXTRA_GENERATOR_REQS)
	mkdir -p $(build_dir)
	$(call run_scala_main,$(SBT_PROJECT),$(GENERATOR_PACKAGE).Generator,\
		--target-dir $(build_dir) \
		--name $(long_name) \
		--top-module $(MODEL_PACKAGE).$(MODEL) \
		--legacy-configs $(CONFIG_PACKAGE):$(CONFIG))

.PHONY: firrtl
firrtl: $(FIRRTL_FILE)

#########################################################################################
# create verilog files rules and variables
#########################################################################################
REPL_SEQ_MEM = --infer-rw --repl-seq-mem -c:$(MODEL):-o:$(TOP_SMEMS_CONF)
HARNESS_CONF_FLAGS = -thconf $(HARNESS_SMEMS_CONF)

TOP_TARGETS = $(TOP_FILE) $(TOP_SMEMS_CONF) $(TOP_ANNO) $(TOP_FIR) $(sim_top_blackboxes)
HARNESS_TARGETS = $(HARNESS_FILE) $(HARNESS_SMEMS_CONF) $(HARNESS_ANNO) $(HARNESS_FIR) $(sim_harness_blackboxes)

# DOC include start: FirrtlCompiler
# NOTE: These *_temp intermediate targets will get removed in favor of make 4.3 grouped targets (&: operator)
.INTERMEDIATE: firrtl_temp
$(TOP_TARGETS) $(HARNESS_TARGETS): firrtl_temp
	@echo "" > /dev/null

firrtl_temp: $(FIRRTL_FILE) $(ANNO_FILE) $(VLOG_SOURCES)
	$(call run_scala_main,tapeout,barstools.tapeout.transforms.GenerateTopAndHarness,-o $(TOP_FILE) -tho $(HARNESS_FILE) -i $(FIRRTL_FILE) --syn-top $(TOP) --harness-top $(VLOG_MODEL) -faf $(ANNO_FILE) -tsaof $(TOP_ANNO) -tdf $(sim_top_blackboxes) -tsf $(TOP_FIR) -thaof $(HARNESS_ANNO) -hdf $(sim_harness_blackboxes) -thf $(HARNESS_FIR) $(REPL_SEQ_MEM) $(HARNESS_CONF_FLAGS) -td $(build_dir) -ll $(FIRRTL_LOGLEVEL)) && touch $(sim_top_blackboxes) $(sim_harness_blackboxes)
# DOC include end: FirrtlCompiler

# This file is for simulation only. VLSI flows should replace this file with one containing hard SRAMs
MACROCOMPILER_MODE ?= --mode synflops
.INTERMEDIATE: top_macro_temp
$(TOP_SMEMS_FILE) $(TOP_SMEMS_FIR): top_macro_temp
	@echo "" > /dev/null

top_macro_temp: $(TOP_SMEMS_CONF)
	$(call run_scala_main,barstoolsMacros,barstools.macros.MacroCompiler,-n $(TOP_SMEMS_CONF) -v $(TOP_SMEMS_FILE) -f $(TOP_SMEMS_FIR) $(MACROCOMPILER_MODE))

HARNESS_MACROCOMPILER_MODE = --mode synflops
.INTERMEDIATE: harness_macro_temp
$(HARNESS_SMEMS_FILE) $(HARNESS_SMEMS_FIR): harness_macro_temp
	@echo "" > /dev/null

harness_macro_temp: $(HARNESS_SMEMS_CONF) | top_macro_temp
	$(call run_scala_main,barstoolsMacros,barstools.macros.MacroCompiler, -n $(HARNESS_SMEMS_CONF) -v $(HARNESS_SMEMS_FILE) -f $(HARNESS_SMEMS_FIR) $(HARNESS_MACROCOMPILER_MODE))

########################################################################################
# remove duplicate files and headers in list of simulation file inputs
########################################################################################
$(sim_common_files): $(sim_files) $(sim_top_blackboxes) $(sim_harness_blackboxes)
	awk '{print $1;}' $^ | sort -u | grep -v '.*\.\(svh\|h\)$$' > $@

#########################################################################################
# helper rule to just make verilog files
#########################################################################################
.PHONY: verilog
verilog: $(sim_vsrcs)

#########################################################################################
# helper rules to run simulations
#########################################################################################
.PHONY: run-binary run-binary-fast run-binary-debug run-fast

# run normal binary with hardware-logged insn dissassembly
run-binary: $(output_dir) $(sim)
	(set -o pipefail && $(NUMA_PREFIX) $(sim) $(PERMISSIVE_ON) $(SIM_FLAGS) $(EXTRA_SIM_FLAGS) $(SEED_FLAG) $(VERBOSE_FLAGS) $(PERMISSIVE_OFF) $(BINARY) </dev/null 2> >(spike-dasm > $(sim_out_name).out) | tee $(sim_out_name).log)

# run simulator as fast as possible (no insn disassembly)
run-binary-fast: $(output_dir) $(sim)
	(set -o pipefail && $(NUMA_PREFIX) $(sim) $(PERMISSIVE_ON) $(SIM_FLAGS) $(EXTRA_SIM_FLAGS) $(SEED_FLAG) $(PERMISSIVE_OFF) $(BINARY) </dev/null | tee $(sim_out_name).log)

# run simulator with as much debug info as possible
run-binary-debug: $(output_dir) $(sim_debug)
	(set -o pipefail && $(NUMA_PREFIX) $(sim_debug) $(PERMISSIVE_ON) $(SIM_FLAGS) $(EXTRA_SIM_FLAGS) $(SEED_FLAG) $(VERBOSE_FLAGS) $(WAVEFORM_FLAG) $(PERMISSIVE_OFF) $(BINARY) </dev/null 2> >(spike-dasm > $(sim_out_name).out) | tee $(sim_out_name).log)

run-fast: run-asm-tests-fast run-bmark-tests-fast

#########################################################################################
# helper rules to run simulator with fast loadmem via hex files
#########################################################################################
$(binary_hex): $(output_dir) $(BINARY)
	$(base_dir)/scripts/smartelf2hex.sh $(BINARY) > $(binary_hex)

run-binary-hex: $(output_dir) $(sim) $(binary_hex)
run-binary-hex: run-binary
run-binary-hex: override LOADMEM_ADDR = 80000000
run-binary-hex: override LOADMEM = $(binary_hex)
run-binary-hex: override SIM_FLAGS += +loadmem=$(LOADMEM) +loadmem_addr=$(LOADMEM_ADDR)
run-binary-debug-hex: $(output_dir) $(sim) $(binary_hex)
run-binary-debug-hex: run-binary-debug
run-binary-debug-hex: override LOADMEM_ADDR = 80000000
run-binary-debug-hex: override LOADMEM = $(binary_hex)
run-binary-debug-hex: override SIM_FLAGS += +loadmem=$(LOADMEM) +loadmem_addr=$(LOADMEM_ADDR)
run-binary-fast-hex: $(output_dir) $(sim) $(binary_hex)
run-binary-fast-hex: run-binary-fast
run-binary-fast-hex: override LOADMEM_ADDR = 80000000
run-binary-fast-hex: override LOADMEM = $(binary_hex)
run-binary-fast-hex: override SIM_FLAGS += +loadmem=$(LOADMEM) +loadmem_addr=$(LOADMEM_ADDR)

#########################################################################################
# run assembly/benchmarks rules
#########################################################################################
$(output_dir):
	mkdir -p $@

$(output_dir)/%: $(RISCV)/riscv64-unknown-elf/share/riscv-tests/isa/% $(output_dir)
	ln -sf $< $@

$(output_dir)/%.run: $(output_dir)/% $(sim)
	(set -o pipefail && $(NUMA_PREFIX) $(sim) $(PERMISSIVE_ON) $(SIM_FLAGS) $(EXTRA_SIM_FLAGS) $(SEED_FLAG) $(PERMISSIVE_OFF) $< </dev/null | tee $<.log) && touch $@

$(output_dir)/%.out: $(output_dir)/% $(sim)
	(set -o pipefail && $(NUMA_PREFIX) $(sim) $(PERMISSIVE_ON) $(SIM_FLAGS) $(EXTRA_SIM_FLAGS) $(SEED_FLAG) $(VERBOSE_FLAGS) $(PERMISSIVE_OFF) $< </dev/null 2> >(spike-dasm > $@) | tee $<.log)

#########################################################################################
# include build/project specific makefrags made from the generator
#########################################################################################
ifneq ($(filter run% %.run %.out %.vpd %.vcd,$(MAKECMDGOALS)),)
-include $(build_dir)/$(long_name).d
endif

#######################################
# Rules for building DRAMSim2 library #
#######################################

dramsim_dir = $(base_dir)/tools/DRAMSim2
dramsim_lib = $(dramsim_dir)/libdramsim.a

$(dramsim_lib):
	$(MAKE) -C $(dramsim_dir) $(notdir $@)

#########################################################################################
# print help text
#########################################################################################
.PHONY: help
help:
	@for line in $(HELP_LINES); do echo "$$line"; done

#########################################################################################
# Implicit rule handling
#########################################################################################
# Disable all suffix rules to improve Make performance on systems running older
# versions of Make
.SUFFIXES:
