// 文档内部链接自检。
//
// README / CHANGELOG / docs/DEVELOPMENT.md 之间互相引用，拆分会让锚点失效。
// 这类链接坏了不影响 npm test 的绿灯，只有点进去的人才发现，所以单独测。

import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const DOCS = ["README.md", "CHANGELOG.md", join("docs", "DEVELOPMENT.md")];

// 与 GitHub 的锚点规则对齐：转小写、去掉标点（字母、数字、下划线、连字符、空格保留）、
// 最后空格换成 "-"。顺序不能反：先把空格删掉，"30 秒上手" 会变成 "30秒上手" 而对不上链接。
const anchor = (heading) =>
    heading.toLowerCase().trim()
        .replace(/[^0-9a-z_\p{L}\p{N} -]/gu, "")
        .replace(/ /g, "-");

const parsed = DOCS.map((rel) => {
    const text = readFileSync(join(ROOT, rel), "utf8");
    const headings = new Set(
        [...text.matchAll(/^#{1,6}\s+(.+)$/gm)].map((m) => anchor(m[1]))
    );
    return { rel, text, headings };
});

test("每个文档都存在", () => {
    for (const rel of DOCS) {
        assert.ok(existsSync(join(ROOT, rel)), `缺少文档 ${rel}`);
    }
});

test("文内锚点指向真实存在的小节", () => {
    const broken = [];
    for (const { rel, text, headings } of parsed) {
        for (const m of text.matchAll(/\[[^\]]*\]\((#[^)\s]+)\)/g)) {
            if (!headings.has(m[1].slice(1))) broken.push(`${rel} -> ${m[1]}`);
        }
    }
    assert.deepEqual(broken, [], `锚点失效:\n${broken.join("\n")}`);
});

test("相对链接指向存在的文件", () => {
    const broken = [];
    for (const { rel, text } of parsed) {
        const here = dirname(join(ROOT, rel));
        for (const m of text.matchAll(/\[[^\]]*\]\(([^)\s#]+)(?:#[^)\s]*)?\)/g)) {
            const target = m[1];
            if (/^[a-z]+:\/\//.test(target) || target.startsWith("mailto:")) continue;
            if (!existsSync(join(here, target))) broken.push(`${rel} -> ${target}`);
        }
    }
    assert.deepEqual(broken, [], `文件链接失效:\n${broken.join("\n")}`);
});
