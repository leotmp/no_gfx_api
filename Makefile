MAKEFLAGS += --no-print-directory
.PHONY: *
.NOTPARALLEL: default
examples := 1_triangle 2_textures 3_3D 4_indirect_triangles 5_compute_shaders 6_deferred_async_load 7_raytracing third_party/dear_imgui
glsl_flags :=

ifeq ($(OS),Windows_NT)
exe_extension := .exe
vs_version := 2022
else
exe_extension :=
endif

default: vercheck check_gpu build

full_build: vercheck_native build_vma build_imgui check_gpu build

# Verifies that all dependencies are installed
vercheck:
	make --version
	odin version
	slangc -v
	vulkaninfo --summary

# Verifies that all dependencies neede to build native dependencies are installed
vercheck_native: vercheck vercheck_platform
	premake5 --version
	python3 --version
	git --version

ifeq ($(OS),Windows_NT)
vercheck_platform:
	@if [ ! -f "C:/Program Files/Microsoft Visual Studio/$(vs_version)/Community/VC/Auxiliary/Build/vcvars64.bat" ]; then \
		echo "Missing visual studio $(vs_version) build tools: C:/Program Files/Microsoft Visual Studio/$(vs_version)/Community/VC/Auxiliary/Build/vcvars64.bat"; \
		exit 1; \
	fi
else
vercheck_platform:
	gcc --version
endif

clean_example:
	rm -rf examples/$(example)/shaders/*.spv
	rm -rf examples/$(example)/shaders/*.glsl

# Checks that all examples compile without errors
check:
	$(foreach example,$(examples),make check_example example=$(example);)

check_example:
	odin check examples/$(example)

# Checks that no_gfx compiles without errors
check_gpu:
	odin check gpu -no-entry-point -vet

# Builds all examples
build: compiler
	$(foreach example,$(examples),make build_example example=$(example);)

build_slang:
	$(foreach example,$(examples),make build_example_slang example=$(example);)

build_example:
	make clean_example example=$(example)
	make shaders_nosl example=$(example)
	odin build examples/$(example) -debug "-out=build/$(subst /,_,$(example))$(exe_extension)"

build_example_slang:
	make clean_example example=$(example)
	make shaders_slang example=$(example)
	odin build examples/$(example) -debug "-out=build/$(subst /,_,$(example))$(exe_extension)"

run_example:
	make clean_example example=$(example)
	make shaders_nosl example=$(example)
	odin run examples/$(example) -debug -keep-executable "-out=build/$(subst /,_,$(example))$(exe_extension)"

run_example_slang:
	make clean_example example=$(example)
	make shaders_slang example=$(example)
	odin run examples/$(example) -debug -keep-executable "-out=build/$(subst /,_,$(example))$(exe_extension)"

# Builds the gpu_compiler
compiler:
	odin build gpu_compiler -debug -out=build/gpu_compiler$(exe_extension)

# ==== Native dependencies ====

ifeq ($(OS),Windows_NT)
premake:
	powershell -NoProfile -Command "cmd /c 'call \"C:\Program Files\Microsoft Visual Studio\$(vs_version)\Community\VC\Auxiliary\Build\vcvars64.bat\" && cd $(folder) && premake5 $(arguments) vs$(vs_version) && cd build && build.bat'"
else
premake:
	cd $(folder) && premake5 $(arguments) gmake && cd build/make/linux && make config=release_x86_64
endif

build_vma:
	make premake folder=gpu/vma arguments=--vk-version=3

build_imgui:
	make premake folder=examples/third_party/dear_imgui/odin-imgui arguments=--backends=sdl3,vulkan

# ==== Shaders ====

shader_nosl:
	./build/gpu_compiler$(exe_extension) "$(shader).nosl" -out:"$(shader).spv"

# Compiles NOSL shaders for one example
shaders_nosl:
	$(foreach shader,$(wildcard examples/$(example)/shaders/*.nosl),make shader_nosl shader=$(subst .nosl,,$(shader));)

# Builds the NOSL shaders for all examples
shaders_nosl_all: compiler
	$(foreach example,$(examples),make shaders_nosl example=$(example);)

# Compiles Slang shaders for one example and validates SPIR-V output.
shaders_slang:
	@set -e; \
	dir="examples/$(example)"; \
	for slang in "$$dir"/shaders/*.slang; do \
		[ -e "$$slang" ] || continue; \
		base="$${slang%.slang}"; \
		if [ -f "$$base.vert.nosl" ]; then \
			echo "Compiling $$slang to vertex shader"; \
			slangc -target spirv -target glsl -fvk-use-c-layout -fvk-use-scalar-layout -force-glsl-scalar-layout -validate-ir -no-mangle -entry vertexMain -stage vertex "$$slang" -o "$$base.vert.spv" -o "$$base.vert.glsl"; \
			spirv-val "$$base.vert.spv" --relax-block-layout --scalar-block-layout --target-env vulkan1.3; \
		fi; \
		if [ -f "$$base.frag.nosl" ]; then \
			echo "Compiling $$slang to fragment shader"; \
			slangc -target spirv -target glsl -fvk-use-c-layout -fvk-use-scalar-layout -force-glsl-scalar-layout -validate-ir -no-mangle -entry fragmentMain -stage fragment "$$slang" -o "$$base.frag.spv" -o "$$base.frag.glsl"; \
			spirv-val "$$base.frag.spv" --relax-block-layout --scalar-block-layout --target-env vulkan1.3; \
		fi; \
		if [ -f "$$base.comp.nosl" ]; then \
			echo "Compiling $$slang to compute shader"; \
			slangc -target spirv -target glsl -fvk-use-c-layout -fvk-use-scalar-layout -force-glsl-scalar-layout -validate-ir -no-mangle -entry computeMain -stage compute "$$slang" -o "$$base.comp.spv" -o "$$base.comp.glsl"; \
			spirv-val "$$base.comp.spv" --relax-block-layout --scalar-block-layout --target-env vulkan1.3; \
		fi; \
	done

# Builds the Slang shaders for all examples
shaders_slang_all:
	$(foreach example,$(examples),make shaders_slang example=$(example);)

# ==== Individual examples ====

example1:
	make run_example example=1_triangle

example2:
	make run_example example=2_textures

example3:
	make run_example example=3_3D

example4:
	make run_example example=4_indirect_triangles

example5:
	make run_example example=5_compute_shaders

example6:
	make run_example example=6_deferred_async_load

example7:
	make run_example example=7_raytracing

example_imgui:
	make run_example example=third_party/dear_imgui