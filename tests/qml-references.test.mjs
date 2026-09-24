// 检查 qml 里的标识符引用。
//
// QML 的声明式部分没法用 JS 解析器读，所以这里退而求其次：
// 收集文件里所有"被定义过"的名字（id / property / function / var / 形参），
// 凡是拿来做成员访问 `X.y` 或下标访问 `X[y]` 的 X 不在其中，就报出来。
// 这能抓到控件 id 改名后忘改引用、属性名拼错这一类问题。

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

import { stripLiterals, withoutImports } from "./qml-scan.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const QML = join(HERE, "..", "LyricsFiller", "lyricsfiller.qml");
const source = readFileSync(QML, "utf8");
const code = withoutImports(stripLiterals(source));

// Qt / MuseScore 插件运行时提供的全局名
const BUILTINS = new Set([
    "Qt", "Math", "JSON", "console", "Boolean", "Number", "String", "Array",
    "Object", "parseInt", "parseFloat", "isNaN", "undefined", "Infinity",
    "RegExp", "Error",
    // QML 内置作用域：声明式代码里合法，但不是本文件定义的 JS 变量
    "Layout", "Text", "TextEdit", "Rectangle", "border", "anchors", "parent",
    "Component",
    // MuseScore 3.0 兼容层
    "curScore", "api", "Element", "Lyrics", "Cursor", "NoteType",
    "newElement", "removeElement", "fraction", "cmd", "quit",
    // Muse.Ui 单例
    "ui"
]);

const KEYWORDS = new Set([
    "if", "else", "return", "while", "for", "typeof", "new", "case", "in",
    "of", "do", "switch", "try", "catch", "finally", "throw", "delete", "void"
]);

const declared = new Set();
const collect = (re) => {
    for (const match of code.matchAll(re)) {
        declared.add(match[1]);
    }
};

collect(/\bid:\s*(\w+)/g);
collect(/\b(?:readonly\s+)?property\s+\S+\s+(\w+)/g);
collect(/\bfunction\s+(\w+)\s*\(/g);
collect(/\bvar\s+(\w+)/g);
for (const match of code.matchAll(/\bfunction\s+\w+\s*\(([^)]*)\)/g)) {
    for (const part of match[1].split(",")) {
        const name = part.trim();
        if (name) declared.add(name);
    }
}

const ids = [...source.matchAll(/^\s*id:\s*(\w+)/gm)].map((m) => m[1]);

test("所有 id 唯一", () => {
    const duplicated = ids.filter((id, index) => ids.indexOf(id) !== index);
    assert.deepEqual(duplicated, [], `重复的 id: ${duplicated.join(", ")}`);
});

test("覆盖了核心控件的 id", () => {
    for (const required of [
        "lyricsField", "languageCombo", "verseSpin", "staffSpin", "voiceSpin",
        "useSelectionCheck", "skipTiesCheck", "slurMelismaCheck", "extenderCheck",
        "existingCombo", "placementCombo", "strictCheck", "root", "window"
    ]) {
        assert.ok(ids.includes(required), `缺少 id: ${required}`);
    }
});

test("成员访问的基名都有定义", () => {
    const unknown = [];
    // 只取成员链的根：`a.b.c` 里只检查 a，避免把中间环节当引用
    for (const match of code.matchAll(/(^|[^.\w$])([A-Za-z_$][\w$]*)\s*(?=[.\[])/g)) {
        const base = match[2];
        if (BUILTINS.has(base) || declared.has(base) || KEYWORDS.has(base)) continue;
        if (/^\d/.test(base)) continue;
        if (!unknown.includes(base)) unknown.push(base);
    }
    assert.deepEqual(unknown, [], `未定义的引用: ${unknown.join(", ")}`);
});

test("入口与关键函数都已定义", () => {
    for (const name of [
        "buildTokenizer", "readClipboard", "syncFromSelection", "selectionRange",
        "collectSlots", "writeLyric", "analyze", "report", "applyLyrics",
        "setStatus",
        "refreshUnitCount", "spannerHasSlur", "segmentOf", "syllabicCode",
        "existingLyricForVerse", "languageMode", "slurMelismaEnabled", "currentUnits"
    ]) {
        assert.match(code, new RegExp(`function\\s+${name}\\s*\\(`), `缺少函数 ${name}`);
    }
});

test("每个声明的控件 id 都被用到", () => {
    const unused = ids.filter((id) => {
        if (id === "root" || id === "window") return false;
        // 只统计 JS 里的引用，声明处（id: xxx 自身）不算
        const uses = [...code.matchAll(new RegExp(`\\b${id}\\b`, "g"))].length;
        return uses <= 1;
    });
    assert.deepEqual(unused, [], `定义了但没用到的 id: ${unused.join(", ")}`);
});

// MuseScore 根类型（src/engraving/api/v1/qmlpluginapi.h）已有的成员。
// 插件里再声明同名函数或属性会与之冲突：例如自己写 function run() 会顶掉
// run 信号，导致 onRun 处理器无法生成，插件直接加载失败且不报在界面上。
const RESERVED = [
    "menuPath", "title", "description", "version", "pluginType", "dockArea",
    "requiresScore", "thumbnailName", "categoryCode", "division",
    "mscoreVersion", "mscoreMajorVersion", "mscoreMinorVersion",
    "mscoreUpdateVersion", "mscoreDPI", "curScore", "scores",
    "run", "closeRequested", "scoreStateChanged",
    "newScore", "newElement", "removeElement", "cmd", "newQProcess",
    "writeScore", "readScore", "closeScore", "log", "logn", "log2",
    "openLog", "closeLog", "fraction", "fractionFromTicks",
    "ornamentInterval", "interval", "intervalFromOrnamentInterval", "quit"
];

test("没有声明与 MuseScore 根类型同名的函数或属性", () => {
    const mine = new Set();
    for (const m of code.matchAll(/\bfunction\s+(\w+)\s*\(/g)) mine.add(m[1]);
    for (const m of code.matchAll(/\b(?:readonly\s+)?property\s+\S+\s+(\w+)/g)) mine.add(m[1]);
    const clashes = [...mine].filter((name) => RESERVED.includes(name));
    assert.deepEqual(clashes, [], `与根类型成员重名: ${clashes.join(", ")}`);
});
