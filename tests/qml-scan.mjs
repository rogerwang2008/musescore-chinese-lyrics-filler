// 供测试使用的小型 QML/JS 词法扫描器。
//
// 把注释、字符串字面量和正则字面量替换成中性占位符（保留换行以维持行号），
// 这样后面的括号配平和标识符扫描就不会被 "/[^']+$/" 这类内容带偏。

const REGEX_ALLOWED_AFTER = new Set(["=", "(", "[", "{", "!", "&", "|", "?", ":", ";", ",", "+", "-", "*", "%", "<", ">", "\n", ""]);

export function stripLiterals(source) {
    let out = "";
    let i = 0;
    let lastMeaningful = "";

    const push = (text) => {
        out += text;
        const trimmed = text.trimEnd();
        if (trimmed.length > 0) lastMeaningful = trimmed[trimmed.length - 1];
    };

    while (i < source.length) {
        const ch = source[i];
        const next = source[i + 1];

        if (ch === "/" && next === "/") {
            while (i < source.length && source[i] !== "\n") i += 1;
            continue;
        }

        if (ch === "/" && next === "*") {
            i += 2;
            while (i < source.length && !(source[i] === "*" && source[i + 1] === "/")) {
                if (source[i] === "\n") out += "\n";
                i += 1;
            }
            i += 2;
            continue;
        }

        if (ch === '"' || ch === "'") {
            i += 1;
            while (i < source.length && source[i] !== ch) {
                if (source[i] === "\\") i += 1;
                i += 1;
            }
            i += 1;
            push('""');
            continue;
        }

        // 除号与正则的区分：标识符、数字、")"、"]" 之后的 "/" 是除号
        const looksLikeValue = /[A-Za-z0-9_$)\]]/.test(lastMeaningful);
        if (ch === "/" && !looksLikeValue && REGEX_ALLOWED_AFTER.has(lastMeaningful)) {
            i += 1;
            let inClass = false;
            while (i < source.length) {
                const c = source[i];
                if (c === "\n") break;
                if (c === "\\") {
                    i += 2;
                    continue;
                }
                if (c === "[") inClass = true;
                else if (c === "]") inClass = false;
                else if (c === "/" && !inClass) {
                    i += 1;
                    break;
                }
                i += 1;
            }
            // 跳过正则修饰符
            while (i < source.length && /[gimsuy]/.test(source[i])) i += 1;
            push("REGEX");
            continue;
        }

        out += ch;
        if (!/\s/.test(ch)) lastMeaningful = ch;
        i += 1;
    }
    return out;
}

// 去掉 import 行，避免 "import QtQuick.Layouts" 被当成成员访问
export function withoutImports(strippedSource) {
    return strippedSource
        .split("\n")
        .map((line) => (/^\s*import\s/.test(line) ? "" : line))
        .join("\n");
}
