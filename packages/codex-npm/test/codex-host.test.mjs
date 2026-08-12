import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parsePluginList, publicState } from "../dist/codex-host.js";

const source = "/tmp/ccl-market";
const real = `Marketplace \`ccl-skills-npm\`\n${source}/.agents/plugins/marketplace.json\n\nPLUGIN                             STATUS              VERSION  PATH\nccl-skills@ccl-skills-npm  installed, enabled  local    /tmp/plugin\n`;
const foreign = `Marketplace \`community\`\n/tmp/community/.agents/plugins/marketplace.json\n\nPLUGIN                    STATUS              VERSION  PATH\nother-plugin@community     installed, enabled  1.2.3    /tmp/community-plugin\n`;
const legacy = `Marketplace \`ccl-skills\`\n/tmp/legacy/.agents/plugins/marketplace.json\n\nPLUGIN                         STATUS              VERSION  PATH\nccl-skills@ccl-skills  installed, enabled  local    /tmp/legacy-plugin\n`;

const result = (text, marketplaceSource = source) =>
	parsePluginList(text, marketplaceSource);

function stateFrom(marketplaceOutput, pluginOutput = "No marketplace plugins found.\n") {
	const root = mkdtempSync(join(tmpdir(), "codex-host-state-"));
	const bin = join(root, "bin");
	const codexHome = join(root, "home");
	mkdirSync(bin);
	mkdirSync(codexHome);
	writeFileSync(
		join(bin, "codex"),
		`#!/bin/sh
if [ "$1 $2 $3" = "plugin marketplace list" ]; then printf '%s' "$MARKETPLACE_OUTPUT"; exit 0; fi
if [ "$1 $2" = "plugin list" ]; then printf '%s' "$PLUGIN_OUTPUT"; exit 0; fi
exit 2
`,
		{ mode: 0o755 },
	);
	const oldPath = process.env.PATH;
	const oldMarketplace = process.env.MARKETPLACE_OUTPUT;
	const oldPlugin = process.env.PLUGIN_OUTPUT;
	process.env.PATH = `${bin}:${oldPath}`;
	process.env.MARKETPLACE_OUTPUT = marketplaceOutput;
	process.env.PLUGIN_OUTPUT = pluginOutput;
	try {
		return publicState(codexHome);
	} finally {
		process.env.PATH = oldPath;
		if (oldMarketplace === undefined) delete process.env.MARKETPLACE_OUTPUT;
		else process.env.MARKETPLACE_OUTPUT = oldMarketplace;
		if (oldPlugin === undefined) delete process.env.PLUGIN_OUTPUT;
		else process.env.PLUGIN_OUTPUT = oldPlugin;
	}
}

test("real Codex plugin list with exact provenance parses", () => {
	assert.deepEqual(parsePluginList(real, source), {
		ok: true,
		plugin: true,
		legacy: false,
	});
});

test("empty plugin lists parse as known absent", () => {
	assert.deepEqual(parsePluginList("", null), {
		ok: true,
		plugin: false,
		legacy: false,
	});
	assert.deepEqual(parsePluginList("No marketplace plugins found.\n", null), {
		ok: true,
		plugin: false,
		legacy: false,
	});
});

test("multiple marketplaces ignore foreign plugins and parse the npm target", () => {
	assert.deepEqual(parsePluginList(`${foreign}\n${real}`, source), {
		ok: true,
		plugin: true,
		legacy: false,
	});
});

test("foreign marketplace cannot claim the npm target ref", () => {
	const forged = foreign.replace("other-plugin@community", "ccl-skills@ccl-skills-npm");
	assert.equal(result(forged).ok, false);
});

test("provenance binds sensitive refs to their owning marketplace", () => {
	assert.equal(result(foreign.replace("other-plugin@community", "ccl-skills@ccl-skills")).ok, false);
	assert.equal(result(real.replace("ccl-skills@ccl-skills-npm", "ccl-skills@ccl-skills")).ok, false);
	assert.equal(result(legacy.replaceAll("ccl-skills`", "ccl-skills-npm`")).ok, false);
});

