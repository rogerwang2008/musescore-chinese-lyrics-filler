# 开发与发版说明

面向想读源码、改规则或接手维护的人。只用插件的话看 [README.md](../README.md) 就够了。

- [仓库结构](#仓库结构)
- [代码结构：为什么分词器是个纯函数](#代码结构为什么分词器是个纯函数)
- [测试](#测试)
- [在 MuseScore 4.7.5 上开发必须知道的九件事](#在-musescore-475-上开发必须知道的九件事)
- [手动联调流程](#手动联调流程)
- [发版（自动生成 GitHub Release）](#发版自动生成-github-release)
- [安装脚本为什么是纯 ASCII](#安装脚本为什么是纯-ascii)
- [实测记录](#实测记录)

---

## 仓库结构

```
LyricsFiller/           插件本体（整个目录就是发布单元，MuseScore 扫描这里）
  lyricsfiller.qml        单文件插件：界面 + 分词 + 写入
  lyricsfiller.png        插件卡片缩略图
README.md               面向使用者的文档
CHANGELOG.md            面向使用者的更新记录（只列有用户影响的变化）
docs/DEVELOPMENT.md       这个文件
tests/                  Node 单元测试，不需要 MuseScore，也不依赖任何包
.github/workflows/
  test.yml                每次 push / PR 跑 npm test
  release.yml             打 v* 标签自动发 Release
install.bat / install.sh  把 LyricsFiller/ 复制到用户插件目录
test/                     本地联调素材（歌词与乐谱副本），已 gitignore，不会入库
```

---

## 代码结构：为什么分词器是个纯函数

分词与排布逻辑全部集中在 `buildTokenizer()` 里，被这两行标记圈住：

```qml
/* =====[TOKENIZER-BEGIN]===== */
function buildTokenizer() { /* ... */ }
/* =====[TOKENIZER-END]===== */
```

这个函数**不引用任何 MuseScore 对象**，只吃字符串和数组。好处：

- `tests/tokenizer.test.mjs` 能把这段代码**原样截取**出来，用 `new Function` 直接跑，
  测的就是插件真正会执行的那份代码，而不是手抄一遍的副本（抄的副本会漂）。
- 需要 Qt 环境的部分（遍历音符、读写 `Lyrics` 元素、连音线/延音线判定）都在它外面，
  改分词规则不需要启动 MuseScore。

要扩展分词规则，只改 `buildTokenizer()`，然后 `npm test`。

注意 `new Function` 的输入只有本仓库自己提交的 `.qml`，不来自任何不可信数据。

---

## 测试

```bash
npm test
# 等价于：node --test      （不带路径，用 Node 的默认测试文件发现规则）
```

> 这里刻意不写路径。`node --test tests/` 会被当成模块路径报 MODULE_NOT_FOUND；
> `node --test "tests/*.test.mjs"` 依赖 Node 21+ 才支持的 glob，而 CI 固定在 Node 20 ——
> 这两点都实测踩过，CI 会直接红。不带参数在 18/20/22/24 上行为一致，
> 默认匹配 `**/*.test.mjs`，新增测试文件不需要再改 `package.json`。

四个测试文件各管一块：

| 文件 | 守住什么 |
| --- | --- |
| `tokenizer.test.mjs` | 中英文分词、标点跟随、方括号合并、语言识别，以及 `planFill` 的 melisma/延长线/数量不匹配 |
| `plugin-format.test.mjs` | 复刻 MuseScore 的头部文本解析器，校验 7 个必需元数据、缩略图存在、括号配平、**三处版本号一致** |
| `qml-references.test.mjs` | 控件 id 唯一且被引用、成员访问的基名都有定义、不与根类型保留名冲突、每个 `CheckBox` 都带 `onClicked: checked = !checked` |
| `install-script.test.mjs` | `install.bat` 必须纯 ASCII + CRLF + 无 BOM；`install.sh` 的路径校验要在 `mkdir` 之前 |

**给行为型断言做变异验证。** 上面这些断言里有几条是为了钉住"曾经错得很隐蔽"的 bug，
所以每次新增这类测试，都手动把被测代码改坏一次，确认测试真的会红 ——
比如删掉一个 `onClicked`、往 `install.bat` 塞一个中文字符。
否则很容易写出"永远绿"的测试（曾经把断言方向写反过：`missing.length > 0` 当哨兵，
结果全部通过和什么都没测到看起来一模一样）。

---

## 在 MuseScore 4.7.5 上开发必须知道的九件事

全部是实测踩出来的，源码和文档里看不出来：

1. **`onRun:` 不能用在 dialog 插件上。** 写 `onRun: { … }` 会让 QML 直接报
   `Cannot assign to non-existent property "onRun"` 并中止加载，插件窗口根本不出现。
   本插件改用根对象的 `Component.onCompleted`，对话框打开时同样触发。
2. **不要给函数/属性起根类型的保留名。** 根类型自带 `run` 信号，
   自己再写 `function run()` 会报 `Duplicate method name`，并连带让 `onRun` 无法生成。
   同类保留名还有 `quit` `cmd` `newElement` `fraction` `division` `curScore` 等，
   完整清单见 `tests/qml-references.test.mjs` 里的 `RESERVED`。
3. **MuseScore 不读清单文件**，而是逐行文本解析 `.qml` 头部的
   `title` / `description` / `pluginType` / `categoryCode` / `thumbnailName` /
   `requiresScore` / `version` 这 7 个属性（见
   `src/framework/extensions/internal/legacy/extpluginsloader.cpp`）。
   缺任何一个，插件不会出现在列表里；它们必须都出现在第一个内层代码块（如 `Item {`）之前。
4. **加载失败时 MuseScore 只弹一个全空白窗口。** 它想显示的
   `qrc:/qml/Muse/Extensions/ExtensionErrorMessage.qml` 在 4.7.5 安装包里缺失，
   日志里对应一条 `No such file or directory`。所以"窗口是空的"就等于"加载失败"。
5. **不要在异常对话框上按 Escape。** 实测会触发 MuseScore 自身的断言
   （`InteractiveProvider::onClose ASSERT FAILED`，interactiveprovider.cpp:828）并让整个程序退出，
   留下 23 MB 的 dump。
6. **看日志是唯一可靠的诊断手段**：
   `%LOCALAPPDATA%\MuseScore\MuseScore4\logs\MuseScore_*.log`，
   搜 `ExtensionBuilder::load`（加载失败）、`Qt |`（QML 运行时报错）、
   `ActionsDispatcher::doDispatch`（动作是否被触发）。
   但**插件里的 `console.log` 不会进这个日志** —— 想打印只能写到界面文本控件上再截图读回。
7. **`Muse.UiComponents` 的 `CheckBox` 点击时不会自己翻转。** 它是自定义 `FocusScope`，
   `checked` 只是普通属性，`onClicked` 只发 `clicked()` 信号。必须显式写
   `onClicked: checked = !checked`，否则界面上看得到却点不动。
   （`ComboBox` / `SpinBox` 来自 `QtQuick.Controls`，没这个问题。）
8. **延音线（Slur）只能从谱面级拿。** `Note.spannerForward` / `spannerBack` 自 4.6 起就有，
   但在 4.7.5 上对 Slur **恒返回空列表**（源码注释也只提到 glissando、bend）。
   正确做法是枚举 `curScore.spanners`，用 `spannerTick` / `spannerTicks` 划 tick 区间，
   其中 `spannerTicks`（Pid::SPANNER_TICKS）是**跨度不是结束位置**，结束点要自己 `start + ticks`。
   `ScoreElement.name()` 返回的是 `typeName()`，即首字母大写的 `"Slur"`，比较时必须忽略大小写。
9. **tick 基准是 960/四分音符、3840/全音符**，不是历史上常用的 1440/5760。
   实测十六分=240、八分=480、四分=960、二分=1920。
   自己 `fraction(ticks, 5760)` 会得到错两倍的时值；优先用 `fractionFromTicks()`。

另外两条 QML 之外的坑：

- **Plugins 菜单的弹出层是独立 HWND**，屏幕抓取工具截不到，也没有 UIA 子元素；
  MuseScore 自己的对话框倒是可以截到、可以按元素定位。
- **"Reload plugins" 不会重新编译 QML。** 它只重扫插件列表（卡片上的版本号会变），
  旧脚本仍在内存里。改完 `.qml` 必须完全退出并重开 MuseScore。

---

## 手动联调流程

给插件绑一个快捷键最可靠（避开截不到的菜单弹层）：

1. Home → Plugins → 点插件卡片 → **Edit shortcut**（会直接跳到 偏好设置 → Shortcuts 并筛好）。
2. 选中 `Run plugin …` 那行 → Define… → 按下组合键（本项目用 `Ctrl+Shift+L`）→ Save → OK。
   快捷键写进 `%LOCALAPPDATA%\MuseScore\MuseScore4\shortcuts.xml`，重启后仍然有效。
3. 每轮改完 `.qml`：完全退出 MuseScore 再重开，按一下快捷键触发。

联调前**先复制一份乐谱**（`cp 原谱.mscz test/副本.mscz`），并且**不要按 Ctrl+S**：
标题栏带 `*` 表示尚未保存，一次 Ctrl+Z 就能整体撤销插件写入的全部歌词，原谱始终干净。

歌词与乐谱样本放在 `test/`，配合 `.gitignore` 里的 `test/` 和 `*.txt`，
不会连着歌词文本一起提交上去（版权与隐私）。

---

## 发版（自动生成 GitHub Release）

发布由**打标签**驱动，不需要本地装 `gh`，也不依赖任何第三方 Action
（用的是 runner 自带的 `gh` CLI），权限收紧到 `contents: write`：

```bash
npm test                                    # 先确认全绿
# 三处版本号一起改：package.json、lyricsfiller.qml 头部 version、下一个 git tag
# 并在 CHANGELOG.md 顶部加一节 vX.Y.Z，只写对用户有影响的变化
git commit -am "Bump version to x.y.z" && git push
git tag -a v1.0.1 -m "..." && git push origin v1.0.1   # 这一推就触发发布
```

`.github/workflows/release.yml` 收到 `v*` 标签后依次：跑测试 → 校验标签与
`package.json` 版本一致 → 把 `LyricsFiller/` 压成 `LyricsFiller-v1.0.1.zip` →
创建 Release，挂上 zip 和单个 `lyricsfiller.qml`。

几个容易踩的点：

- **版本号有三处**：git 标签、`package.json`、`lyricsfiller.qml` 头部的 `version`。
  不一致会让 Release 标题、下载文件名和插件里显示的版本号互相对不上；
  `plugin-format.test.mjs` 会拦住前两处，workflow 再校验标签这一处。
- **需要** 仓库 Settings → Actions → General → "Workflow permissions" 至少是
  **Read and write**，否则 `gh release create` 直接 403。
- 想改发布说明或补附件：在 Actions 页手动运行 **release** workflow（`workflow_dispatch`），
  填同一个 tag，脚本走"已存在则更新"分支，不会重复创建 Release。
- **标签推上去就是公开状态**，删标签不会自动删 Release，要去 Releases 页一起删。
  如果标签对应的 CI 是红的，用 `--force-with-lease` 重指比"删了再建"安全：
  注意 lease 要比对**远端 ref 的值**，注解标签的远端值是 tag 对象 SHA 而不是提交 SHA
  （`git ls-remote origin refs/tags/v1.1.0` 拿到的那个），写成提交 SHA 会被判 stale 而拒绝。

发布说明的正文在 `release.yml` 的 `Write release notes` 步骤里（heredoc）。
它面向下载者：这是什么、怎么装、怎么用、隐私声明，**不要往里塞开发细节** ——
提交历史、测试结构、CI 配置这些会随版本腐烂，对装插件的人也没用。
版本级的变化写进 `CHANGELOG.md`，正文里链接过去。

`docs/` 下的文档不要引用仓库外的绝对路径，`README.md` 与 `CHANGELOG.md` 之间用相对链接，
这样在 Release 页面、本地克隆和 IDE 预览里都能点。

---

## 安装脚本为什么是纯 ASCII

`install.bat` 刻意全英文、全 ASCII。原因不是风格偏好：cmd.exe 按**字节偏移**读脚本，
文件里出现多字节字符（中文）时它的行边界会错位，把后续行切在奇怪的地方 ——
`REM` 和 `echo` 的尾巴会被当成命令执行。实际报错长这样：

```
'?>' 不是内部或外部命令，也不是可运行的程序或批处理文件。
```

（原本是转义过的 `^>`。）`chcp 65001` 也救不了，因为它改的是输出解码，
脚本读取的位置簿记仍然是错的。所以：

- `install.bat` 纯 ASCII + 英文输出，中文说明写进 README；
- `install.sh` 保留中文（bash 读 UTF-8 没问题）；
- `tests/install-script.test.mjs` 钉住"纯 ASCII / CRLF / 无 BOM / echo 行不含元字符"。

另一个坑：Windows 的"文档"经常被重定向（OneDrive 或整个搬到别的盘），
这时 `%USERPROFILE%\Documents` 并不是 MuseScore 读取的目录，脚本会把插件装到一个
永远不会被扫描的地方。`install.bat` 因此先查注册表
`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\Personal`，
它是 `REG_EXPAND_SZ`，可能还带着没展开的 `%USERPROFILE%`，要用 `call set` 再展开一次。

顺带两条脚本写法约束：`echo` 行不要出现没转义的 `>` `<` `&`；
含中文的行不要用 `if ( ... )` 代码块（改成 `goto`），括号被吞掉是这类脚本最常见的死法。
测试时也别把 `install.bat` 接管道给 `head` —— head 先退出会让 cmd 在 `xcopy` 中途收到断管而中止，
留下一个"脚本说 Done 但文件没更新"的假象。

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
| 安装脚本 | 注册表解析到重定向后的真实"文档"目录，Windows 实跑落地正确 |
| 发布产物 | v1.1.0 zip 内为 `LyricsFiller/lyricsfiller.qml` + `.png`，解压即用 |
