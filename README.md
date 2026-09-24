# Lyrics Filler 自动填词

MuseScore Studio 4.x 的自动填词插件：从系统剪贴板读取歌词，按语言规则切成"音节单元"，
再顺序填入指定声部的音符下方。中文支持一字一音，英文支持连字符分音节，
连音线（Tie）与延音线（Slur）段落只在第一个音上填词，实现一字多音。

---

## 目录

- [功能](#功能)
- [环境要求](#环境要求)
- [安装](#安装)
- [使用](#使用)
- [分词规则](#分词规则)
- [连音线与延音线](#连音线与延音线)
- [选项说明](#选项说明)
- [示例](#示例)
- [故障排查](#故障排查)
- [开发与测试](#开发与测试)
- [已知限制](#已知限制)
- [许可](#许可)

---

## 功能

| 能力 | 说明 |
| --- | --- |
| 剪贴板读取 | 打开插件时自动读取系统剪贴板，也可手动粘贴或点"重新读取剪贴板" |
| 中文分词 | 默认一个汉字（含假名）对应一个音符，空白自动丢弃 |
| 标点跟随 | 标点不占音符，而是自动贴在前一个字上（`霜。`），词首引号则贴到下一个字前（`“你`） |
| 英文分词 | 空格分词，词内 `-` 视为音节边界，自动设置 MuseScore 的 syllabic 使连字符正确显示 |
| 方括号合并 | `[测试]` / `[test word]` 内的内容整体作为一个音节单元，只占一个音符 |
| 一字多音 | 连音线、延音线覆盖的后续音符留空，只在首音填词；可选为整段画延长线 |
| 范围控制 | 只填当前选区，或整条声部；可指定谱表、声部、歌词段落（verse） |
| 安全 | 全部改动包在一个撤销命令里，出错自动回滚，成功后可 Ctrl+Z 一次撤销 |

---

## 环境要求

- **MuseScore Studio 4.x**。在 **4.7.5** 上开发验证。
- "延音线（Slur）只填首音"从谱面级的 `curScore.spanners` 读取延音线区间。
  4.x 早期版本未实测；若读不到延音线，插件会退回"只识别连音线（Tie）"并在状态栏提示。
- 测试脚本需要 Node.js（可选，仅开发时使用）。

---

## 安装

### 方式一：下载发布包（最简单）

到仓库的 **Releases** 页下载 `LyricsFiller-vX.Y.Z.zip`，解压后把
**`LyricsFiller` 整个文件夹**放进 MuseScore 的用户插件目录（见下表），重启 MuseScore。

### 方式二：脚本

Windows 双击 `install.bat`（或在终端执行）；macOS / Linux：

```bash
./install.sh
```

脚本会把 `LyricsFiller/` 整个目录复制到默认用户插件目录：

```
Windows   <文档>\MuseScore4\Plugins\LyricsFiller
macOS     ~/Documents/MuseScore4/Plugins/LyricsFiller
Linux     ~/Documents/MuseScore4/Plugins/LyricsFiller
```

Windows 上的"文档"经常被重定向（OneDrive，或者整个搬到别的盘），
这时 `%USERPROFILE%\Documents` 并不是 MuseScore 真正读取的目录。
`install.bat` 因此会先查注册表里的 `User Shell Folders\Personal` 拿到真实路径，
脚本运行时会把 **Target** 打印出来，请以它为准。也可以直接指定目标：

```bash
./install.sh "D:/Music/MuseScore4/Plugins"      # macOS / Linux
install.bat "D:\Music\MuseScore4\Plugins"       # Windows
```

> `install.bat` 刻意写成纯 ASCII + 英文输出：cmd.exe 按字节偏移读脚本，
> 文件里出现多字节字符会让它把后续行切错位置，`echo` / `REM` 的尾巴会被当成命令执行。
> 中文说明放在这里，`install.sh` 则保留中文输出。

### 确认安装成功

重启后在菜单 **插件 → 歌词 → Lyrics Filler 自动填词** 应该能看到它；
或在 **插件 → 管理插件** 里搜索名字。

> MuseScore 不用清单文件，它靠**逐行文本解析** `.qml` 头部的
> `title` / `description` / `pluginType` / `categoryCode` / `thumbnailName` /
> `requiresScore` / `version` 这 7 个属性来识别插件。
> 缺任何一个，插件都不会出现在列表里。修改头部时请保留这 7 行，
> 且它们必须都出现在第一个内层代码块（如 `Item {`）之前。

---

## 使用

1. 复制歌词到剪贴板（Word、网页、记事本里复制的纯文本都可以）。
2. 在乐谱里**选中要填词的那一行**（拖选一个区间，或点谱表左侧选中整条谱表）。
   不选也可以，插件默认按整个谱表处理。
3. 菜单 **插件 → 歌词 → Lyrics Filler 自动填词**。歌词文本会自动出现在输入框里。
4. 点 **统计**：确认"音节单元数"和"音符数"是否对得上。
5. 点 **应用** 写入。结果不满意直接 **Ctrl+Z** 撤销。

第二段歌词：把新歌词复制到剪贴板 → 重新打开插件 → 把"第几段歌词"改成 2 → 应用。

---

## 分词规则

### 中文 / 一字一音（默认）

| 输入 | 结果（每个 → 一个音符） |
| --- | --- |
| `床前明月光` | 床 / 前 / 明 / 月 / 光 |
| `床前明月光，` | 床 / 前 / 明 / 月 / `光，`（逗号跟着"光"走，仍 5 个单元） |
| `床前 明月\n光` | 空白与换行都不占音符 |
| `[测试]你好` | `测试`（1 个音符）/ 你 / 好 |
| `唱la la吧` | 唱 / `la` / `la` / 吧（夹带的英文按词聚合） |

- 汉字范围：CJK 统一表意文字（含扩展 A）、兼容表意文字、平假名、片假名。
- 方括号内的内容会**原样保留**（只把连续空白压成一个空格），可以放标点。

### 英文

| 输入 | 结果 |
| --- | --- |
| `Silence is golden` | Silence / is / golden（三个音符，均无连字符） |
| `re-action` | `re` + `action`，MuseScore 自动在 `re` 后画连字符 |
| `in-com-pre-hen-si-ble` | 6 个音符 |
| `Si - lence` / `re- action` / `ev-\nery` | 连字符两侧的空格和换行不影响拆分 |
| `sing [test word] now` | sing / `test word`（1 个音符）/ now |
| `Singin' in the "rain"` | Singin' / in / the / `"rain"`（撇号与引号都保留） |
| `Hello — world` | `Hello—` / world（破折号贴到前一个词，不占音符） |

关于连字符的关键点：**写入时会去掉 `-`**，改用 MuseScore 的 `syllabic`
（begin / middle / end / single）属性。这样排版时连字符由软件自己画，
位置、字体、换行都跟原生歌词一致；手动把 `-` 留在文本里会出现双连字符。

### 标点符号

标点**不占音符**，但不会被丢掉，而是自动贴到相邻的歌词上：

| 情况 | 归属 | 例子 |
| --- | --- | --- |
| 字后面的标点 | 贴回前一个字 | `霜。` → 一个音符显示 `霜。` |
| 连续多个标点 | 全部并到前一个字 | `了！??` → 一个音符 |
| 词前的引号/括号 | 贴到下一个字前面 | `“你好”` → `“你` + `好”` |
| 方括号单元后面 | 贴到该单元末尾 | `[la la]吧！` → `la la` + `吧！` |

因为标点不产生新单元，**加不加标点，音节数完全一致**，不会影响与音符的对位
（有测试专门钉住这条不变量）。

唯一的例外是连字符 `-`：它是英文的音节边界标记，也常被当作"延长"的手写符号，
贴进歌词会被误当成文字，所以永远丢弃。想要延长线请用"为连音段画延长线"选项。

另一个细节：`go-!` 这种"连字符后紧跟标点"的写法，逗号/感叹号意味着词已经结束，
所以该音节的 `syllabic` 会从 begin 降级为 single，MuseScore 不会再往后画连字符。

### 语言自动识别

统计文本里 CJK 字符数与拉丁字母数，谁多用谁的语言规则；平局按中文。
识别结果会显示在状态栏，判断不对时手动改成"中文"或"English"即可。

---

## 连音线与延音线

- **连音线（Tie）**：同音高相连。检测 `Note.tieBack`，凡是有向后进线的音符一律留空。
- **延音线（Slur）**：从 `curScore.spanners` 里挑出所有 Slur，用
  `spannerTick` / `spannerTicks` 划出 tick 区间，落在区间内（不含首音、含结束音）
  的音符全部留空。

两者都只在"首音"上消耗一个音节，实现**一字多音**。

勾选"为连音段画延长线"后，首音歌词会带上 `lyricTicks`，
长度等于整段 melisma 的时值，MuseScore 会画出下面这条延长线：

```
床 ——————————————————
```

> **音乐学上的提醒**：slur（连奏线）在常规记谱里只是"连贯地唱"，
> 每个音通常各自有歌词；把 slur 当 melisma 处理并不通用。
> 所以这里做成了开关（默认按任务要求开启）。
> 若你的谱子里 slur 只是连奏标记，请取消勾选"延音线只填首音"。

装饰音（倚音、颤音等 `noteType != NORMAL`）不占歌词，会被跳过并在状态栏提示数量。
休止符同样不消耗音节。

---

## 选项说明

| 选项 | 默认 | 作用 |
| --- | --- | --- |
| 语言 | 自动识别 | 强制按中文或英文规则分词 |
| 第几段歌词 | 1 | 写入的 verse 编号，多段歌词逐段填 |
| 谱表 / 声部 | 跟随选区 | 目标轨道；打开插件时会用当前选区预填 |
| 只填选区 | 开（有选区时） | 关掉了就处理整条声部 |
| 连音线只填首音 | 开 | 关掉后 tie 的每个音都各自吃一个音节 |
| 延音线只填首音 | 开 | 见上一节 |
| 为连音段画延长线 | 关 | 在首音歌词上加 extender |
| 已有歌词 | 覆盖 | "跳过该音符"会保留原歌词不动 |
| 位置 | 自动 | 只在选"上方/下方"时才写 `placement`，否则用软件默认 |
| 数量不一致时不应用 | 关 | 开启后音节数与音符数不等就直接中止 |

---

## 示例

**中文**：6 个音符，其中第 3 个音与第 4 个音由连音线相连（同音高延续），
所以真正能填歌词的位置只有 5 个。

```
[测试]床前明月
```

分词结果是 `测试`、`床`、`前`、`明`、`月` 共 5 个单元，正好对上 5 个可填音符：

| 音符 | 1 | 2 | 3 | 4 | 5 | 6 |
| --- | --- | --- | --- | --- | --- | --- |
| 与下一音 | | | Tie → | | | |
| 歌词 | 测试 | 床 | 前 | *（留空）* | 明 | 月 |

**英文**：4 个音符，无连音线。

```
re-action [test word] go
```

| 音符 | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- |
| 写入文本 | `re` | `action` | `test word` | `go` |
| syllabic | begin | end | single | single |
| 谱面显示 | re- | action | test word | go |

第 1、2 个音之间由 MuseScore 自动补出连字符，看起来就是 `re-action`；
文本里并不包含 `-`，所以换行、改字体时连字符位置始终正确。

---

## 故障排查

**菜单里找不到插件**
- 确认复制的是 `LyricsFiller` **文件夹**，路径形如 `.../Plugins/LyricsFiller/lyricsfiller.qml`。
- 检查 **编辑 → 偏好设置 → 扩展** 里的"我的插件"目录，必须是那个目录，不是 `Documents\MuseScore4\Plugins` 之外的别处。
- 需要完全退出 MuseScore 再打开。

**提示"剪贴板是空的或不含文本"**
- 有些来源（图片、富文本）不含纯文本。直接把歌词粘贴到输入框即可，效果相同。
- Linux 下部分剪贴板管理器需要 `wl-clipboard` / X11 支持。

**填出来的位置不对 / 填到了别的声部**
- 多声部谱表要先在"声部"里选对（1–4 对应 Voice 1–4）。
- 用"统计"先看音节数与音符数，两者接近说明目标轨道找对了。

**音节比音符多/少**
- 状态栏会给出确切差值。少音符就删歌词，少音符则检查是否被 slur 选项吃掉。
- 需要严格对齐时勾上"数量不一致时不应用"。

**想改回原来的样子**
- 一次 **Ctrl+Z** 即可撤销整批改动（所有写入都在同一个撤销命令内）。

---

## 开发与测试

```bash
npm test
# 等价于：node --test "tests/*.test.mjs"
```

> 引号不能省。glob 交给 Node 自己展开，Windows 的 cmd 和 CI 的 bash 行为才一致；
> 写成 `node --test tests/` 在 Node 24 上会被当成模块路径而报 MODULE_NOT_FOUND。

测试不依赖 MuseScore，分四块：

- `tests/tokenizer.test.mjs` — 从 `lyricsfiller.qml` 里
  `TOKENIZER-BEGIN/END` 之间**原样截取**分词代码来跑，保证测的就是插件真正会执行的代码。
- `tests/plugin-format.test.mjs` — 复刻 MuseScore 的插件头部文本解析器，
  校验 7 个必需元数据能否被识别、缩略图是否存在、括号是否配平。
- `tests/qml-references.test.mjs` — 检查控件 id 唯一、被引用，成员访问的基名都有定义，
  以及每个 `CheckBox` 都带 `onClicked: checked = !checked`。
- `tests/install-script.test.mjs` — 钉住 `install.bat` 必须是纯 ASCII + CRLF + 无 BOM，
  以及 `install.sh` 的路径校验要在 `mkdir` 之前。

分词/排布逻辑全部放在 `buildTokenizer()` 这一个纯函数里，不引用任何 MuseScore 对象；
需要 Qt 环境的部分（遍历音符、读写歌词元素）都在它外面。想扩展规则只改这个函数，
然后 `npm test` 就能验证。

### 发版（自动生成 GitHub Release）

发布是**打标签驱动**的，不需要本地装 `gh`，也不依赖任何第三方 Action
（用的是 runner 自带的 `gh` CLI）：

```bash
npm test                                   # 先确认全绿
git commit -am "..." && git push
git tag v1.0.1 && git push origin v1.0.1   # 这一推就会触发发布
```

`.github/workflows/release.yml` 收到 `v*` 标签后依次：跑测试 → 校验
标签版本号与 `package.json` / 插件 `version` 一致 → 把 `LyricsFiller/` 压成
`LyricsFiller-v1.0.1.zip` → 创建 Release 并挂上 zip 和单个 `lyricsfiller.qml`。

想改发布说明或补附件，可以在 Actions 页手动运行 **release** workflow
（workflow_dispatch），填同一个 tag 即可，脚本会走"已存在则更新"分支，
不会重复创建 Release。

发版前必须知道的三件事：

- 版本号有三处：git 标签 `v1.0.1`、`package.json` 的 `version`、
  `lyricsfiller.qml` 头部的 `version`。三者必须一致，测试会拦住不一致的情况。
- 标签一旦推上去就是公开状态，删标签不会自动删 Release，需要去 Releases 页一起删。
- 需要仓库 Settings → Actions → General 里 "Workflow permissions" 至少为
  **Read and write**（默认值通常已是），否则 `gh release create` 会 403。

### 在 4.7.5 上开发时必须知道的几件事


这些是实测踩出来的，源码里看不出来：

- **`onRun:` 不能用在 dialog 插件上。** 写 `onRun: { … }` 会让 QML 直接报
  `Cannot assign to non-existent property "onRun"` 并中止加载，插件窗口根本不出现。
  本插件改用根对象的 `Component.onCompleted`，对话框打开时同样触发。
- **不要给函数/属性起根类型的保留名。** 根类型自带 `run` 信号，
  自己再写 `function run()` 会报 `Duplicate method name`，并且连带让 `onRun` 无法生成。
  同类保留名还有 `quit` `cmd` `newElement` `fraction` `division` `curScore` 等，
  完整清单见 `tests/qml-references.test.mjs` 里的 `RESERVED`。
- **加载失败时 MuseScore 只会弹一个全空白窗口。** 它想显示的
  `qrc:/qml/Muse/Extensions/ExtensionErrorMessage.qml` 在 4.7.5 安装包里缺失，
  日志里对应一条 `No such file or directory`。所以"窗口是空的"就等于"加载失败"，
  真正的原因要去日志里看。
- **不要在异常对话框上按 Escape。** 实测会触发 MuseScore 自身的断言
  （`InteractiveProvider::onClose ASSERT FAILED`，interactiveprovider.cpp:828）并让整个程序退出。
- **看日志是唯一可靠的诊断手段**：
  `%LOCALAPPDATA%\MuseScore\MuseScore4\logs\MuseScore_*.log`，
  搜 `ExtensionBuilder::load`（加载失败）、`Qt |`（QML 运行时报错）、
  `ActionsDispatcher::doDispatch`（动作是否被触发）。
- **插件里的 `console.log` 不进日志文件。** 想打印东西只能写到界面上的文本控件，
  截图读回来。
- **`Muse.UiComponents` 的 `CheckBox` 点击时不会自己翻转。** 它是一个自定义
  `FocusScope`，`checked` 只是普通属性，`onClicked` 只负责发 `clicked()` 信号。
  必须显式写 `onClicked: checked = !checked`，否则界面上看得到却点不动。
  （`ComboBox` / `SpinBox` 来自 `QtQuick.Controls`，没这个问题。）
- **tick 基准是 960/四分音符、3840/全音符**，不是历史上常用的 1440/5760。
  实测十六分=240、八分=480、四分=960、二分=1920。
  自己 `fraction(ticks, 5760)` 会算出错两倍的时值，优先用 `fractionFromTicks()`。
- **`Note.spannerForward` / `spannerBack` 对 Slur 恒返回空。** 属性自 4.6 起就有，
  但在 4.7.5 上只对 glissando 一类有效，延音线得从 `curScore.spanners` 枚举。
- **`spannerTicks`（Pid::SPANNER_TICKS）是"跨度"不是结束位置。**
  实测一条 slur 给 `spannerTick=44160, spannerTicks=960`，
  结束点必须自己 `start + ticks` 加出来。

### 手动联调的推荐流程

Plugins 菜单的弹出层是独立 HWND，屏幕抓取工具截不到，盲按键盘又容易误触发别的命令。
更可靠的做法是给插件绑一个快捷键：

1. Home → Plugins → 点插件卡片 → **Edit shortcut**（会直接跳到 偏好设置 → Shortcuts 并筛好）。
2. 选中那行 `Run plugin …` → Define… → 按下组合键（本项目用 `Ctrl+Shift+L`）→ Save → OK。
   快捷键写进 `%LOCALAPPDATA%\MuseScore\MuseScore4\shortcuts.xml`，重启后仍然有效。
3. 之后每轮改完 `.qml`，**必须完全退出 MuseScore 再重开**。
   Home → Plugins → **Reload plugins** 只会重新扫描插件列表（卡片上的版本号会变），
   **不会重新编译 QML**，旧脚本仍在内存里，改的代码看不到。
   4.7.5 实测：Reload 后探针输出保持旧值，重启后才更新。

联调时建议先复制一份乐谱再测（`cp 原谱.mscz test/副本.mscz`），
并且**不要按 Ctrl+S**——标题栏带 `*` 表示尚未保存，一次 Ctrl+Z 就能整体撤销插件写入的全部歌词。

---

## 实测记录

在 MuseScore Studio 4.7.5 + 一首真实歌曲（单谱表、4/4、253 个音符、含连音线与延音线）上验证通过：

| 项目 | 结果 |
| --- | --- |
| 剪贴板自动读取 | 打开对话框即读入 291 字符歌词，中文无乱码 |
| 语言自动识别 | 纯中文文本判为"中文/一字一音" |
| 分词数量 | 报告 215 个音节单元，与独立脚本统计的 CJK 字符数完全一致 |
| 声部遍历 | 识别出 253 个音符；连音线后续音 25 个，开启延音线后共 37 个，可填位置 216 |
| 数量不匹配提示 | 正确警告"还有 1 个音符没有歌词"（216 − 215 = 1） |
| 开关可点击 | 5 个复选框取消勾选后统计随之变化（延音线关掉时后续音回到 25 个） |
| 写入 | 215 个音节全部落位，顺序与原文一致，休止符不占音节 |
| 撤销 | 一次 Ctrl+Z 可整体回退 |

---

## 已知限制

- **每次只处理一条谱表的一个声部**，不能一次把 4 段歌词分派到 4 条谱表。
- **换行不被当作段落分隔**，多段歌词请逐段填（配合"第几段歌词"）。
- 方括号 `[...]` 不支持嵌套，也不建议与相邻文字连写（`la[xx]` 会被当一个词）。
- 英文不处理省音号（elision，如 `l'amor` 的连音线），需要时请手动加。
- CJK 扩展 B 及以外的生僻字（Unicode 平面 2 以上，如 𠀀）不在汉字范围内，
  会被当成标点贴到前一个字上（`月𠀀` 挤进同一个音符）。需要它独占一个音符时，
  用方括号包起来：`[𠀀]`。
- 标点只是"贴"在歌词文本上，不参与发音或排版判断；如果你想让某个标点单独占一拍，
  那本来就该是一个音符，请用方括号把它包成一个单元。
- 休止符上不写歌词（MuseScore 里歌词挂在休止符上属于异常状态）。
- 延音线只从谱面级 `curScore.spanners` 读取；4.x 早期版本未实测，读不到时会退回只认连音线并提示。

---

## 许可

GPL-3.0-or-later，与 MuseScore Studio 保持一致。详见 [LICENSE](LICENSE)。
