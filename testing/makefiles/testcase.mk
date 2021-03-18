mkfile_dir 	:= $(dir $(lastword ${MAKEFILE_LIST}))
top_dir         := $(abspath $(mkfile_dir)../..)

include $(mkfile_dir)/shared.mk

build_dir := ${top_dir}/_build/${testcase}

LIB_DIR := ${build_dir}/lib
OBJ_DIR := ${build_dir}/obj
BIN_DIR	:= ${build_dir}/bin

COMMON_LIB_DIR	:= ${top_dir}/_build/lib

include $(top_dir)/etc/makefiles/arduino-cli.mk

ifneq ($(KALEIDOSCOPE_CCACHE),)
COMPILER_WRAPPER := ccache
endif


SRC_DIR	:= test

SKETCH_FILE=$(wildcard *.ino)
BIN_FILE=$(subst .ino,,$(SKETCH_FILE))
LIB_FILE=${BIN_FILE}-latest.a

TEST_FILES=$(sort $(wildcard $(SRC_DIR)/*.cpp))

# If we have a ktest file and no generated testcase, 
# we want to turn it into a generated testcase
# and add it to the list of possible test files

ifneq (,$(wildcard test.ktest))
HAS_KTEST_FILE=1
ifeq (,$(findstring $(SRC_DIR)/generated-testcase.cpp, $(TEST_FILES)))
TEST_FILES += $(SRC_DIR)/generated-testcase.cpp
endif
endif

.DEFAULT_GOAL := build

TEST_OBJS=$(patsubst $(SRC_DIR)/%.cpp,${OBJ_DIR}/%.o,$(TEST_FILES))

build: ${BIN_DIR}/${BIN_FILE} compile-sketch

all: run

run: ${BIN_DIR}/${BIN_FILE}
	$(QUIET) "${BIN_DIR}/${BIN_FILE}" -t -q

${BIN_DIR}/${BIN_FILE}: ${TEST_OBJS} 

# We force sketch recompiliation because otherwise, make won't pick up changes to...anything on the arduino side
compile-sketch: ${TEST_OBJS}
	@install -d "${BIN_DIR}" "${LIB_DIR}"
	$(QUIET) env LIBONLY=yes VERBOSE=${VERBOSE}  \
		OUTPUT_PATH="${LIB_DIR}" \
		$(MAKE) -f ${top_dir}/testing/makefiles/delegate.mk compile
	$(QUIET) $(COMPILER_WRAPPER) $(call _arduino_prop,compiler.cpp.cmd) -o "${BIN_DIR}/${BIN_FILE}" \
		-lpthread -g -w ${TEST_OBJS} \
		-L"${COMMON_LIB_DIR}" -lcommon \
		"${LIB_DIR}/${LIB_FILE}" \
		-L"${top_dir}/testing/googletest/build/lib" \
		-lgtest -lgmock -lpthread -lm


# If we have a test.ktest file, it should be processed into a c++ testcase

generate-testcase: $(if $(HAS_KTEST_FILE), ${SRC_DIR}/generated-testcase.cpp)


${SRC_DIR}/generated-testcase.cpp: test.ktest
ifneq (,$(wildcard test.ktest))
	$(info Compiling ${testcase} ktest script into ${SRC_DIR}/generated-testcase.cpp)
	$(QUIET) install -d "${SRC_DIR}"
	$(QUIET) perl ${top_dir}/testing/bin/ktest-to-cxx \
		--ktest=test.ktest \
		--cxx=${SRC_DIR}/generated-testcase.cpp
endif

${OBJ_DIR}/%.o: ${SRC_DIR}/%.cpp
	$(QUIET) install -d "${OBJ_DIR}"
	$(QUIET) $(COMPILER_WRAPPER) $(call _arduino_prop,compiler.cpp.cmd) -o "$@" -c -std=c++14 \
		${shared_includes} ${shared_defines} $<

clean:
	$(QUIET) rm -f -- "${SRC_DIR}/generated-testcase.cpp"
	$(QUIET) rm -rf -- "${build_dir}"

.PHONY: clean run all build
