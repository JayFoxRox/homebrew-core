class Apitrace < Formula
  desc "Tools for tracing OpenGL, Direct3D, and other graphics APIs"
  homepage "https://apitrace.github.io/"
  url "https://github.com/apitrace/apitrace/archive/00706d1a395ab6570ab88136fffb3028a3ded3bd.zip"
  version "11.1+dev.0"
  sha256 "0b51d3d6e9db9b42fc47c3ffad5b9ae68054a2a0e518f4c8c287316842c04757"
  license all_of: ["MIT", "BSD-3-Clause", "libpng-2.0", "Zlib"]

  # Known problems:
  # - libbacktrace only meant to be used for ELF support / only relevant for Linux
  # - gtest required in build-system, but unused

  depends_on "cmake" => :build
  depends_on "qt"
  depends_on "glew" => :test

  # We have one resource per submodule.. except:
  # - "frametrim/tests": Removed (unused)
  resource "thirdparty/brotli" do
    url "https://github.com/google/brotli/archive/9801a2c5d6c67c467ffad676ac301379bb877fc3.zip"
    sha256 "79edf11c219ee05fa57f5ec7b2a224d1d945679c457f4585bb834a6e2c321b8f"
    # license "MIT"
  end
  resource "thirdparty/gtest" do
    url "https://github.com/google/googletest/archive/58d77fa8070e8cec2dc1ed015d66b454c8d78850.zip"
    sha256 "ab78fa3f912d44d38b785ec011a25f26512aaedc5291f51f3807c592b506d33a"
    # license "BSD-3-Clause"
  end
  resource "thirdparty/libbacktrace" do
    url "https://github.com/ianlancetaylor/libbacktrace/archive/8602fda64e78f1f46563220f2ee9f7e70819c51d.zip"
    sha256 "900944e725051a5d0fd3b08d22c1563c73ca94817b95c79c0a081f4c621b290e"
    #license "BSD-3-Clause"
  end
  resource "thirdparty/libpng" do
    url "https://github.com/apitrace/libpng/archive/0a158f3506502dfa23edfc42790dfaed82efba17.zip"
    sha256 "c60874fc4d17cb76acbe486383b70e29d622c03f1baed049061cb8a2ed104ece"
    #license "libpng-2.0"
  end
  resource "thirdparty/snappy" do
    url "https://github.com/google/snappy/archive/2b63814b15a2aaae54b7943f0cd935892fae628f.zip"
    sha256 "f5c27f3b7099e4cb43b17f21ac78eaf009c7a7c22d38b33b9cbf679afbffc58d"
    # license "BSD-3-Clause"
  end
  resource "thirdparty/zlib" do
    url "https://github.com/madler/zlib/archive/21767c654d31d2dccdde4330529775c6c5fd5389.zip"
    sha256 "b860a877983100f28c7bcf2f3bb7abbca8833e7ce3af79edfda21358441435d3"
    # license "Zlib"
  end
  resource "thirdparty/directxmath" do
    url "https://github.com/microsoft/DirectXMath/archive/e95d84892ec894967c48151f9106bd4388e85e63.zip"
    sha256 "98e4ff2d3bd9231155e203172a826e9946953c68e949308bcf0446d8e005e17a"
    # license "MIT"
  end

  # Patch for https://github.com/apitrace/apitrace/issues/826
  # A resource instead of a patch, because we have to apply it between 2 building steps
  resource "cgltrace-patch" do
    url "https://github.com/apitrace/apitrace/commit/76d5b175da88a7267d85b9f5deb85324cb919048.diff"
    sha256 "48411ce0897a4bdf788ae5b7fe858da049ba83d921ddd12afe0a9d176afe2e1e"
    # license "MIT"
  end

  # - Disable system brotli because it's incompatible with universal macOS binary
  # - Fix a compile bug with mixed QString and QLatin1String
  patch :DATA

  def install

    # We'll build some universal library for tracing
    ENV.permit_arch_flags

    # Install all submodules
    resource("thirdparty/brotli").stage { (buildpath + 'thirdparty/brotli').install Dir["*"] }
    resource("thirdparty/gtest").stage { (buildpath + 'thirdparty/gtest').install Dir["*"] }
    resource("thirdparty/libbacktrace").stage { (buildpath + 'thirdparty/libbacktrace').install Dir["*"] }
    resource("thirdparty/libpng").stage { (buildpath + 'thirdparty/libpng').install Dir["*"] }
    resource("thirdparty/snappy").stage { (buildpath + 'thirdparty/snappy').install Dir["*"] }
    resource("thirdparty/zlib").stage { (buildpath + 'thirdparty/zlib').install Dir["*"] }
    resource("thirdparty/directxmath").stage { (buildpath + 'thirdparty/directxmath').install Dir["*"] }

    # Build the UI natively
    system "cmake", "-S", ".", "-B", "build", "-DENABLE_GUI=ON", "-DENABLE_QT6=ON", *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    # We have to rebuild some parts of apitrace with a patch for the macOS tracer
    # The patch also disables those parts which do not work, so we are only merging the improved parts with the previous install
    # We also enable universal binaries so we can trace in Rosetta apps
    resource("cgltrace-patch").stage { system "patch", "-d", buildpath, "-i", (Dir.pwd + "/76d5b175da88a7267d85b9f5deb85324cb919048.diff") }
    system "cmake", "-S", ".", "-B", "build", "-DENABLE_GUI=OFF", "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64", *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

  end

  test do
    system "#{bin}/apitrace", "trace", "glewinfo"
    system "#{bin}/glretrace", "glewinfo.trace"
    system "#{bin}/gltrim", "glewinfo.trace"
    system "#{bin}/qapitrace", "--version"
  end
end

__END__
diff --git a/CMakeLists.txt b/CMakeLists.txt
index ce8ef57c..24f736a1 100644
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -552,8 +552,8 @@ if (NOT WIN32 AND NOT ENABLE_STATIC_EXE)
 
     find_package (PkgConfig)
     if (PKG_CONFIG_FOUND)
-        pkg_check_modules (BROTLIDEC IMPORTED_TARGET libbrotlidec>=1.0.7)
-        pkg_check_modules (BROTLIENC IMPORTED_TARGET libbrotlienc>=1.0.7)
+        #pkg_check_modules (BROTLIDEC IMPORTED_TARGET libbrotlidec>=1.0.7)
+        #pkg_check_modules (BROTLIENC IMPORTED_TARGET libbrotlienc>=1.0.7)
     endif ()
 
     find_package (GTest)
diff --git a/gui/apitracecall.cpp b/gui/apitracecall.cpp
index 900057e6..6c880494 100644
--- a/gui/apitracecall.cpp
+++ b/gui/apitracecall.cpp
@@ -1097,7 +1097,8 @@ QString ApiTraceCall::searchText() const
         return m_searchText;
 
     QVector<QVariant> argValues = arguments();
-    m_searchText = m_signature->name() + QLatin1String("(");
+    m_searchText = m_signature->name();
+    m_searchText += QLatin1String("(");
     QStringList argNames = m_signature->argNames();
     for (int i = 0; i < argNames.count(); ++i) {
         m_searchText += argNames[i] +