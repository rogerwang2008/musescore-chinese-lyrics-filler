// 安装脚本的守门测试。
//
// install.bat 必须保持纯 ASCII + CRLF + 无 BOM：cmd.exe 按字节偏移读脚本，
// 文件里一旦出现多字节字符，其后的行就会被错误切分，REM/echo 的尾巴会被当成
// 命令执行（就是之前那个 "'?>' 不是内部或外部命令" 的报错来源）。
// 这个约束编辑器很容易无声破坏，所以用测试钉住。

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");

const batRaw = readFileSync(join(ROOT, "install.bat"));
const bat = batRaw.toString("utf8");

test("install.bat 是纯 ASCII（多字节会让 cmd 解析错位）", () => {
    const bad = [];
    for (let i = 0; i < batRaw.length; i++) {
        if (batRaw[i] > 0x7f) bad.push(`字节 ${i}: 0x${batRaw[i].toString(16)}`);
    }
    assert.deepEqual(bad.slice(0, 5), [], `install.bat 里出现了非 ASCII 字节: ${bad.slice(0, 5).join(", ")}`);
});

test("install.bat 使用 CRLF 且没有 BOM", () => {
    assert.notEqual(bat.charCodeAt(0), 0xFEFF, "cmd 会把 BOM 当成第一条命令的一部分");
    const lines = bat.split("\n");
    const bad = lines
        .map((line, n) => ({ line, n }))
        // 最后一行允许没有换行符
        .filter(({ line, n }) => line.length > 0 && n < lines.length - 1 && !line.endsWith("\r"));
    assert.deepEqual(bad.map(({ n }) => n + 1), [], `这些行不是 CRLF 结尾: ${bad.map(({ n }) => n + 1).join(", ")}`);
});

test("install.bat 的 echo 行不含未转义的 cmd 元字符", () => {
    // echo 行里没转义的 > 或 < 会变成重定向（还会顺手创建文件），& 会串联命令。
    // 允许的形式只有 "| findstr ... >nul" 这类有意为之的管道。
    const ALLOWED_PIPE = /\| findstr/;
    const offenders = [];
    for (const line of bat.split(/\r?\n/)) {
        if (!/^\s*echo\b/.test(line)) continue;
        const payload = line.replace(/^\s*echo\b\.?\s?/, "");
        if ((/[<>]/.test(payload) || payload.includes("&&")) && !ALLOWED_PIPE.test(payload)) {
            offenders.push(line.trim());
        }
    }
    assert.deepEqual(offenders, [], `echo 行里有未转义的元字符:\n${offenders.join("\n")}`);
});

test("install.sh 在 mkdir 之前先校验目标路径", () => {
    const sh = readFileSync(join(ROOT, "install.sh"), "utf8");
    const guard = sh.indexOf('|| [ "$DEST" = "/" ]');
    const mk = sh.indexOf("mkdir -p");
    assert.ok(guard > 0, "找不到目标路径校验");
    assert.ok(mk > 0, "找不到 mkdir");
    assert.ok(guard < mk, "路径校验必须在 mkdir 之前，否则根目录会先被创建");
});
