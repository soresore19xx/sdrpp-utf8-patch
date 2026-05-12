# sdrpp-utf8-patch

[SDR++](https://github.com/AlexandreRouma/SDRPlusPlus) を UTF-8 clean に改修するパッチ。Frequency Manager のブックマーク名等で日本語(CJK)を表示・保存・**IME 直接入力**できるようにする。

## 背景

SDR++ stock 環境(macOS)では、Frequency Manager → Add のブックマーク名フィールドに日本語を入れる手段がほぼ無い:

- **直接入力**: GLFW backend の `NSTextInputClient` 経路が ImGui まで橋渡しされておらず、IME で変換した確定文字列が InputText に届かない。さらに同 backend の `firstRectForCharacterRange:` 標準実装は ImGui の caret 位置を返さないため、IME 候補ウィンドウがアプリ左下隅に固定で出る。preedit (変換中文字列) を InputText 内に描画する経路も標準では用意されていない。
- **コピー&ペースト**: ペースト自体は通るが、Apply 時に CJK 文字は `?` に置換されて保存される(`frequency_manager_config.json` に `???????` が並ぶ)。
- **表示**: 同梱フォント `Roboto-Medium.ttf` のグリフ範囲は Basic Latin + Cyrillic が中心で CJK 文字を持たないため、仮に正しい UTF-8 文字列が InputText のバッファに入っても ImGui のフォントアトラスから該当グリフが見つからず、画面では `?` (いわゆる豆腐) として描画される。

本パッチは以下の二段構成で、上記の経路を CJK 向けに補い、直接入力 → Apply → UTF-8 保存までを通す:

1. **CJK font merge** — ImGui の MergeMode で CJK 対応フォントを `baseFont` に統合して描画する
2. **macOS IME hook** — `GLFWContentView` の `NSTextInputClient` メソッド 4 つ(`firstRectForCharacterRange:`, `insertText:replacementRange:`, `setMarkedText:selectedRange:replacementRange:`, `unmarkText`)を Objective-C runtime swizzle で拡張し、preedit を InputText 内に inline 表示しつつ、確定文字列を `io.AddInputCharactersUTF8()` で commit する

## ファイル

| ファイル | 内容 |
|---|---|
| `sdrpp-cjk-font.patch` | `core/src/gui/style.cpp` への差分(CJK フォントマージ) |
| `sdrpp-ime-macos.patch` | `core/CMakeLists.txt` + `core/backends/glfw/backend.cpp` への差分 + `core/backends/glfw/ime_macos.{h,mm}` 新規追加(macOS IME 連携: caret 位置補正・preedit インライン表示・確定文字列の伝搬) |
| `scripts/sdr++_CJK_build.sh` | MacPorts 経由で SDR++ を fresh clone → 上記 2 パッチを適用 → ビルド → `/Applications/SDR++.app` に展開する自動化スクリプト |
| `README.md` | このファイル |

## 適用手順

### A. macOS で全自動 (推奨)

MacPorts が入っていれば `scripts/sdr++_CJK_build.sh` を実行するだけで依存インストール → fresh clone → パッチ適用 → ビルド → `/Applications/SDR++.app` 展開まで完結する:

```sh
git clone https://github.com/<your-fork>/sdrpp-utf8-patch
cd sdrpp-utf8-patch
./scripts/sdr++_CJK_build.sh
```

`sudo port -N install` を実行するため sudo パスワードを求められる。

### B. 手動

```sh
# SDR++ を clone
git clone https://github.com/AlexandreRouma/SDRPlusPlus
cd SDRPlusPlus

# パッチ適用 (両方適用推奨。IME パッチは macOS 以外でもビルドできる: __APPLE__ ガード付き)
git apply --whitespace=nowarn /path/to/sdrpp-cjk-font.patch
git apply --whitespace=nowarn /path/to/sdrpp-ime-macos.patch

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
[IME] macOS hook installed on GLFWContentView (firstRect=yes, insertText=yes, setMarkedText=yes, unmarkText=yes, log=off)
CJK font merged: /path/to/NotoSansJP-Regular.ttf
Font atlas built. baseFont glyphs: 3960, IsBuilt=1
baseFont coverage: U+3042(あ)=yes, U+6F22(漢)=yes
```

`baseFont glyphs` が ~467(Latin + Cyrillic のみ)のままならマージが反映されていない可能性がある(stb_truetype がフォントフォーマットを認識できないケース、もしくは OS 側にフォントが見つからないケース)。

### IME 動作テスト

Frequency Manager の Add ダイアログで InputText に focus → かな漢字変換モードで `nihon` 入力 → スペースで変換 → Enter で確定。InputText 内に「ｎ→に→にｈ→にほ→にほｎ→日本」と変換途中の文字も逐次表示され、Enter で確定。Apply で反映される。

### 診断ログを有効化する (`SDR_IME_LOG=1`)

通常時はタイプ内容を log に残さないため、`setMarkedText:` / `insertText:` / `unmarkText` の本文ログは default では出力しない(起動時の `[IME] macOS hook installed` 1 行のみ)。挙動を細かく追跡したいときは環境変数 `SDR_IME_LOG=1` をセットして起動する:

```sh
SDR_IME_LOG=1 stdbuf -oL -eL /path/to/SDR++.app/Contents/MacOS/sdrpp 2>&1 | tee /tmp/sdrpp.log
```

起動 1 行目が `log=on (SDR_IME_LOG=1)` になっていれば診断ログが有効。`nihon` → Space → Enter の出力例:

```
[IME] setMarkedText: 'ｎ' (len=1)
[IME] setMarkedText: 'に' (len=1)
[IME] setMarkedText: 'にｈ' (len=2)
[IME] setMarkedText: 'にほ' (len=2)
[IME] setMarkedText: 'にほｎ' (len=3)
[IME] setMarkedText: '日本' (len=2)          ← Space 後の preedit
[IME] insertText: '日本' (chars=2)            ← Enter 確定
```

`stdbuf -oL -eL` は stdout block buffer のため早期終了時にログ末尾が欠落するのを防ぐ用途。

#### トラブルシュート

以下は `SDR_IME_LOG=1` を付けた状態を前提とする(default 起動では本文ログは出ない設計)。

| 現象 | 原因と対処 |
|---|---|
| `[IME] macOS hook installed` が出ない | パッチが適用されていない、または `OPT_BACKEND_GLFW=ON` でビルドされていない |
| `[IME] macOS hook installed` 行末が `log=off` のまま | `SDR_IME_LOG=1` 環境変数の設定漏れ。`SDR_IME_LOG=1 stdbuf -oL -eL .../sdrpp 2>&1 \| tee ...` の形で再起動する |
| `firstRect=no` または `insertText=no` | GLFW の `GLFWContentView` がリネーム/構造変更された可能性。GLFW バージョン確認 |
| `log=on` だが入力しても `insertText:` ログが一切出ない | accessibility 制約で keystroke が contentView に届いていない。Finder から起動した場合、macOS の InputMonitoring/Accessibility 権限を確認 |
| `setMarkedText:` は出るが `insertText:` が出ない | IME 確定操作が未完了 (preedit 表示中で確定前)。スペースで変換 → Enter で確定 |
| ASCII 入力(`'a' chars=1` 等)は出るが Japanese が出ない | IME 自体が日本語モードに切り替わっていない可能性がある。`fn` キーや Ctrl + Space で IME 切替を確認 |

## 実装ノート

### CJK font merge (`sdrpp-cjk-font.patch`)

- **マージ順序が重要**: ImGui の `MergeMode = true` は **直前に追加された non-merge フォント** に統合される仕様。本パッチは `baseFont` を追加した**直後**に CJK マージを行い、その後で `bigFont` / `hugeFont` を追加する。順序を逆にすると hugeFont 側に CJK が統合されてしまい、Frequency Manager の InputText(baseFont 使用)では描画されなくなる。
- **`fonts->Build()` 明示呼び出し**: 起動時にグリフ統計を取得して flog 出力する目的。副作用は無いが、本番運用で不要なら削除可。
- **`std::filesystem::exists` チェック**: フォント候補リストを順次評価し、存在するものから順に試す。`AddFontFromFileTTF` が NULL を返した場合(stb_truetype が当該フォーマットを扱えない場合等)は次の候補へフォールバックする。

### macOS IME hook (`sdrpp-ime-macos.patch`)

#### 前提となる挙動

1. **IME 候補ウィンドウの位置**: GLFW の `firstRectForCharacterRange:actualRange:` 標準実装は `NSMakeRect(frame.origin.x, frame.origin.y, 0, 0)` を返す。ImGui 側の caret 位置を渡す経路が無いため、IME はこの戻り値を見て候補窓をウィンドウ左下隅に配置する。
2. **preedit (変換中文字列) のインライン表示**: macOS の IME は native NSTextField 等の widget が `setMarkedText:` を介して自分で preedit を描画する設計になっている。GLFW + ImGui の組み合わせはこの描画経路を持たないため、変換中の文字列は標準では画面に現れない。
3. **確定文字列の伝搬**: 仕様上は `insertText:` → `_glfwInputChar()` → `glfwSetCharCallback` → ImGui の `io.AddInputCharacter()` で届くが、GLFW 3.4 + macOS 26 (Tahoe) の組み合わせでは `IMKCFRunLoopWakeUpReliable` の警告ログと共に CharCallback 経路で確定文字列が ImGui に到達しないケースを観測した。

#### 本パッチの実装

`NSTextInputClient` 4 メソッドを `method_setImplementation()` で拡張する:

1. **`firstRectForCharacterRange:actualRange:`** → ImGui の `SetPlatformImeDataFn` で取得した caret 位置を screen rect で返す → IME 候補窓が caret 直下に出る。
2. **`setMarkedText:selectedRange:replacementRange:`** → 直前の preedit 文字数だけ `io.AddKeyEvent(ImGuiKey_Backspace)` を発火して削除 → 新 preedit を `io.AddInputCharactersUTF8()` で挿入 → preedit が InputText 内に inline 表示される(`ｎ→に→にｈ→にほ→にほｎ→日本`)。
3. **`insertText:replacementRange:`** → 同じく直前 preedit を Backspace で削除 → 確定文字列を挿入。GLFW の `_glfwInputChar` 経路に依存せず、確定文字列を直接 ImGui に届けるため CharCallback 経路の取りこぼしも回避できる。
4. **`unmarkText`** → IME キャンセル時に preedit を Backspace で削除 → 元実装も呼ぶ(GLFW の内部 markedText state を保つため)。

#### 設計ノート

- **preedit の UTF-8 codepoint カウント**: Backspace 発火数を正確に決めるため、UTF-8 のバイト列を読んで codepoint 数を数える(`CountUtf8Codepoints`)。`NSString.length` は UTF-16 unit 数なのでサロゲートペアで誤差が出る可能性があり使わない。
- **GLFW 自体は無変更**: GLFW のソース修正や fork は不要。MacPorts/Homebrew の標準 `libglfw.3.dylib` をそのまま使う。
- **二重挿入の回避**: `insertText:` / `setMarkedText:` の元実装は呼ばない(`g_origInsertText` / `g_origSetMarkedText` は保持するが unused)。元実装が `_glfwInputChar` 経由で `io.AddInputCharacter()` を呼ぶため、両方呼ぶと二重挿入になる。
- **クラス名チェック**: `GLFWContentView` 以外の view class が contentView になっている場合(将来の GLFW 変更等)は swizzle を skip して安全にフォールバックする。
- **入力内容ログの opt-in 化**: `setMarkedText:` / `insertText:` / `unmarkText` の本文ログは default で出力しない設計にしている。stdout/log ファイルにユーザーがタイプした文字列(ブックマーク名・パスワード等、機密性のあるものも含む)が残ることを避けるため。`getenv("SDR_IME_LOG")` を `ime_macos_init()` 内で 1 回読んで `g_imeLog` に保持し、各 hook 内の `flog::info` 呼び出しを `if (g_imeLog)` でガードする。`SDR_IME_LOG` が unset・空・"0" のいずれかなら OFF。

## 既知の限界

- **preedit と確定文字列の見た目が同じ**: macOS の native NSTextField では preedit が下線付きで表示されて「これは未確定だよ」と区別されるが、本パッチは普通の文字として挿入してから Backspace で書き換えるため preedit ↔ 確定の見分けが付かない。実用上は気にならないが、長文入力時に「Enter 押し忘れ」のリスクがある。
- **preedit 中に caret 移動・選択範囲操作するとズレる**: Backspace 発火数は「直前 preedit の codepoint 数」を仮定しているため、preedit 中にカーソル移動・選択・他のキー入力等で caret 位置が動くと、Backspace 削除が意図しない文字を消す可能性がある。実用上は IME 入力中は他の操作をしないので問題になりにくい。
- **Windows / Linux IME 未対応**: 当パッチは macOS 専用(`__APPLE__` ガード)。Windows IME(WM_IME_*)・Linux fcitx/ibus は GLFW 側で別途バインドが必要。
- **Variable Font 非対応**: stb_truetype v1.20 は variable fonts(`fvar` table)を扱わないため、`NotoSansJP[wght].ttf` のような variable 形式ではなく static 版を使うのが望ましい。本 README の curl URL は static OTF を取得する。
- **font 容量**: NotoSansCJKjp-Regular.otf は約 16 MB。bundle サイズ重視なら別軽量 CJK フォント(IPAex Gothic 等)に置換可能。

## TODO

- [x] **macOS IME 直接入力対応** — `sdrpp-ime-macos.patch` で対応(GLFWContentView の NSTextInputClient 4 メソッドを swizzle、preedit を InputText 内に inline 表示 + 確定文字列を `io.AddInputCharactersUTF8()` でコミット)
- [ ] **preedit を下線表示**: 現在は preedit と確定文字列を見た目で区別していない。ImGui 自体に preedit 描画機構を追加すれば視認性が上がる(改修規模大)
- [ ] **Windows IME 対応**: GLFW Win32 backend の WM_IME_* メッセージを ImGui へ橋渡し
- [ ] **Linux IME 対応**(fcitx / ibus): GLFW X11/Wayland backend に IM module を組み込む必要あり
- [ ] **bundle font の軽量化検討**: NotoSansCJKjp-Regular.otf 16MB → IPAex Gothic / M PLUS 1 Code 等の subset で 2〜5MB 程度に圧縮
- [ ] **パッチ upstream 提案**: SDR++ 本家 (AlexandreRouma/SDRPlusPlus) への PR 化を検討

## ライセンス

- 本リポジトリの全コード(`sdrpp-cjk-font.patch` / `sdrpp-ime-macos.patch` / `scripts/sdr++_CJK_build.sh` / および patch 経由で SDR++ に追加される `core/backends/glfw/ime_macos.{h,mm}`): **GNU General Public License v3.0 or later (GPL-3.0-or-later)**。SDR++ 本体が GPLv3 であり、本パッチは SDR++ のソースを改変・拡張する派生物として同ライセンスを継承する。全文は本リポジトリ直下の [`LICENSE`](LICENSE) を参照。新規追加ファイルおよびスクリプトには SPDX-License-Identifier コメントを付与済。
- 利用を推奨する `NotoSansJP-Regular.ttf` (Noto Sans CJK JP): [SIL Open Font License 1.1](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE)。本リポジトリでは同梱せず、ビルド時に必要に応じて curl で取得する形(配布物には含まれない)。

## 参考

- [SDR++ 本家リポジトリ](https://github.com/AlexandreRouma/SDRPlusPlus)
- [ImGui FONTS.md](https://github.com/ocornut/imgui/blob/master/docs/FONTS.md)
- [Noto CJK](https://github.com/notofonts/noto-cjk)
