class Pocl < Formula
  desc "Portable Computing Language"
  homepage "http://portablecl.org"
  url "https://github.com/pocl/pocl/archive/refs/tags/v4.0.tar.gz"
  sha256 "7f4e8ab608b3191c2b21e3f13c193f1344b40aba7738f78762f7b88f45e8ce03"
  license "MIT"
  revision 2
  head "https://github.com/pocl/pocl.git", branch: "main"

  livecheck do
    url :head
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  bottle do
    sha256 arm64_ventura:  "a889cde4e1f855f90ccc3e9afcb0839c3f2cd63ac4788c3b6ae109fdf69e3b01"
    sha256 arm64_monterey: "b102e21ee22fb6da243b672735d26d75aacceb79cb2628d5cb6897dc7709423d"
    sha256 arm64_big_sur:  "05ad886415b8c78098aec4a5511e058b86e5c4b90833e815f4f010b47723d258"
    sha256 ventura:        "31547dd88a441097ac30b5a396d293af17331df64223e5d6bc75e8bee5219c70"
    sha256 monterey:       "ebd4512a7dffd600b8a02b61fa017fe5f90c8b693785963d241dffcb224bd703"
    sha256 big_sur:        "be751028d7efa9dd39564b3a79e39a40aaa6916683cccabde37b030884a64b10"
    sha256 x86_64_linux:   "691ace09c0b0bd71a8a63cd44a201dd15d36de055cd6fca2e96aadc4eaa59426"
  end

  depends_on "cmake" => :build
  depends_on "opencl-headers" => :build
  depends_on "pkg-config" => :build
  depends_on "hwloc"
  depends_on "llvm"
  depends_on "opencl-icd-loader"
  depends_on "spirv-llvm-translator"
  uses_from_macos "python" => :build

  # Fix build with clang and a bug with CPU devices
  patch :DATA

  def install
    ENV.llvm_clang if OS.mac?
    llvm = deps.reject(&:build?).map(&:to_formula).find { |f| f.name.match?(/^llvm(@\d+(\.\d+)*)?$/) }

    # Make sure our runtime LLVM dependency is found first.
    ENV.prepend_path "PATH", llvm.opt_bin
    ENV.prepend_path "CMAKE_PREFIX_PATH", llvm.opt_prefix

    # Install the ICD into #{prefix}/etc rather than #{etc} as it contains the realpath
    # to the shared library and needs to be kept up-to-date to work with an ICD loader.
    # This relies on `brew link` automatically creating and updating #{etc} symlinks.
    args = %W[
      -DPOCL_INSTALL_ICD_VENDORDIR=#{prefix}/etc/OpenCL/vendors
      -DCMAKE_INSTALL_RPATH=#{loader_path};#{rpath(source: lib/"pocl")}
      -DENABLE_EXAMPLES=OFF
      -DENABLE_TESTS=OFF
      -DWITH_LLVM_CONFIG=#{llvm.opt_bin}/llvm-config
      -DLLVM_PREFIX=#{llvm.opt_prefix}
      -DLLVM_BINDIR=#{llvm.opt_bin}
      -DLLVM_LIBDIR=#{llvm.opt_lib}
      -DLLVM_INCLUDEDIR=#{llvm.opt_include}
      -DLLVM_SPIRV=#{Formula["spirv-llvm-translator"].opt_bin}/llvm-spirv
      -DENABLE_SLEEF=OFF
    ]
    # Avoid installing another copy of OpenCL headers on macOS
    args << "-DOPENCL_H=#{Formula["opencl-headers"].opt_include}/CL/opencl.h" if OS.mac?
    # Only x86_64 supports "distro" which allows runtime detection of SSE/AVX
    args << "-DKERNELLIB_HOST_CPU_VARIANTS=distro" if Hardware::CPU.intel?

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
    (pkgshare/"examples").install "examples/poclcc"
  end

  test do
    ENV["OCL_ICD_VENDORS"] = "#{opt_prefix}/etc/OpenCL/vendors" # Ignore any other ICD that may be installed
    cp pkgshare/"examples/poclcc/poclcc.cl", testpath
    system bin/"poclcc", "-o", "poclcc.cl.pocl", "poclcc.cl"
    assert_predicate testpath/"poclcc.cl.pocl", :exist?
    # Make sure that CMake found our OpenCL headers and didn't install a copy
    refute_predicate include/"OpenCL", :exist?
  end
