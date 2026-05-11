# sdrpp-utf8-patch

[SDR++](https://github.com/AlexandreRouma/SDRPlusPlus) を UTF-8 clean に改修するパッチ。Frequency Manager のブックマーク名等で日本語(CJK)を表示・保存できるようにする。

## 背景

SDR++ stock のフォントは `Roboto-Medium.ttf` のみで、グリフ範囲は Basic Latin + Cyrillic だけ。`frequency_manager_config.json` には UTF-8 で日本語が正しく保存されているのに、ImGui の atlas に該当グリフが無く、画面では豆腐(`?`)で描画される。

本パッチは ImGui の MergeMode を使い、CJK 対応フォントを `baseFont` に統合して描画できるようにする。

## ファイル

| ファイル | 内容 |
|---|---|
| `sdrpp-cjk-font.patch` | `core/src/gui/style.cpp` への差分パッチ(`git apply` 形式) |
| `README.md` | このファイル |

## 適用手順

```sh
# SDR++ を clone
git clone https://github.com/AlexandreRouma/SDRPlusPlus
cd SDRPlusPlus

# パッチ適用
git apply --whitespace=nowarn /path/to/sdrpp-cjk-font.patch

# (任意) bundle 同梱フォントを配置 — 後述
mkdir -p root/res/fonts
curl -L -o root/res/fonts/NotoSansJP-Regular.ttf \
  https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf

# ビルド(macOS 例)
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DUSE_BUNDLE_DEFAULTS=ON ...
make -j$(sysctl -n hw.ncpu)
cd ..
sh make_macos_bundle.sh ./build ./SDR++.app
```

## フォント検索順

パッチ適用後、style.cpp は以下の順序で CJK フォントを探し、最初に見つかったものを `baseFont` にマージする。

1. `${resDir}/fonts/NotoSansJP-Regular.ttf` (bundle 同梱優先)
2. `${resDir}/fonts/NotoSansCJK-Regular.ttc`
3. macOS:
   - `/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc`
   - `/System/Library/Fonts/Hiragino Sans GB.ttc`
   - `/System/Library/Fonts/AppleSDGothicNeo.ttc`
4. Windows:
   - `C:/Windows/Fonts/meiryo.ttc`
   - `C:/Windows/Fonts/YuGothM.ttc`
   - `C:/Windows/Fonts/msgothic.ttc`
5. Linux:
   - `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`
   - `/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc`

`Contents/Resources/fonts/NotoSansJP-Regular.ttf`(`root/res/fonts/` 経由)を配置すれば最優先ヒットになり、OS のフォント差異の影響を受けない。

## 動作確認

起動時の flog に以下が出ていれば成功:

```
CJK font merged: /path/to/NotoSansJP-Regular.ttf
Font atlas built. baseFont glyphs: 3960, IsBuilt=1
baseFont coverage: U+3042(あ)=yes, U+6F22(漢)=yes
```

`baseFont glyphs` が ~467(Latin + Cyrillic だけ)のままなら、マージが効いていない(stb_truetype がフォントを拒否した、または OS にフォントが無い)。

## 実装ノート

- **マージ順序が重要**: ImGui の `MergeMode = true` は **直前に追加された non-merge フォント** に統合される仕様。本パッチは `baseFont` を追加した**直後**に CJK マージを行い、その後で `bigFont` / `hugeFont` を追加する。順序を逆にすると hugeFont 側に CJK が統合されてしまい、Frequency Manager の InputText(baseFont 使用)では描画されなくなる。
- **`fonts->Build()` 強制呼び出し**: 起動時にグリフ統計を取得して flog 出力するため。実害は無いが本番運用で気になれば削除可。
- **`std::filesystem::exists` チェック**: フォント候補リストを順次評価し、存在するものから順に試す。`AddFontFromFileTTF` が NULL を返した場合(stb_truetype がフォーマット拒否)は次の候補へフォールバックする。

## 既知の限界

- **IME 直接入力は不可**: macOS GLFW backend が `NSTextInputClient` の marked text / confirmed text を `glfwSetCharCallback` に橋渡ししていないため、IME 経由の文字入力が ImGui に届かない。**クリップボード貼付け(Ctrl+V / Cmd+V)経由なら日本語入力可能**。GLFW 側の patch fork または `imgui_impl_osx.mm` への切替で対応可能だが、本パッチのスコープ外。
- **Variable Font 非対応**: stb_truetype v1.20 は variable fonts(`fvar` table)を解釈しないため、`NotoSansJP[wght].ttf` のような variable 形式は static 版を使うべき。本 README の curl URL は static OTF を取得する。
- **font 容量**: NotoSansCJKjp-Regular.otf は約 16 MB。bundle サイズ重視なら別軽量 CJK フォント(IPAex Gothic 等)に置換可能。

## ライセンス

- 本パッチコード: SDR++ 本体に準ずる(GPLv3)
- 同梱を推奨する `NotoSansJP-Regular.ttf` (Noto Sans CJK JP): [SIL Open Font License 1.1](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE)

## 参考

- [SDR++ 本家リポジトリ](https://github.com/AlexandreRouma/SDRPlusPlus)
- [ImGui FONTS.md](https://github.com/ocornut/imgui/blob/master/docs/FONTS.md)
- [Noto CJK](https://github.com/notofonts/noto-cjk)
