//===========================================================================
// Lyrics Filler (自动填词)
//
// Copyright (C) 2026 Lyrics Filler contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//===========================================================================
//
// 从系统剪贴板读取歌词，按语言规则拆成"音节单元"，再顺序填入指定声部的音符。
//
// 兼容 MuseScore Studio 4.x（在 4.7.5 上验证）。
//
// 注意：MuseScore 用纯文本方式解析下面 MuseScore { } 内的元数据，
// 要求 title / description / pluginType / categoryCode / thumbnailName /
// requiresScore / version 这 7 项都出现在第一个内层代码块之前，
// 且每个属性各占一行、不要以 "{" 结尾，否则插件不会出现在列表中。

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import MuseScore 3.0
import Muse.Ui
import Muse.UiComponents

MuseScore {
    version: "1.0.0"
    title: qsTr("Lyrics Filler 自动填词")
    description: qsTr("Read lyrics from the clipboard and fill one syllable per note, with CJK / English tokenizing, tie and slur melisma handling.")
    pluginType: "dialog"
    categoryCode: "lyrics"
    thumbnailName: "lyricsfiller.png"
    requiresScore: true

    id: root
    width: 860
    height: 640

    property var tok: buildTokenizer()
    property string statusText: qsTr("把歌词复制到剪贴板后打开本插件，或在此粘贴。")
    property bool cmdOpen: false

    // MuseScore 内部 1 个四分音符 = 1440 ticks，1 个全音符 = 5760 ticks。
    // fraction(n, d) 的分母以"全音符"为单位，所以由 ticks 构造 Fraction 要用 5760。
    readonly property int ticksPerWholeNote: 5760
    // paste() 无法直接判断剪贴板内容，先写入哨兵再粘贴，未发生变化即说明剪贴板为空。
    readonly property string clipboardSentinel: "__LYRICS_FILLER_EMPTY__"

    /* =====[TOKENIZER-BEGIN]===== */
    // 纯 JavaScript 分词 / 排布逻辑，不引用任何 MuseScore 对象，
    // 因此可以被 tests/tokenizer.test.mjs 原样抽取并单独测试。
    function buildTokenizer() {
        var GROUP_OPEN = "\u0001";
        var GROUP_CLOSE = "\u0002";

        // CJK 统一表意文字基本区与扩展 A、兼容表意文字，以及假名
        // （日语歌词同样一字一音）。扩展 B 等平面 2 的字形不在此列。
        var CJK_RANGES = [0x3400, 0x4DBF, 0x4E00, 0x9FFF, 0xF900, 0xFAFF,
                          0x3040, 0x30FF, 0x31F0, 0x31FF];
        // 拉丁字母（含常用变音符号）与数字，用于英文单词以及中文里夹带的英文
        var LETTER_RE = /[A-Za-z0-9\u00C0-\u024F\u1E00-\u1EFF]/;
        var HEAD_TRIM_RE = /^[^A-Za-z0-9\u00C0-\u024F\u1E00-\u1EFF]+/;
        var TAIL_TRIM_RE = /[^A-Za-z0-9\u00C0-\u024F\u1E00-\u1EFF']+$/;

        function isCjkChar(ch) {
            var c = ch.charCodeAt(0);
            for (var i = 0; i < CJK_RANGES.length; i += 2) {
                if (c >= CJK_RANGES[i] && c <= CJK_RANGES[i + 1]) {
                    return true;
                }
            }
            return false;
        }

        // 一个音节单元在"词"中的位置决定 MuseScore 是否补画连字符：
        // begin / middle 会自动带上下一个音节的 "-"，所以文本里不能保留连字符。
        function syllabicOf(wordStart, wordEnd) {
            if (wordStart && wordEnd) return "single";
            if (wordStart) return "begin";
            if (wordEnd) return "end";
            return "middle";
        }

        // 把 [xxx] 抽出成占位符，避免括号内的内容被后续分词规则拆开。
        // 括号前后补空格，保证占位符自己是一个独立的块。
        function protectGroups(text, warnings) {
            var out = "";
            var groups = [];
            var i = 0;
            while (i < text.length) {
                var ch = text.charAt(i);
                if (ch === "[") {
                    var close = text.indexOf("]", i + 1);
                    if (close < 0) {
                        warnings.push("第 " + (i + 1) + " 个 '[' 缺少配对的 ']'，已按普通文本处理。");
                        out += ch;
                        i += 1;
                        continue;
                    }
                    var inner = text.slice(i + 1, close).replace(/\s+/g, " ").trim();
                    out += " " + GROUP_OPEN + groups.length + GROUP_CLOSE + " ";
                    groups.push(inner);
                    i = close + 1;
                    continue;
                }
                out += ch;
                i += 1;
            }
            return { text: out, groups: groups };
        }

        function groupPlaceholder(index) {
            return GROUP_OPEN + index + GROUP_CLOSE;
        }

        function isGroupBlock(block) {
            return block.length > 2 && block.charAt(0) === GROUP_OPEN
                    && block.charAt(block.length - 1) === GROUP_CLOSE;
        }

        function groupIndex(block) {
            return parseInt(block.slice(1, block.length - 1), 10);
        }

        // 中文：一个汉字 = 一个音节单元；括号内容整体 = 一个单元；
        // 夹带的拉丁字母/数字按词聚合；空白与标点（含中文标点）丢弃。
        function tokenizeChinese(text) {
            var warnings = [];
            var protectedText = protectGroups(text, warnings);
            var s = protectedText.text;
            var units = [];

            for (var i = 0; i < s.length; i++) {
                var ch = s.charAt(i);
                if (ch === GROUP_OPEN) {
                    var close = s.indexOf(GROUP_CLOSE, i);
                    var index = groupIndex(s.slice(i, close + 1));
                    var content = protectedText.groups[index];
                    if (content.length > 0) {
                        units.push({ text: content, syllabic: "single", bracketed: true });
                    } else {
                        warnings.push("第 " + (index + 1) + " 个方括号是空的，已忽略。");
                    }
                    i = close;
                    continue;
                }
                if (isCjkChar(ch)) {
                    units.push({ text: ch, syllabic: "single", bracketed: false });
                    continue;
                }
                if (LETTER_RE.test(ch)) {
                    var word = "";
                    while (i < s.length && LETTER_RE.test(s.charAt(i))) {
                        word += s.charAt(i);
                        i += 1;
                    }
                    i -= 1;
                    units.push({ text: word, syllabic: "single", bracketed: false });
                    continue;
                }
                // 其余字符（空白、中英文标点）不占音符
            }
            return { units: units, warnings: warnings };
        }

        // 英文：空格分词，词内 "-" 是音节边界。
        // 先抹掉连字符两侧的空白，这样 "Si - lence"、"re- action"、跨行的 "ev-\ner"
        // 都会被规约成同一个词 "Si-lence" / "re-action" / "ev-er"。
        function tokenizeEnglish(text) {
            var warnings = [];
            var protectedText = protectGroups(text, warnings);
            var s = protectedText.text.replace(/\r\n?/g, "\n").replace(/\s*-\s*/g, "-");
            var blocks = s.match(/\S+/g) || [];
            var units = [];

            for (var b = 0; b < blocks.length; b++) {
                var block = blocks[b];
                if (isGroupBlock(block)) {
                    var content = protectedText.groups[groupIndex(block)];
                    if (content.length > 0) {
                        units.push({ text: content, syllabic: "single", bracketed: true });
                    } else {
                        warnings.push("有一个方括号是空的，已忽略。");
                    }
                    continue;
                }

                var raw = block.split("-");
                var startsWithHyphen = (raw[0] === "");
                var endsWithHyphen = (raw[raw.length - 1] === "");
                var pieces = [];
                for (var r = 0; r < raw.length; r++) {
                    var piece = raw[r].replace(HEAD_TRIM_RE, "").replace(TAIL_TRIM_RE, "");
                    if (piece.length > 0) {
                        pieces.push(piece);
                    }
                }
                if (pieces.length === 0) {
                    // 纯标点块（例如单独的破折号）不产生音节
                    continue;
                }
                for (var p = 0; p < pieces.length; p++) {
                    var wordStart = (p === 0) && !startsWithHyphen;
                    var wordEnd = (p === pieces.length - 1) && !endsWithHyphen;
                    units.push({
                        text: pieces[p],
                        syllabic: syllabicOf(wordStart, wordEnd),
                        bracketed: false
                    });
                }
            }
            return { units: units, warnings: warnings };
        }

        // 自动判断语言：统计中日韩字符数与拉丁字母数，谁多用谁的规则。
        function detectLanguage(text) {
            var cjk = 0;
            var latin = 0;
            var clean = text.replace(/\[[^\]]*\]/g, " ");
            for (var i = 0; i < clean.length; i++) {
                var ch = clean.charAt(i);
                if (isCjkChar(ch)) {
                    cjk += 1;
                } else if (LETTER_RE.test(ch)) {
                    latin += 1;
                }
            }
            if (cjk === 0 && latin === 0) return "zh";
            return cjk >= latin ? "zh" : "en";
        }

        // mode: "auto" | "zh" | "en"
        function tokenize(text, mode) {
            var language = (mode === "auto") ? detectLanguage(text) : mode;
            var result = (language === "en") ? tokenizeEnglish(text) : tokenizeChinese(text);
            result.language = language;
            return result;
        }

        // 把音节排到音符上。slots 里每一项形如
        //   { tick: 起始tick, dur: 时值ticks, continuation: 是否为连音/延音的后续音 }
        // continuation 的槽位不消耗音节，实现"一字多音"。
        function planFill(units, slots) {
            var anchors = [];
            var continuations = 0;
            for (var i = 0; i < slots.length; i++) {
                if (slots[i].continuation) {
                    continuations += 1;
                } else {
                    anchors.push(i);
                }
            }

            var count = Math.min(units.length, anchors.length);
            var assignments = [];
            for (var j = 0; j < count; j++) {
                var slotIndex = anchors[j];
                var lastCont = -1;
                // 向后收集紧跟在该锚点之后的连续延音槽位，遇到下一个锚点即停止
                for (var k = slotIndex + 1; k < slots.length && slots[k].continuation; k++) {
                    lastCont = k;
                }
                var extenderTicks = 0;
                if (lastCont >= 0) {
                    extenderTicks = (slots[lastCont].tick + slots[lastCont].dur) - slots[slotIndex].tick;
                }
                assignments.push({
                    slotIndex: slotIndex,
                    unitIndex: j,
                    extenderTicks: extenderTicks,
                    melismaLength: lastCont >= 0 ? (lastCont - slotIndex + 1) : 1
                });
            }

            return {
                assignments: assignments,
                anchorCount: anchors.length,
                slotCount: slots.length,
                continuationCount: continuations,
                unusedUnits: Math.max(0, units.length - anchors.length),
                unfilledNotes: Math.max(0, anchors.length - units.length)
            };
        }

        return {
            tokenize: tokenize,
            tokenizeChinese: tokenizeChinese,
            tokenizeEnglish: tokenizeEnglish,
            detectLanguage: detectLanguage,
            planFill: planFill
        };
    }
    /* =====[TOKENIZER-END]===== */

    //------------------------------------------------------------------------
    // 界面
    //------------------------------------------------------------------------

    Item {
        id: window
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            StyledTextLabel {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("歌词文本（自动读取剪贴板，也可手动 Ctrl+V 粘贴到这里）")
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                color: ui.theme.textFieldColor
                border.color: ui.theme.strokeColor
                border.width: Math.max(ui.theme.borderWidth, 1)
                radius: 3

                ScrollView {
                    id: lyricsScroll
                    anchors.fill: parent
                    anchors.margins: 2

                    TextArea {
                        id: lyricsField
                        width: parent.width
                        height: Math.max(implicitHeight, lyricsScroll.height)
                        anchors.margins: 8
                        wrapMode: TextEdit.WrapAnywhere
                        textFormat: TextEdit.PlainText
                        selectByMouse: true
                        onTextChanged: root.refreshUnitCount()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    spacing: 4
                    StyledTextLabel { text: qsTr("语言:") }
                    ComboBox {
                        id: languageCombo
                        Layout.preferredWidth: 130
                        model: [qsTr("自动识别"), qsTr("中文 / 一字一音"), qsTr("English")]
                    }
                }

                RowLayout {
                    spacing: 4
                    StyledTextLabel { text: qsTr("第几段歌词:") }
                    SpinBox {
                        id: verseSpin
                        Layout.preferredWidth: 64
                        from: 1
                        to: 8
                        value: 1
                    }
                }

                RowLayout {
                    spacing: 4
                    StyledTextLabel { text: qsTr("谱表:") }
                    SpinBox {
                        id: staffSpin
                        Layout.preferredWidth: 64
                        from: 1
                        to: 1
                        value: 1
                    }
                }

                RowLayout {
                    spacing: 4
                    StyledTextLabel { text: qsTr("声部:") }
                    SpinBox {
                        id: voiceSpin
                        Layout.preferredWidth: 64
                        from: 1
                        to: 4
                        value: 1
                    }
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                CheckBox {
                    id: useSelectionCheck
                    text: qsTr("只填选区")
                    checked: true
                }

                CheckBox {
                    id: skipTiesCheck
                    text: qsTr("连音线只填首音")
                    checked: true
                }

                CheckBox {
                    id: slurMelismaCheck
                    text: qsTr("延音线只填首音")
                    checked: true
                }

                CheckBox {
                    id: extenderCheck
                    text: qsTr("为连音段画延长线")
                    checked: false
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    spacing: 4
                    StyledTextLabel { text: qsTr("已有歌词:") }
                    ComboBox {
                        id: existingCombo
                        Layout.preferredWidth: 150
                        model: [qsTr("覆盖"), qsTr("跳过该音符")]
                    }
                }

                RowLayout {
                    spacing: 4
                    StyledTextLabel { text: qsTr("位置:") }
                    ComboBox {
                        id: placementCombo
                        Layout.preferredWidth: 130
                        model: [qsTr("自动"), qsTr("上方"), qsTr("下方")]
                    }
                }

                CheckBox {
                    id: strictCheck
                    text: qsTr("数量不一致时不应用")
                    checked: false
                }

                Item { Layout.fillWidth: true }

                FlatButton {
                    text: qsTr("重新读取剪贴板")
                    toolTipTitle: qsTr("用系统剪贴板的内容替换上方文本框")
                    onClicked: {
                        root.readClipboard();
                        root.refreshUnitCount();
                    }
                }

                FlatButton {
                    text: qsTr("统计")
                    toolTipTitle: qsTr("先检查音节数与音符数是否匹配，不改动乐谱")
                    onClicked: root.report(root.analyze(), false)
                }
            }

            StyledTextLabel {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.statusText
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item { Layout.fillWidth: true }

                FlatButton {
                    text: qsTr("关闭")
                    onClicked: quit()
                }

                FlatButton {
                    text: qsTr("应用")
                    toolTipTitle: qsTr("把音节写入乐谱，可用 Ctrl+Z 撤销")
                    onClicked: root.run()
                }
            }
        }
    }

    onRun: {
        syncFromSelection();
        readClipboard();
        refreshUnitCount();
    }

    //------------------------------------------------------------------------
    // 剪贴板读取
    //------------------------------------------------------------------------

    // Qt 的 QML 没有只读的剪贴板接口，这里借用 TextArea 的 paste()：
    // 先全选再粘贴，剪贴板文本就会替换整个内容；粘贴前写入哨兵，
    // 粘贴后如果仍是哨兵，就说明剪贴板里没有文本。
    function readClipboard() {
        var previous = lyricsField.text;
        lyricsField.text = root.clipboardSentinel;
        lyricsField.select(0, lyricsField.text.length);
        lyricsField.paste();

        if (lyricsField.text === root.clipboardSentinel || lyricsField.text.trim() === "") {
            lyricsField.text = previous;
            setStatus(qsTr("剪贴板是空的或不含文本。请先复制歌词，或直接把歌词粘贴到上方文本框。"));
            return false;
        }
        setStatus(qsTr("已从剪贴板读取 %1 个字符。").arg(lyricsField.text.length));
        return true;
    }

    //------------------------------------------------------------------------
    // 目标声部 / 范围
    //------------------------------------------------------------------------

    // 打开插件时，用当前选区预填谱表与声部，通常正是用户想填词的那一行
    function syncFromSelection() {
        if (!curScore) {
            return;
        }
        staffSpin.to = Math.max(1, curScore.ntracks / 4);

        var sel = curScore.selection;
        if (!sel) {
            return;
        }
        var staff = -1;
        var voice = -1;
        if (sel.isRange && sel.startSegment) {
            staff = sel.startStaff;
        } else if (sel.elements && sel.elements.length > 0) {
            // track = staffIdx * 4 + voice
            var track = sel.elements[0].track;
            staff = Math.floor(track / 4);
            voice = track % 4;
        }
        if (staff >= 0) {
            staffSpin.value = staff + 1;
        }
        if (voice >= 0) {
            voiceSpin.value = voice + 1;
        }
        useSelectionCheck.checked = !!(sel.isRange || (sel.elements && sel.elements.length > 0));
    }

    // 返回 { startTick, endTick }，null 表示不设边界（整条声部）
    function selectionRange() {
        if (!useSelectionCheck.checked) {
            return { startTick: null, endTick: null };
        }
        var sel = curScore.selection;
        if (!sel) {
            return { startTick: null, endTick: null };
        }
        if (sel.isRange && sel.startSegment && sel.endSegment) {
            return { startTick: sel.startSegment.tick, endTick: sel.endSegment.tick };
        }
        // 非区间选区（例如单击选中一个音符/小节）：用选中的元素推出 tick 范围
        var elements = sel.elements;
        if (elements && elements.length > 0) {
            var lo = -1;
            var hi = -1;
            for (var i = 0; i < elements.length; i++) {
                var seg = segmentOf(elements[i]);
                if (!seg) {
                    continue;
                }
                if (lo < 0 || seg.tick < lo) lo = seg.tick;
                if (hi < 0 || seg.tick > hi) hi = seg.tick;
            }
            if (lo >= 0) {
                return { startTick: lo, endTick: hi };
            }
        }
        setStatus(qsTr("当前选区不是连续区间，已按整条声部处理。"));
        return { startTick: null, endTick: null };
    }

    function segmentOf(element) {
        var node = element;
        // Note -> Chord -> Segment，Chord -> Segment，Measure -> Segment
        for (var i = 0; i < 4 && node; i++) {
            if (node.tick !== undefined) {
                return node;
            }
            node = node.parent;
        }
        return null;
    }

    //------------------------------------------------------------------------
    // 遍历音符并判定连音线 / 延音线
    //------------------------------------------------------------------------

    // 延音线（Slur）通过 Note.spannerForward / spannerBack 检测，这两个属性自
    // MuseScore 4.6 起提供；在更早的 4.x 版本里会退回"只识别连音线（Tie）"。
    function spannerHasSlur(note, propertyName) {
        if (!note) {
            return false;
        }
        var list = note[propertyName];
        if (!list || list.length === undefined) {
            root.slurApiAvailable = false;
            return false;
        }
        for (var i = 0; i < list.length; i++) {
            var spanner = list[i];
            if (!spanner) {
                continue;
            }
            if (spanner.name === "slur") {
                return true;
            }
            if (Element.SLUR !== undefined && spanner.type === Element.SLUR) {
                return true;
            }
        }
        return false;
    }

    property bool slurApiAvailable: true
    property int graceNoteCount: 0

    // 按时间顺序收集该声部的和弦。每个槽位记录 tick、时值，以及它是不是
    // "连音/延音的后续音"（continuation）。后续音不分配新音节，从而实现一字多音。
    function collectSlots(staffIdx, voice, range) {
        var slots = [];
        root.slurApiAvailable = true;
        root.graceNoteCount = 0;
        var wantSlurMelisma = slurMelismaEnabled();

        var cursor = curScore.newCursor();
        cursor.track = staffIdx * 4 + voice;
        if (range.startTick !== null) {
            cursor.rewindToTick(range.startTick);
        } else {
            cursor.rewind(Cursor.SCORE_START);
        }

        var openSlurs = 0;
        var guard = 0;
        while (cursor.segment && guard < 200000) {
            guard += 1;
            var element = cursor.element;
            if (element && element.type === Element.CHORD) {
                if (range.endTick !== null && cursor.tick > range.endTick) {
                    break;
                }
                var isGrace = false;
                if (typeof NoteType !== "undefined" && element.noteType !== undefined
                        && element.noteType !== NoteType.NORMAL) {
                    isGrace = true;
                }
                if (isGrace) {
                    // 装饰音不占歌词
                    root.graceNoteCount += 1;
                } else {
                    var note = (element.notes && element.notes.length > 0) ? element.notes[0] : null;
                    var tiedIn = !!(note && note.tieBack);
                    var slurOut = wantSlurMelisma ? spannerHasSlur(note, "spannerForward") : false;
                    var slurIn = wantSlurMelisma ? spannerHasSlur(note, "spannerBack") : false;

                    var continuation = false;
                    if (skipTiesCheck.checked && tiedIn) {
                        continuation = true;
                    }
                    if (wantSlurMelisma) {
                        // 处于已打开的 slur 内部（含 slur 的结束音）→ 后续音；
                        // slur 的起始音此时 openSlurs 仍为 0，因此保持锚点身份。
                        if (openSlurs > 0) {
                            continuation = true;
                        }
                        if (slurOut) {
                            openSlurs += 1;
                        }
                        if (slurIn && openSlurs > 0) {
                            openSlurs -= 1;
                        }
                    }

                    var duration = element.actualDuration ? element.actualDuration : element.duration;
                    slots.push({
                        tick: cursor.tick,
                        dur: duration ? duration.ticks : 0,
                        continuation: continuation,
                        chord: element
                    });
                }
            }
            if (!cursor.next()) {
                break;
            }
        }
        return slots;
    }

    // 把延音线（Slur）也当作"一字多音"处理：只在 slur 的第一个音上填词。
    // 注意这与常见的记谱习惯不同（slur 通常只是连奏，每个音各自一个音节），
    // 因此界面上可以自由开关；关闭时每个音符都会拿到自己的音节。
    function slurMelismaEnabled() {
        return slurMelismaCheck.checked;
    }

    function languageMode() {
        var index = languageCombo.currentIndex;
        return index === 1 ? "zh" : (index === 2 ? "en" : "auto");
    }

    //------------------------------------------------------------------------
    // 写入歌词
    //------------------------------------------------------------------------

    function syllabicCode(name) {
        if (name === "begin") return Lyrics.BEGIN;
        if (name === "middle") return Lyrics.MIDDLE;
        if (name === "end") return Lyrics.END;
        return Lyrics.SINGLE;
    }

    function existingLyricForVerse(chord, verse) {
        var lyrics = chord.lyrics;
        if (!lyrics) {
            return null;
        }
        for (var i = 0; i < lyrics.length; i++) {
            if (lyrics[i].verse === verse) {
                return lyrics[i];
            }
        }
        return null;
    }

    function writeLyric(chord, unit, verse, overwrite, extenderTicks) {
        var old = existingLyricForVerse(chord, verse);
        if (old) {
            if (!overwrite) {
                return false;
            }
            // 先移除再新建：直接改写已有元素不会进入撤销栈，也不会触发重新排版
            chord.remove(old);
        }
        var lyric = newElement(Element.LYRICS);
        lyric.text = unit.text;
        lyric.syllabic = syllabicCode(unit.syllabic);
        lyric.verse = verse;
        if (placementCombo.currentIndex > 0) {
            lyric.placement = placementCombo.currentIndex;
        }
        if (extenderCheck.checked && extenderTicks > 0) {
            lyric.lyricTicks = fraction(extenderTicks, root.ticksPerWholeNote);
        }
        chord.add(lyric);
        return true;
    }

    //------------------------------------------------------------------------
    // 主流程
    //------------------------------------------------------------------------

    function currentUnits() {
        return root.tok.tokenize(lyricsField.text, languageMode());
    }

    function refreshUnitCount() {
        if (lyricsField.text.trim() === "") {
            setStatus(qsTr("剪贴板是空的或不含文本。请先复制歌词，或直接把歌词粘贴到上方文本框。"));
            return;
        }
        var result = currentUnits();
        var language = result.language === "en" ? qsTr("英文") : qsTr("中文/一字一音");
        setStatus(qsTr("识别为%1，共 %2 个音节单元。").arg(language).arg(result.units.length));
    }

    function analyze() {
        var text = lyricsField.text;
        if (text.trim() === "") {
            return { ok: false, message: qsTr("歌词文本为空，无法填词。") };
        }
        if (!curScore) {
            return { ok: false, message: qsTr("没有打开的乐谱。") };
        }

        var tokenized = root.tok.tokenize(text, languageMode());
        var units = tokenized.units;
        if (units.length === 0) {
            return { ok: false, message: qsTr("没有从文本中解析出任何音节单元，请检查语言设置或歌词内容。") };
        }

        var staffIdx = staffSpin.value - 1;
        var voice = voiceSpin.value - 1;
        if (staffIdx >= curScore.ntracks / 4) {
            return { ok: false, message: qsTr("谱表编号超出范围。") };
        }

        var slots = collectSlots(staffIdx, voice, selectionRange());
        if (slots.length === 0) {
            return {
                ok: false,
                message: qsTr("在第 %1 个谱表、第 %2 个声部（%3）没有找到音符。")
                        .arg(staffSpin.value).arg(voiceSpin.value)
                        .arg(useSelectionCheck.checked ? qsTr("选区内") : qsTr("全曲"))
            };
        }

        var plan = root.tok.planFill(units, slots);
        plan.ok = true;
        plan.units = units;
        plan.slots = slots;
        plan.warnings = tokenized.warnings;
        plan.language = tokenized.language;
        return plan;
    }

    function report(plan, applyResult) {
        if (!plan.ok) {
            setStatus(plan.message);
            return;
        }
        var language = plan.language === "en" ? qsTr("英文") : qsTr("中文/一字一音");
        var lines = [];
        lines.push(qsTr("识别为%1：%2 个音节单元，%3 个音符（其中 %4 个是连音/延音的后续音）。")
                   .arg(language).arg(plan.units.length).arg(plan.slotCount).arg(plan.continuationCount));

        if (plan.unusedUnits > 0) {
            lines.push(qsTr("警告：还有 %1 个音节没有对应音符，将被忽略。").arg(plan.unusedUnits));
        }
        if (plan.unfilledNotes > 0) {
            lines.push(qsTr("警告：还有 %1 个音符没有歌词。").arg(plan.unfilledNotes));
        }
        if (applyResult && applyResult.skipped > 0) {
            lines.push(qsTr("已跳过 %1 个带已有歌词的音符。").arg(applyResult.skipped));
        }
        if (applyResult) {
            lines.push(qsTr("完成：写入 %1 个音节。可用 Ctrl+Z 撤销。").arg(applyResult.written));
        }
        if (root.graceNoteCount > 0) {
            lines.push(qsTr("提示：已跳过 %1 个装饰音。").arg(root.graceNoteCount));
        }
        if (plan.warnings.length > 0) {
            for (var i = 0; i < plan.warnings.length; i++) {
                lines.push(qsTr("提示：") + plan.warnings[i]);
            }
        }
        if (slurMelismaEnabled() && !root.slurApiAvailable) {
            lines.push(qsTr("提示：当前 MuseScore 版本读不到延音线（Slur 支持需 4.6+），只有连音线（Tie）被识别。"));
        }
        setStatus(lines.join("\n"));
    }

    function run() {
        var plan = analyze();
        if (!plan.ok) {
            setStatus(plan.message);
            return;
        }
        if (strictCheck.checked && (plan.unusedUnits > 0 || plan.unfilledNotes > 0)) {
            report(plan, false);
            setStatus(qsTr("音节数与音符数不一致，已按设置中止。\n") + statusText);
            return;
        }

        var verse = verseSpin.value - 1;
        var overwrite = existingCombo.currentIndex === 0;
        var written = 0;
        var skipped = 0;
        var lastChord = null;

        curScore.startCmd();
        root.cmdOpen = true;
        try {
            // 先清掉所有连音/延音后续音上的旧歌词，才能真正"留空"
            for (var c = 0; c < plan.slots.length; c++) {
                if (!plan.slots[c].continuation) {
                    continue;
                }
                var stale = existingLyricForVerse(plan.slots[c].chord, verse);
                if (stale) {
                    plan.slots[c].chord.remove(stale);
                }
            }
            for (var a = 0; a < plan.assignments.length; a++) {
                var assignment = plan.assignments[a];
                var chord = plan.slots[assignment.slotIndex].chord;
                if (writeLyric(chord, plan.units[assignment.unitIndex], verse, overwrite,
                               assignment.extenderTicks)) {
                    written += 1;
                } else {
                    skipped += 1;
                }
                lastChord = chord;
            }
            curScore.endCmd();
            root.cmdOpen = false;
        } catch (error) {
            if (root.cmdOpen) {
                curScore.endCmd(true);
                root.cmdOpen = false;
            }
            setStatus(qsTr("写入歌词时出错，改动已撤销：%1").arg(error));
            console.log("LyricsFiller error: " + error);
            return;
        }

        if (lastChord) {
            curScore.selection.clear();
            curScore.selection.select(lastChord);
        }
        report(plan, { written: written, skipped: skipped });
    }

    function setStatus(message) {
        root.statusText = message;
    }
}
