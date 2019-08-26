#!/bin/bash

echo "#####################"
echo "IT IS RECOMMENDED TO RUN THIS BUILD SCRIPT ON UBUNTU BIONIC!"
echo "#####################"
echo "If any error occurs, please refer to https://wiki.raptorcs.com/wiki/Porting/Chromium for missing dependencies or others."
echo "#####################"

set -eux

mkdir -p build/download_cache
./utils/downloads.py retrieve -c build/download_cache -i downloads.ini
./utils/downloads.py unpack -c build/download_cache -i downloads.ini -- build/src

./utils/prune_binaries.py build/src pruning.list

./utils/patches.py apply build/src patches

./utils/domain_substitution.py apply -r domain_regex.list -f domain_substitution.list -c build/domsubcache.tar.gz build/src

cd build/src

sed -i '/-static-libstdc++/d' tools/gn/build/gen.py

mkdir -p out/Default
./tools/gn/bootstrap/bootstrap.py --skip-generate-buildfiles -j$(nproc) -o out/Default/gn
PATH="${PWD}/out/Default:${PATH}"

cd third_party/libvpx
mkdir source/config/linux/ppc64
./generate_gni.sh
cd ../../

cd third_party/ffmpeg
./chromium/scripts/build_ffmpeg.py linux ppc64
./chromium/scripts/generate_gn.py
./chromium/scripts/copy_config.sh
cd ../../

cd ../

REVISION=$(grep -Po "(?<=CLANG_REVISION = ')\w+(?=')" src/tools/clang/scripts/update.py)

git clone https://github.com/llvm/llvm-project.git
git -C llvm-project checkout "${REVISION}"

mkdir -p llvm_build
cd llvm_build

LLVM_BUILD_DIR=$(pwd)

cmake -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang -DLLVM_TARGETS_TO_BUILD="PowerPC" -G "Unix Makefiles" ../llvm-project/llvm
make -j$(nproc)

cd ../
cd src

cp ../../flags.gn out/Default/args.gn

sed "s#../llvm_build#${LLVM_BUILD_DIR}#g" -i out/Default/args.gn

./out/Default/gn gen out/Default --fail-on-unused-args
ninja -C out/Default chrome chrome_sandbox chromedriver