end

__END__
diff --git a/lib/llvmopencl/linker.cpp b/lib/llvmopencl/linker.cpp
index 92e862c7..4c45eab9 100644
--- a/lib/llvmopencl/linker.cpp
+++ b/lib/llvmopencl/linker.cpp
@@ -61,9 +61,9 @@ IGNORE_COMPILER_WARNING("-Wunused-parameter")
 
 using namespace llvm;
 
-// #include <cstdio>
-// #define DB_PRINT(...) printf("linker:" __VA_ARGS__)
-#define DB_PRINT(...)
+ #include <cstdio>
+ //#define DB_PRINT(...) printf("linker:" __VA_ARGS__)
+#define DB_PRINT(...)
 
 namespace pocl {
 

diff --git a/bin/CMakeLists.txt b/bin/CMakeLists.txt
index 2fa37f44..f41983b1 100644
--- a/bin/CMakeLists.txt
+++ b/bin/CMakeLists.txt
@@ -28,7 +28,9 @@ set_opencl_header_includes()
 add_executable(poclcc poclcc.c)
 harden(poclcc)
 
-target_link_libraries(poclcc poclu ${OPENCL_LIBS})
+message("libs are ${OPENCL_LIBS}")
+target_link_libraries(poclcc PRIVATE poclu ${OPENCL_LIBS})
+target_link_directories(poclcc PRIVATE "${OPENCL_LIBDIR}")
 
 install(TARGETS "poclcc" RUNTIME
         DESTINATION "${POCL_INSTALL_PUBLIC_BINDIR}" COMPONENT "poclcc")
diff --git a/lib/CMakeLists.txt b/lib/CMakeLists.txt
index 2e2ddc0a..817f368a 100644
--- a/lib/CMakeLists.txt
+++ b/lib/CMakeLists.txt
@@ -78,6 +78,8 @@ else()
   set(OPENCL_LIBS "${PTHREAD_LIBRARY};${POCL_LIBRARY_NAME};${POCL_TRANSITIVE_LIBS}")
 
 endif()
+message("XXXXX OPENCL_LIBS=${OPENCL_LIBS} OPENCL_LIBDIR=${OPENCL_LIBDIR}")
+link_directories("${OPENCL_LIBDIR}")
 
 if(SANITIZER_OPTIONS)
   list(INSERT OPENCL_LIBS 0 ${SANITIZER_LIBS})

diff --git a/lib/kernel/CMakeLists.txt b/lib/kernel/CMakeLists.txt
index 2c89f458..3aea5c4c 100644
--- a/lib/kernel/CMakeLists.txt
+++ b/lib/kernel/CMakeLists.txt
@@ -29,6 +29,7 @@ acos.cl
 acosh.cl
 acospi.cl
 add_sat.cl
+addrspace_operators.ll
 all.cl
 any.cl
 as_type.cl

diff --git a/lib/CL/devices/CMakeLists.txt b/lib/CL/devices/CMakeLists.txt
index f9e0c8c9..bbcdd8d2 100644
--- a/lib/CL/devices/CMakeLists.txt
+++ b/lib/CL/devices/CMakeLists.txt
@@ -23,6 +23,9 @@
 #
 #=============================================================================
 
+set(CMAKE_CXX_STANDARD 11)
+set(CMAKE_CXX_STANDARD_REQUIRED True)
+
 if(ENABLE_LOADABLE_DRIVERS)
 
   function(add_pocl_device_library name)