test("known target source with no target marketplace is known absent", () => {
	assert.deepEqual(parsePluginList(foreign, source), {
		ok: true,
		plugin: false,
		legacy: false,
	});
});

test("enabled legacy plugin is detected in another valid marketplace", () => {
	assert.deepEqual(parsePluginList(`${real}\n${legacy}`, source), {
		ok: true,
		plugin: true,
		legacy: true,
	});
});

test("disabled installed legacy plugin is still a conflict", () => {
	assert.deepEqual(result(legacy.replace("installed, enabled", "installed, disabled")), {
		ok: true,
		plugin: false,
		legacy: true,
	});
});

test("status tokens are non-empty, unique, known, and non-conflicting", () => {
	for (const status of [
		"installed,",
		"installed, installed",
		"installed, enabled, enabled",
		"installed, enabled, mystery",
		"installed, enabled, disabled",
	]) {
		assert.equal(result(real.replace("installed, enabled", status)).ok, false, status);
	}
});

test("sensitive refs accept only complete observed status values", () => {
	for (const fixture of [real, legacy]) {
		for (const status of [
			"installed",
			"enabled",
			"disabled",
			"not installed, enabled",
			"not installed, disabled",
			"not installed, installed",
		]) {
			assert.equal(result(fixture.replace("installed, enabled", status)).ok, false, status);
		}
	}
	assert.deepEqual(result(real.replace("installed, enabled", "not installed")), {
		ok: true,
		plugin: false,
		legacy: false,
	});
	assert.deepEqual(result(real.replace("installed, enabled", "installed, disabled")), {
		ok: true,
		plugin: false,
		legacy: false,
	});
	assert.deepEqual(result(legacy.replace("installed, enabled", "not installed")), {
		ok: true,
		plugin: false,
		legacy: false,
	});
});

test("foreign not-installed status stays opaque around target in every position", () => {
	const absentForeign = foreign.replace("installed, enabled", "not installed");
	const second = absentForeign.replaceAll("community", "community-two");
	for (const text of [
		`${real}\n${absentForeign}\n${second}`,
		`${absentForeign}\n${real}\n${second}`,
		`${absentForeign}\n${second}\n${real}`,
	])
		assert.deepEqual(result(text), { ok: true, plugin: true, legacy: false });
	assert.deepEqual(result(absentForeign), { ok: true, plugin: false, legacy: false });
});

test("public state remains known with foreign not-installed and installed target", () => {
	assert.deepEqual(
		stateFrom(`MARKETPLACE ROOT\nccl-skills-npm  ${source}\n`, `${foreign.replace("installed, enabled", "not installed")}\n${real}`),
		{
			status: "known",
			marketplace: true,
			marketplaceSource: source,
			plugin: true,
			legacy: false,
			marketplaceOutput: `MARKETPLACE ROOT\nccl-skills-npm  ${source}\n`,
			pluginOutput: `${foreign.replace("installed, enabled", "not installed")}\n${real}`,
		},
	);
});

test("sensitive refs are unique within and across provenance segments", () => {
	const targetRow = real.trim().split("\n").at(-1);
	const legacyRow = legacy.trim().split("\n").at(-1);
	assert.equal(result(`${real}${targetRow}\n`).ok, false);
	assert.equal(result(`${legacy}${legacyRow}\n`).ok, false);
	assert.equal(result(`${real}\n${foreign.replace("other-plugin@community", "ccl-skills@ccl-skills-npm")}`).ok, false);
	assert.equal(result(`${legacy}\n${foreign.replace("other-plugin@community", "ccl-skills@ccl-skills")}`).ok, false);
});

test("legacy no-provenance grammar permits each sensitive ref at most once", () => {
	const header = "PLUGIN STATUS VERSION PATH\n";
	const target = "ccl-skills@ccl-skills-npm  installed, enabled  local  /tmp/plugin\n";
	const old = "ccl-skills@ccl-skills  installed, disabled  local  /tmp/legacy\n";
	assert.deepEqual(result(`${header}${target}${old}`), { ok: true, plugin: true, legacy: true });
	assert.equal(result(`${header}${target}${target}`).ok, false);
	assert.equal(result(`${header}${old}${old}`).ok, false);
});

