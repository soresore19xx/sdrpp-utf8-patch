#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 sdrpp-utf8-patch contributors
#
# SDR++ CJK build script — MacPorts 経由で SDR++ を fresh clone してから本リポジトリの
# CJK font + macOS IME 両パッチを適用し、ビルドして /Applications/SDR++.app に展開する。
#
# 派生元: ~/SSS_PORTS (studio 上の個人運用スクリプト)
# 違い:
#   - パッチを ~/SDRPlusPlus_PATCH から読まず、スクリプトと同梱の
#     ../sdrpp-cjk-font.patch および ../sdrpp-ime-macos.patch を直接 git apply する
#   - 失敗時に exit 1 で停止
#
# 動作環境: macOS + MacPorts (/opt/local), bash, git

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PATCH_CJK="$REPO_DIR/sdrpp-cjk-font.patch"
PATCH_IME="$REPO_DIR/sdrpp-ime-macos.patch"

for p in "$PATCH_CJK" "$PATCH_IME"; do
    if [ ! -s "$p" ]; then
        echo "ERROR: patch not found: $p" >&2
        exit 1
    fi
done

# 1. 依存パッケージ (MacPorts)
sudo port -N install pkgconfig usbutils cmake libusb fftw-3 glfw airspyhf airspy portaudio hackrf rtl-sdr bladeRF SoapyBladeRF zstd volk codec2

# 2. ~/SDRPlusPlus を fresh clone
cd ~/
rm -rf SDRPlusPlus
git clone https://github.com/AlexandreRouma/SDRPlusPlus
cd SDRPlusPlus

# 3. パッチ適用 (CJK font merge → macOS IME hook の順)
echo "Applying: $PATCH_CJK"
git apply --whitespace=nowarn "$PATCH_CJK"
echo "Applying: $PATCH_IME"
git apply --whitespace=nowarn "$PATCH_IME"

# 4. ビルド (MacPorts の cmake を明示)
mkdir build
cd build
/opt/local/bin/cmake .. \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DOPT_BUILD_SOAPY_SOURCE=OFF \
    -DOPT_BUILD_BLADERF_SOURCE=ON \
    -DOPT_BUILD_AUDIO_SOURCE=OFF \
    -DOPT_BUILD_AUDIO_SINK=OFF \
    -DOPT_BUILD_PORTAUDIO_SINK=ON \
    -DOPT_BUILD_NEW_PORTAUDIO_SINK=ON \
    -DOPT_BUILD_M17_DECODER=ON \
    -DUSE_BUNDLE_DEFAULTS=ON \
    -DOPT_BUILD_AIRSPYHF_SOURCE=ON \
    -DOPT_BUILD_PLUTOSDR_SOURCE=OFF \
    -DCMAKE_BUILD_TYPE=Release
make -j20

# 5. macOS app bundle 化
cd ..
sh make_macos_bundle.sh ./build ./SDR++.app

# 6. /Applications へ展開
rm -rf /Applications/SDR++.app
mv ./SDR++.app /Applications/

echo "Done: /Applications/SDR++.app"
