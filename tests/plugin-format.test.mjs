// 校验插件能否被 MuseScore 4.x 发现。
//
// MuseScore 不读清单文件，而是用纯文本逐行解析 .qml 头部
// （见 src/framework/extensions/internal/legacy/extpluginsloader.cpp）。
// 只要有一个必需属性没被解析到，插件就不会出现在列表里，
// 所以这里复刻它的解析规则来自检。

import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

import { stripLiterals } from "./qml-scan.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");

const REQUIRED = [
    "title",
    "description",
    "pluginType",
    "categoryCode",
    "thumbnailName",
    "requiresScore",
    "version"
];

function qmlFiles(dir) {
    const found = [];
    for (const entry of readdirSync(dir)) {
        const full = join(dir, entry);
        if (entry === "node_modules" || entry === ".git") continue;
        if (statSync(full).isDirectory()) {
            found.push(...qmlFiles(full));
        } else if (entry.endsWith(".qml")) {
            found.push(full);
        }
    }
    return found;
}

// 与 C++ 侧 dropQuotes() 对齐
function dropQuotes(str) {
    let s = str;
    while (s.endsWith(";")) s = s.slice(0, -1);
    if (s.length < 3) return "";
    if (s.startsWith('qsTr("') && s.endsWith('")')) return s.slice(6, -2);
    if (s.startsWith('"') && s.endsWith('"')) return s.slice(1, -1);
    return s;
}

// 复刻 parseManifest()：逐行扫描，遇到注释跳过，遇到第一个以 "{" 结尾的行
// （即 "MuseScore {"）开始收集属性，再遇到以 "{" 结尾的行就停止。
function parseManifestHeader(content) {
    const props = {};
    let inside = false;
    for (const rawLine of content.split("\n")) {
        const line = rawLine.trim();
        if (line.startsWith("/")) continue;
        if (line.endsWith("{")) {
            if (inside) break;
            inside = true;
            continue;
        }
        for (const key of REQUIRED) {
            const prefix = `${key}:`;
            if (line.startsWith(prefix)) {
                props[key] = dropQuotes(line.slice(prefix.length).trim());
            }
        }
    }
    return props;
}

// 词法元素先由 stripLiterals() 处理掉，这里只判断配平
function balance(strippedSource) {
    const PAIRS = { "}": "{", "]": "[", ")": "(" };
    const stack = [];
    let line = 1;
    for (const ch of strippedSource) {
        if (ch === "\n") {
            line += 1;
            continue;
        }
        if (ch === "{" || ch === "[" || ch === "(") {
            stack.push({ ch, line });
        } else if (ch === "}" || ch === "]" || ch === ")") {
            const top = stack.pop();
            if (!top || top.ch !== PAIRS[ch]) {
                return `line ${line}: unexpected '${ch}'`;
            }
        }
    }
    if (stack.length > 0) {
        const top = stack[stack.length - 1];
        return `line ${top.line}: unclosed '${top.ch}'`;
    }
    return null;
}

const files = qmlFiles(join(ROOT, "LyricsFiller"));

test("插件目录里有 .qml 文件", () => {
    assert.ok(files.length > 0, "找不到 .qml 文件");
});

for (const file of files) {
    const content = readFileSync(file, "utf8");
    const short = file.slice(ROOT.length + 1);

    test(`${short}: 被 MuseScore 识别为插件`, () => {
        assert.ok(content.includes("MuseScore"), "文件里必须出现 MuseScore 字样");
        assert.ok(content.indexOf("{") > 0, "第一个 { 不能在第 0 个字符");
    });

    test(`${short}: 7 个必需元数据齐全`, () => {
        const props = parseManifestHeader(content);
        const missing = REQUIRED.filter((key) => !props[key]);
        assert.deepEqual(missing, [], `缺少属性: ${missing.join(", ")}`);
        assert.equal(props.pluginType, "dialog", "带界面的插件必须声明 pluginType: dialog");
        assert.equal(props.categoryCode, "lyrics");
        assert.ok(props.version.length > 0);
    });

    test(`${short}: 括号配平`, () => {
        assert.equal(balance(stripLiterals(content)), null);
    });

    test(`${short}: 引用的缩略图存在`, () => {
        const props = parseManifestHeader(content);
        const stat = statSync(join(ROOT, "LyricsFiller", props.thumbnailName), {
            throwIfNoEntry: false
        });
        assert.ok(stat, `缺少缩略图 ${props.thumbnailName}`);
    });
}

// 发版流程建立在"git 标签 vX.Y.Z == 插件 version == package.json version"之上，
// 三者不一致会让 Release 标题、下载文件名和插件里显示的版本号互相对不上。
test("version 三处一致且是 x.y.z 形式", () => {
    const pkg = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf8"));
    assert.match(pkg.version, /^\d+\.\d+\.\d+$/, "package.json 的 version 必须是 x.y.z");
    for (const file of files) {
        const props = parseManifestHeader(readFileSync(file, "utf8"));
        assert.equal(props.version, pkg.version,
            `${file.slice(ROOT.length + 1)} 的 version 与 package.json 不一致`);
    }
});