test("first-line grammar forbids mixing provenance and no-provenance blocks", () => {
	const header = "PLUGIN STATUS VERSION PATH\n";
	assert.equal(result(`${header}${real}`).ok, false);
	assert.equal(result(`${real}${header}`).ok, false);
	assert.equal(result(`${real}${header}other@community  installed, enabled  1  /tmp/other\n`).ok, false);
});

test("target marketplace can be first, middle, or last and may be empty", () => {
	const second = foreign.replaceAll("community", "community-two");
	for (const text of [`${real}\n${foreign}\n${second}`, `${foreign}\n${real}\n${second}`, `${foreign}\n${second}\n${real}`]) {
		assert.deepEqual(result(text), { ok: true, plugin: true, legacy: false });
	}
	const emptyTarget = real.replace(real.trim().split("\n").at(-1), "");
	assert.deepEqual(result(`${foreign}\n${emptyTarget}`), { ok: true, plugin: false, legacy: false });
	assert.deepEqual(result(foreign), { ok: true, plugin: false, legacy: false });
});

test("multiple marketplaces fail closed on target source mismatch", () => {
	assert.equal(parsePluginList(`${foreign}\n${real}`, "/tmp/wrong-market").ok, false);
});

test("multiple marketplaces fail closed on malformed foreign or target segments", () => {
	assert.equal(
		parsePluginList(`${foreign.replace("other-plugin@community", "broken row")}\n${real}`, source).ok,
		false,
	);
	assert.equal(
		parsePluginList(`${foreign}\n${real.replace("ccl-skills@ccl-skills-npm", "broken row")}`, source).ok,
		false,
	);
});

test("duplicate npm target marketplace fails closed", () => {
	assert.equal(parsePluginList(`${real}\n${real}`, source).ok, false);
});

test("duplicate foreign marketplace fails closed as ambiguous", () => {
	assert.equal(parsePluginList(`${foreign}\n${foreign}`, source).ok, false);
});

test("duplicate or relative target marketplace ROOT makes public state unknown", () => {
	assert.equal(
		stateFrom(`MARKETPLACE ROOT\nccl-skills-npm  ${source}\nccl-skills-npm  ${source}\n`).status,
		"unknown",
	);
	assert.equal(stateFrom("MARKETPLACE ROOT\nccl-skills-npm  relative/root\n").status, "unknown");
});

test("duplicate foreign marketplace names make public state unknown", () => {
	assert.equal(
		stateFrom("MARKETPLACE ROOT\ncommunity  /tmp/a\ncommunity  /tmp/b\n").status,
		"unknown",
	);
});

test("header-only segments are known absent and legacy unprovenanced rows stay compatible", () => {
	const header = "PLUGIN STATUS VERSION PATH\n";
	assert.deepEqual(parsePluginList(header, source), {
		ok: true,
		plugin: false,
		legacy: false,
	});
	assert.deepEqual(
		parsePluginList(
			`${header}ccl-skills@ccl-skills-npm  installed, enabled  local  /tmp/plugin\n`,
			source,
		),
		{ ok: true, plugin: true, legacy: false },
	);
});

test("unknown preamble, similar prefix, duplicate header, and malformed row fail closed", () => {
	assert.equal(parsePluginList(`surprise\n${real}`, source).ok, false);
	assert.deepEqual(
		parsePluginList(
			real.replace(
				"ccl-skills@ccl-skills-npm",
				"ccl-skills@ccl-skills-npm-copy",
			),
			source,
		),
		{ ok: true, plugin: false, legacy: false },
	);
	assert.equal(
		parsePluginList(`${real}PLUGIN STATUS VERSION PATH\n`, source).ok,
		false,
	);
	assert.equal(
		parsePluginList("PLUGIN STATUS VERSION PATH\nbroken row\n", null).ok,
		false,
	);
	assert.equal(parsePluginList(real, "/tmp/other-market").ok, false);
});
