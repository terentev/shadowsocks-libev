#!/usr/bin/env bash
# Run with the Ubuntu 26.04 shadowsocks-libev build dependencies and libbloom v2.0
# (57b35ea256b803b5fa6cd7cd2a2c36ecff9109c9) checked out separately.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 LIBBLOOM_V2_SOURCE OUTPUT_FILE" >&2
    exit 2
fi

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
bloom_source=$(realpath -- "$1")
output=$(realpath -m -- "$2")
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

mkdir -p "$scratch/server" "$scratch/bloom"
tar --exclude=./.git --exclude=./bin -C "$repo" -cf - . | tar -C "$scratch/server" -xf -
cp -- "$bloom_source/bloom.c" "$bloom_source/bloom.h" "$scratch/bloom/"
cp -- "$bloom_source/murmur2/MurmurHash2.c" "$bloom_source/murmur2/murmurhash2.h" "$scratch/bloom/"
(
    cd "$scratch/bloom"
    sha256sum -c --status <<'CHECKSUMS'
15ee8ab6f997729b3f9087ee789041f86bc0bd058069d14a673ab4d28ac2de73  bloom.c
d50a3470fc5dcf439ab4ccb18e435e7ac93881f2eeea38499886885119f936d2  bloom.h
917efef6dc4833172679f88c1014e8054aecf5276d7885bcab4d4c167be32ca4  MurmurHash2.c
af204df2a5b6ef67b5d24c28ac2bfd014599fd0c69b2f05a75900ee94af1ca3b  murmurhash2.h
CHECKSUMS
    patch -p1 --fuzz=0 < "$repo/build/libbloom-2.0-add.patch"
    cc -O2 -g -fno-omit-frame-pointer -fno-strict-aliasing -fPIC \
        -DBLOOM_VERSION_MAJOR=2 -DBLOOM_VERSION_MINOR=0 -c bloom.c MurmurHash2.c
    ar rcs libbloom.a bloom.o MurmurHash2.o
)

cd "$scratch/server"
for directory in libcork libipset libbloom; do
    mkdir -p "$directory"
    touch "$directory/Makefile.in"
done
autoreconf -fi
CPPFLAGS="-I$scratch/bloom" LDFLAGS="-L$scratch/bloom" \
    CFLAGS="-O2 -g -fno-omit-frame-pointer" \
    ./configure --enable-system-shared-lib --enable-shared --disable-documentation
make -C src -j4 ss-server
install -D -m 0755 src/ss-server "$output"
