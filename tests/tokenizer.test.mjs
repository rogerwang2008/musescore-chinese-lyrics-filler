// 分词器单元测试。
//
// 测试对象不是副本，而是直接从 lyricsfiller.qml 里截取的
// TOKENIZER-BEGIN / TOKENIZER-END 之间的代码，
// 保证跑过的逻辑就是插件真正会执行的逻辑。

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

const HERE = dirname(fileURLToPath(import.meta.url));
const QML = join(HERE, "..", "LyricsFiller", "lyricsfiller.qml");

const source = readFileSync(QML, "utf8");
const BEGIN = "/* =====[TOKENIZER-BEGIN]===== */";
const END = "/* =====[TOKENIZER-END]===== */";
const from = source.indexOf(BEGIN);
const to = source.indexOf(END);
assert.ok(from >= 0 && to > from, "在 qml 里找不到 TOKENIZER 标记");

// 这里的输入只有本仓库自己提交的 .qml，不存在外部不可信数据，
// 因此可以安全地把截取的代码段编译成函数来执行。
const tok = new Function(`${source.slice(from + BEGIN.length, to)}\nreturn buildTokenizer();`)();

// 把结果压成 "文本:音节类型" 的紧凑形式，方便断言和看差异
const shape = (units) => units.map((u) => `${u.text}:${u.syllabic}`).join(" ");

// ---------------------------------------------------------------- 中文

test("中文：一字一音，标点与空白丢弃", () => {
    const r = tok.tokenizeChinese("床前明月光，\n疑是地上霜。");
    assert.equal(shape(r.units), "床:single 前:single 明:single 月:single 光:single 疑:single 是:single 地:single 上:single 霜:single");
});

test("中文：[方括号] 内的字合并成一个音节单元", () => {
    const r = tok.tokenizeChinese("[测试] 你好");
    assert.equal(shape(r.units), "测试:single 你:single 好:single");
});

test("中文：括号内的空白被压平，标点被保留", () => {
    const r = tok.tokenizeChinese("[测试   哦，耶]下一");
    assert.equal(shape(r.units), "测试 哦，耶:single 下:single 一:single");
});

test("中文：括号内是英文时整体作为一个单元", () => {
    const r = tok.tokenizeChinese("唱[la la]吧");
    assert.equal(shape(r.units), "唱:single la la:single 吧:single");
});

test("中文：夹杂的英文按单词聚合", () => {
    const r = tok.tokenizeChinese("hello你好world");
    assert.equal(shape(r.units), "hello:single 你:single 好:single world:single");
});

test("中文：括号未闭合时给出警告且不崩溃", () => {
    const r = tok.tokenizeChinese("[测试 你好");
    assert.equal(r.warnings.length, 1);
    assert.match(r.warnings[0], /缺少配对/);
    assert.ok(shape(r.units).includes("你:single"));
});

test("中文：空括号被忽略并警告", () => {
    const r = tok.tokenizeChinese("[]你好");
    assert.equal(r.warnings.length, 1);
    assert.equal(shape(r.units), "你:single 好:single");
});

test("中文：假名同样一字一音", () => {
    const r = tok.tokenizeChinese("さくら");
    assert.equal(shape(r.units), "さ:single く:single ら:single");
});

// ---------------------------------------------------------------- 英文

test("英文：空格分词，无连字符即为 single", () => {
    const r = tok.tokenizeEnglish("Silence is golden");
    assert.equal(shape(r.units), "Silence:single is:single golden:single");
});

test("英文：连字符拆音节并决定 syllabic", () => {
    const r = tok.tokenizeEnglish("re-action");
    assert.equal(shape(r.units), "re:begin action:end");
});

test("英文：三个以上音节 begin/middle/end", () => {
    const r = tok.tokenizeEnglish("in-com-pre-hen-si-ble");
    assert.equal(
        shape(r.units),
        "in:begin com:middle pre:middle hen:middle si:middle ble:end"
    );
});

test("英文：连字符两侧的空格不影响拆分", () => {
    assert.equal(shape(tok.tokenizeEnglish("Si - lence").units), "Si:begin lence:end");
    assert.equal(shape(tok.tokenizeEnglish("re- action").units), "re:begin action:end");
    assert.equal(shape(tok.tokenizeEnglish("ev-\nery").units), "ev:begin ery:end");
});

test("英文：词首/词尾连字符", () => {
    assert.equal(shape(tok.tokenizeEnglish("-est").units), "est:end");
    assert.equal(shape(tok.tokenizeEnglish("hap-").units), "hap:begin");
});

test("英文：[test word] 合并为一个单元", () => {
    const r = tok.tokenizeEnglish("sing [test word] now");
    assert.equal(shape(r.units), "sing:single test word:single now:single");
});

