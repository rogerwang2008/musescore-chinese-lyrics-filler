# 开发与发版说明

面向修改源码或接手维护的读者。仅使用插件请见 [README.md](../README.md)。

- [仓库结构](#仓库结构)
- [代码结构](#代码结构)
- [测试](#测试)
- [MuseScore 4.7.5 的已验证行为](#musescore-475-的已验证行为)
- [手动联调](#手动联调)
- [发版](#发版)
- [安装脚本约束](#安装脚本约束)
- [实测记录](#实测记录)

---

## 仓库结构

```
LyricsFiller/             插件本体，整个目录即发布单元
  lyricsfiller.qml          界面 + 分词 + 写入，单文件
  lyricsfiller.png          插件卡片缩略图
README.md                 使用者文档
CHANGELOG.md              使用者视角的更新记录
docs/DEVELOPMENT.md         本文件
tests/                    Node 单元测试，不依赖 MuseScore，无第三方依赖
.github/workflows/
  test.yml                  每次 push / PR 运行 npm test
  release.yml               v* 标签触发自动发布
install.bat / install.sh    将 LyricsFiller/ 复制到用户插件目录
test/                     本地联调素材（歌词与乐谱副本），已 gitignore
```

---

## 代码结构

分词与排布逻辑集中在 `buildTokenizer()`，由两行标记界定：

```qml
/* =====[TOKENIZER-BEGIN]===== */
function buildTokenizer() { /* ... */ }
/* =====[TOKENIZER-END]===== */
```

该函数不引用任何 MuseScore 对象，输入输出均为字符串与数组。这样安排的原因：

- `tests/tokenizer.test.mjs` 将这段代码原样截取后用 `new Function` 执行，
  被测代码与插件实际执行的代码是同一份，不存在副本漂移。
  `new Function` 的输入仅为本仓库提交的 `.qml`，不涉及外部数据。
- 依赖 Qt 环境的部分（遍历音符、读写 `Lyrics` 元素、连音线/延音线判定）全部在其外部，
  修改分词规则无需启动 MuseScore。

扩展分词规则：修改 `buildTokenizer()`，运行 `npm test`。

---

## 测试

```bash
npm test
# 即 node --test，不带路径，使用 Node 的默认测试文件发现规则
```

不带路径是必要的：`node --test tests/` 会被解析为模块路径并报 MODULE_NOT_FOUND；
`node --test "tests/*.test.mjs"` 依赖 Node 21+ 才支持的 glob，而 CI 固定在 Node 20，
两种写法都会让 CI 失败。不带参数在 Node 18/20/22/24 上行为一致，默认匹配
`**/*.test.mjs`，新增测试文件无需修改 `package.json`。

| 文件 | 覆盖内容 |
| --- | --- |
| `tokenizer.test.mjs` | 中英文分词、标点并入、方括号合并、语言识别，`planFill` 的 melisma、延长线、数量不匹配 |
| `plugin-format.test.mjs` | 复刻 MuseScore 头部文本解析器，校验 7 个必需元数据、缩略图存在、括号配平、三处版本号一致 |
| `qml-references.test.mjs` | 控件 id 唯一且被引用、成员访问基名均有定义、不与根类型保留名冲突、每个 `CheckBox` 均带 `onClicked: checked = !checked` |
| `install-script.test.mjs` | `install.bat` 为纯 ASCII + CRLF + 无 BOM；`install.sh` 的路径校验位于 `mkdir` 之前 |
| `docs-links.test.mjs` | 三份文档之间的锚点与相对链接有效 |

**行为型断言需做变异验证。** 表中多条断言用于固定曾经实现错误的行为，
新增此类测试后应手动将被测代码改坏一次，确认测试确实失败
（例如删除一个 `onClicked`、向 `install.bat` 写入一个中文字符）。
否则容易写出恒真的测试：曾把哨兵条件写成 `missing.length > 0`，
导致"全部通过"与"什么都没检查"在输出上完全相同。

---

## MuseScore 4.7.5 的已验证行为

以下结论均来自实测，源码与官方文档中不足以推断：

1. **`onRun:` 不可用于 dialog 插件。** 声明 `onRun: { … }` 会使 QML 报
   `Cannot assign to non-existent property "onRun"` 并中止加载，插件窗口不出现。
   本插件改用根对象的 `Component.onCompleted`，对话框打开时同样触发。
2. **函数与属性不得与根类型保留名冲突。** 根类型自带 `run` 信号，
   再定义 `function run()` 会报 `Duplicate method name`，并连带使 `onRun` 无法生成。
   同类保留名包括 `quit`、`cmd`、`newElement`、`fraction`、`division`、`curScore` 等，
   完整清单见 `tests/qml-references.test.mjs` 中的 `RESERVED`。
3. **MuseScore 不读取清单文件**，而是逐行文本解析 `.qml` 头部的
   `title`、`description`、`pluginType`、`categoryCode`、`thumbnailName`、
   `requiresScore`、`version` 七个属性
   （见 `src/framework/extensions/internal/legacy/extpluginsloader.cpp`）。
   缺任一属性插件即不出现在列表中；七者必须都位于第一个内层代码块（如 `Item {`）之前。
4. **加载失败时只弹出空白窗口。** 用于显示错误的
   `qrc:/qml/Muse/Extensions/ExtensionErrorMessage.qml` 在 4.7.5 安装包中缺失，
   日志对应一条 `No such file or directory`。因此"窗口空白"等价于"加载失败"。
5. **不要在异常对话框上按 Escape。** 实测触发 MuseScore 自身断言
   （`InteractiveProvider::onClose ASSERT FAILED`，interactiveprovider.cpp:828），
   进程退出并生成约 23 MB 的 dump。
6. **日志是主要诊断手段**：
   `%LOCALAPPDATA%\MuseScore\MuseScore4\logs\MuseScore_*.log`，
   检索 `ExtensionBuilder::load`（加载失败）、`Qt |`（QML 运行时报错）、
   `ActionsDispatcher::doDispatch`（动作是否触发）。
   插件内的 `console.log` 不写入该日志；需要输出时只能写入界面文本控件再截图读取。
7. **`Muse.UiComponents` 的 `CheckBox` 点击不会自行翻转 `checked`。**
   它是自定义 `FocusScope`，`checked` 为普通属性，`onClicked` 仅发出 `clicked()` 信号，
   必须显式写 `onClicked: checked = !checked`。
   `ComboBox` 与 `SpinBox` 来自 `QtQuick.Controls`，无此问题。
8. **延音线（Slur）只能从谱面级获取。** `Note.spannerForward` / `spannerBack`
   自 4.6 起存在，但在 4.7.5 上对 Slur 恒返回空列表（源码注释仅提及 glissando、bend）。
   应枚举 `curScore.spanners`，用 `spannerTick` 与 `spannerTicks` 划出 tick 区间；
   `spannerTicks`（Pid::SPANNER_TICKS）是跨度而非结束位置，终点需自行以 `start + ticks` 计算。
   `ScoreElement.name()` 返回 `typeName()`，即首字母大写的 `"Slur"`，比较需忽略大小写。
9. **tick 基准为 960/四分音符、3840/全音符**，而非历史值 1440/5760。
   实测十六分=240、八分=480、四分=960、二分=1920。
   按 `fraction(ticks, 5760)` 换算得到的时长只有应有长度的 2/3；优先使用 `fractionFromTicks()`。

另有两条与 QML 无关的限制：

- **Plugins 菜单的弹出层是独立 HWND**，屏幕抓取工具无法截取，也不暴露 UIA 子元素；
  MuseScore 自身的对话框可以截取并按元素定位。
- **"Reload plugins" 不重新编译 QML。** 它只重扫插件列表（卡片版本号会更新），
  旧脚本仍驻留内存。修改 `.qml` 后必须完全退出并重启 MuseScore。

---

## 手动联调

Plugins 菜单弹层无法截取，键盘盲操作易误触发其他命令，因此为插件绑定快捷键：

1. Home → Plugins → 选择插件卡片 → **Edit shortcut**（跳转至 偏好设置 → Shortcuts 并已筛选）。
2. 选中 `Run plugin …` → Define… → 按下组合键（本项目使用 `Ctrl+Shift+L`）→ Save → OK。
   快捷键写入 `%LOCALAPPDATA%\MuseScore\MuseScore4\shortcuts.xml`，重启后仍有效。
3. 每轮修改 `.qml` 后完全退出并重启 MuseScore，再按快捷键触发。

联调前先复制一份乐谱（`cp 原谱.mscz test/副本.mscz`），并且不要按 Ctrl+S：
标题栏的 `*` 表示未保存，一次 Ctrl+Z 即可撤销插件写入的全部歌词，原谱保持不变。

歌词与乐谱样本置于 `test/`。`.gitignore` 中的 `test/` 与 `*.txt`
确保样本不会连同歌词文本入库。

---

## 发版

发布由标签触发。不依赖本地 `gh`，也不使用第三方 Action（调用 runner 内置的 `gh` CLI），
工作流权限收紧为 `contents: write`：

```bash
npm test                                    # 确认全部通过
# 同步修改三处版本号：package.json、lyricsfiller.qml 头部 version、即将创建的标签
# 并在 CHANGELOG.md 顶部新增 vX.Y.Z 一节，只写对用户有影响的变化
git commit -am "Bump version to x.y.z" && git push
git tag -a v1.0.1 -m "..." && git push origin v1.0.1   # 推送标签即触发发布
```

`.github/workflows/release.yml` 收到 `v*` 标签后依次执行：运行测试 →
校验标签与 `package.json` 版本一致 → 将 `LyricsFiller/` 打包为
`LyricsFiller-v1.0.1.zip` → 创建 Release，附上 zip 与单个 `lyricsfiller.qml`。

注意事项：

- 版本号存在三处：git 标签、`package.json`、`lyricsfiller.qml` 头部的 `version`。
  不一致会导致 Release 标题、下载文件名与插件内显示的版本号互不对应。
  `plugin-format.test.mjs` 校验前两处，workflow 校验标签。
- 仓库 Settings → Actions → General → Workflow permissions 需为 **Read and write**，
  否则 `gh release create` 返回 403。
- 修改发布说明或补附件：在 Actions 页手动运行 **release** 工作流（`workflow_dispatch`），
  填入同一标签，脚本走"已存在则更新"分支，不会重复创建 Release。
- 标签推送后即对外可见；删除标签不会自动删除 Release，需在 Releases 页面一并删除。
  若标签对应的 CI 失败需要重指标签，使用 `--force-with-lease` 较安全，
  且 lease 须比对远端 ref 的实际值：注解标签的远端值是 tag 对象 SHA 而非提交 SHA
  （`git ls-remote origin refs/tags/<tag>` 的输出），填提交 SHA 会被判定 stale 而拒绝。

发布说明正文位于 `release.yml` 的 `Write release notes` 步骤（heredoc）。
其读者是下载者，内容限于功能、安装、用法与隐私声明；
提交历史、测试结构、CI 配置等开发信息不写入，这些内容会随版本失效。
版本级变化记录在 `CHANGELOG.md`，正文以链接指向。

文档之间使用相对链接，不使用仓库外绝对路径，以便在 Release 页面、
本地克隆与编辑器预览中均可跳转。

---

## 安装脚本约束

`install.bat` 为纯 ASCII、全英文输出，原因是功能性的而非风格偏好：
cmd.exe 按字节偏移读取脚本，文件含多字节字符时行边界会错位，
将后续行切在错误位置，`REM` 与 `echo` 的尾部会被当作命令执行。实际报错形如：

```
'?>' 不是内部或外部命令，也不是可运行的程序或批处理文件。
```

（原文是转义过的 `^>`。）`chcp 65001` 无法解决：它改变的是输出解码，
脚本读取的位置簿记仍然错误。因此：

- `install.bat` 纯 ASCII + 英文输出，中文说明置于 README；
- `install.sh` 保留中文输出（bash 读取 UTF-8 无此问题）；
- `tests/install-script.test.mjs` 校验纯 ASCII、CRLF、无 BOM、`echo` 行不含元字符。

目标目录：Windows 的"文档"常被重定向，此时 `%USERPROFILE%\Documents`
不是 MuseScore 扫描的目录，脚本会把插件放到永不读取的位置。
`install.bat` 先查询注册表
`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\Personal`；
该值类型为 `REG_EXPAND_SZ`，可能仍含未展开的 `%USERPROFILE%`，需用 `call set` 再展开一次。

脚本写法约束：

- `echo` 行不含未转义的 `>`、`<`、`&`。
- 含非 ASCII 内容的行不使用 `if ( ... )` 代码块，改用 `goto`；括号被误吞是此类脚本的常见故障。
- 测试时不要将 `install.bat` 的输出接管道给 `head`：`head` 先退出会使 cmd 在 `xcopy`
  过程中收到断管而中止，出现"脚本打印 Done 但文件未更新"。

---

## 实测记录

在 MuseScore Studio 4.7.5 与一首真实歌曲（单谱表、4/4、253 个音符，含连音线与延音线）上验证：

| 项目 | 结果 |
| --- | --- |
| 剪贴板读取 | 打开对话框读入 291 字符歌词，中文无乱码 |
| 语言自动识别 | 纯中文文本识别为"中文/一字一音" |
| 分词数量 | 215 个音节单元，与独立脚本统计的 CJK 字符数一致 |
| 声部遍历 | 253 个音符；连音线后续音 25 个，启用延音线后 37 个，可填位置 216 |
| 数量不匹配提示 | 提示"还有 1 个音符没有歌词"（216 − 215 = 1） |
| 开关响应 | 取消勾选后统计随之变化（关闭延音线时后续音回到 25 个） |
| 写入 | 215 个音节全部落位，顺序与原文一致，休止符不占音节 |
| 撤销 | 一次 Ctrl+Z 整体回退 |
| 安装脚本 | 注册表解析到重定向后的真实文档目录，Windows 实跑落地正确 |
| 发布产物 | v1.1.0 的 zip 内为 `LyricsFiller/lyricsfiller.qml` 与 `.png` |
