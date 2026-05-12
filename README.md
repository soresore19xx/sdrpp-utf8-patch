# sdrpp-utf8-patch

**macOS 向けの** [SDR++](https://github.com/AlexandreRouma/SDRPlusPlus) パッチ。CJK 文字(日本語等)を表示・入力・保存できるようにし、Frequency Manager のブックマーク名等で macOS IME による日本語の直接入力を可能にする。CJK フォントマージ部のみは Windows / Linux でもビルド可能だが、IME 連携は `__APPLE__` ガードで macOS 専用。

## 背景

SDR++ stock 環境(macOS)では Frequency Manager → Add に日本語を入れる手段がほぼ無い。同梱フォントが CJK 非対応で表示できず、GLFW backend が IME を ImGui に橋渡ししないため直接入力もできず、コピー&ペーストでも Apply 時に `?` に置換されて `frequency_manager_config.json` に保存されてしまう。

本パッチは 2 段構成でこのパイプラインを通す:

1. **CJK font merge** — ImGui の MergeMode で CJK 対応フォントを `baseFont` に統合する
2. **macOS IME hook** — `GLFWContentView` の `NSTextInputClient` メソッドを Objective-C runtime swizzle で拡張し、IME 候補ウィンドウを caret 位置へ移動、preedit を InputText 内に inline 表示、確定文字列を `io.AddInputCharactersUTF8()` で commit する

## ファイル

| ファイル | 内容 |
|---|---|
| `sdrpp-cjk-font.patch` | `core/src/gui/style.cpp` に CJK フォントマージを追加 |
| `sdrpp-ime-macos.patch` | macOS IME 連携(caret 位置補正・preedit インライン表示・確定文字列伝搬) |
| `scripts/sdr++_CJK_build.sh` | MacPorts 経由で fresh clone → パッチ適用 → ビルド → `/Applications/SDR++.app` 展開する自動化スクリプト |

## 適用手順

MacPorts が入っていれば一発:

```sh
git clone https://github.com/soresore19xx/sdrpp-utf8-patch.git
cd sdrpp-utf8-patch
./scripts/sdr++_CJK_build.sh
```

スクリプト内で `sudo port -N install ...` が走るため sudo パスワードを求められる。MacPorts 未インストールなら <https://www.macports.org/install.php>。

手動で適用したい場合は `git apply --whitespace=nowarn <patch>` で 2 パッチを当ててから SDR++ 標準のビルドフロー (cmake / make / make_macos_bundle.sh) を実行する。

## 動作確認

起動時の flog に以下が出ていれば成功:

```
[IME] macOS hook installed on GLFWContentView (firstRect=yes, insertText=yes, setMarkedText=yes, unmarkText=yes, log=off)
CJK font merged: /System/Library/Fonts/...
baseFont coverage: U+3042(あ)=yes, U+6F22(漢)=yes
```

Frequency Manager → Add でブックマーク名 InputText に focus → IME 切替 → 日本語入力。preedit が逐次表示され、Enter 確定 → Apply で保存される。

### フォント検索順

`baseFont` にマージするフォント候補(最初に見つかったものを使う):

1. `${resDir}/fonts/NotoSansJP-Regular.ttf`(bundle 同梱があれば最優先)
2. `${resDir}/fonts/NotoSansCJK-Regular.ttc`
3. macOS: ヒラギノ角ゴシック W3 / Hiragino Sans GB / AppleSDGothicNeo
4. Windows: meiryo / YuGothM / msgothic
5. Linux: NotoSansCJK (`/usr/share/fonts/{opentype,truetype}/noto/`)

### 診断ログ (`SDR_IME_LOG=1`)

タイプ内容を log に残さないため preedit/確定文字列のログは default OFF。挙動を追跡したい場合は環境変数で opt-in:

```sh
SDR_IME_LOG=1 stdbuf -oL -eL /Applications/SDR++.app/Contents/MacOS/sdrpp 2>&1 | tee /tmp/sdrpp.log
```

起動 1 行目が `log=on (SDR_IME_LOG=1)` になっていれば有効。`stdbuf -oL` は stdout block buffer 対策(無いと早期終了で末尾欠落)。

## 既知の限界

- preedit と確定文字列の見た目が同じ(native NSTextField のような下線表示はしない — ImGui に preedit 描画機構が無いため)
- preedit 中の caret 移動・選択範囲操作で削除位置がズレる可能性あり
- Windows / Linux IME は未対応(本パッチは `__APPLE__` ガードで macOS 専用)
- Variable Font は非対応(stb_truetype v1.20 制約)
- NotoSansCJKjp-Regular.otf は約 16 MB(bundle 同梱する場合はサイズに注意)

## ライセンス

GPL-3.0-or-later(SDR++ 本体が GPLv3 であるため派生物として継承)。全文は [`LICENSE`](LICENSE) を参照。新規追加ファイルおよびスクリプトには SPDX-License-Identifier を付与済。

利用を推奨する Noto Sans CJK JP は本リポジトリでは同梱せず、ビルド時に curl で取得する形なので [SIL Open Font License 1.1](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE) は配布物に影響しない。

## 参考

- [SDR++](https://github.com/AlexandreRouma/SDRPlusPlus)
- [ImGui FONTS.md](https://github.com/ocornut/imgui/blob/master/docs/FONTS.md)
- [Noto CJK](https://github.com/notofonts/noto-cjk)