test("英文：撇号与标点不拆词", () => {
    const r = tok.tokenizeEnglish("Singin' in the \"rain\"");
    assert.equal(shape(r.units), "Singin':single in:single the:single rain:single");
});

test("英文：单独的破折号不产生音节", () => {
    const r = tok.tokenizeEnglish("Hello — world");
    assert.equal(shape(r.units), "Hello:single world:single");
});

test("英文：重音字母视作词内字符", () => {
    const r = tok.tokenizeEnglish("l'été café");
    assert.equal(shape(r.units), "l'été:single café:single");
});

// ---------------------------------------------------------- 语言自动识别

test("自动识别：纯中文走中文规则", () => {
    assert.equal(tok.detectLanguage("床前明月光"), "zh");
    assert.equal(tok.tokenize("床前明月光", "auto").language, "zh");
});

test("自动识别：纯英文走英文规则", () => {
    assert.equal(tok.detectLanguage("Silence is golden"), "en");
});

test("自动识别：中文为主时按中文（英文缩写不改变判断）", () => {
    assert.equal(tok.detectLanguage("你好 OK 世界"), "zh");
});

test("手动指定语言时忽略自动识别", () => {
    assert.equal(tok.tokenize("你好", "en").language, "en");
    // 中文模式下连字符不是音节边界，拉丁字母按词聚合
    assert.equal(shape(tok.tokenize("re-action", "zh").units), "re:single action:single");
    assert.equal(shape(tok.tokenize("re-action", "en").units), "re:begin action:end");
});

// ---------------------------------------------------------------- 排布

const slots = (...flags) => flags.map((continuation, i) => ({
    tick: i * 1440,
    dur: 1440,
    continuation
}));

test("planFill：音节与锚点一一对应", () => {
    const units = tok.tokenize("床前明月光", "zh").units;
    const p = tok.planFill(units, slots(false, false, false, false, false));
    assert.equal(p.assignments.length, 5);
    assert.equal(p.unusedUnits, 0);
    assert.equal(p.unfilledNotes, 0);
    assert.deepEqual(p.assignments.map((a) => a.slotIndex), [0, 1, 2, 3, 4]);
});

test("planFill：连音线后续音不消耗音节", () => {
    const units = tok.tokenize("床前", "zh").units;
    // 床~~~ 前
    const p = tok.planFill(units, slots(false, true, true, false));
    assert.equal(p.anchorCount, 2);
    assert.equal(p.continuationCount, 2);
    assert.deepEqual(p.assignments.map((a) => a.slotIndex), [0, 3]);
});

test("planFill：音节多于音符时报告剩余", () => {
    const units = tok.tokenize("床前明月光", "zh").units;
    const p = tok.planFill(units, slots(false, false));
    assert.equal(p.assignments.length, 2);
    assert.equal(p.unusedUnits, 3);
    assert.equal(p.unfilledNotes, 0);
});

test("planFill：音符多于音节时报告未填", () => {
    const units = tok.tokenize("床前", "zh").units;
    const p = tok.planFill(units, slots(false, false, false));
    assert.equal(p.assignments.length, 2);
    assert.equal(p.unusedUnits, 0);
    assert.equal(p.unfilledNotes, 1);
});

test("planFill：延长线时值覆盖整段 melisma", () => {
    const units = tok.tokenize("床", "zh").units;
    const p = tok.planFill(units, slots(false, true, true));
    // 锚点 tick 0，最后一个后续音 tick 2*1440 + dur 1440 = 4320
    assert.equal(p.assignments[0].extenderTicks, 4320);
    assert.equal(p.assignments[0].melismaLength, 3);
});

test("planFill：非 melisma 音符的延长线时值为 0", () => {
    const units = tok.tokenize("床前", "zh").units;
    const p = tok.planFill(units, slots(false, false));
    assert.equal(p.assignments[0].extenderTicks, 0);
    assert.equal(p.assignments[1].extenderTicks, 0);
});

test("planFill：melisma 段在遇到下一个锚点时结束", () => {
    const units = tok.tokenize("床前", "zh").units;
    // 床~~ 前 明（明是第二个锚点，不应被并入第一段）
    const p = tok.planFill(units, slots(false, true, false));
    assert.equal(p.assignments[0].extenderTicks, 2880);
    assert.equal(p.assignments[1].extenderTicks, 0);
});

test("planFill：全部是后续音时不产生任何分配", () => {
    const units = tok.tokenize("床", "zh").units;
    const p = tok.planFill(units, slots(true, true));
    assert.equal(p.assignments.length, 0);
    assert.equal(p.anchorCount, 0);
});
