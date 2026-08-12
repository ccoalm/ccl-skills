import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
import { LEGACY_REF, MARKET, REF } from "./paths.js";
import { canonicalAlias } from "./fs-safe.js";
import { compare, parseVersion } from "./version.js";

export interface HostState {
	status: "known" | "unknown";
	marketplace: boolean;
	marketplaceSource: string | null;
	plugin: boolean;
	legacy: boolean;
	marketplaceOutput: string;
	pluginOutput: string;
}

function call(args: string[], codexHome?: string) {
	const env = {
		...process.env,
		...(codexHome ? { CODEX_HOME: codexHome } : {}),
	};
	return spawnSync("codex", args, {
		encoding: "utf8",
		env,
		detached: process.platform !== "win32",
	} as Parameters<typeof spawnSync>[2]);
}

export function checkHost(codexHome?: string) {
	const p = call(["--version"], codexHome);
	if (p.error || p.status !== 0)
		return {
			ok: false as const,
			kind: "missing",
			message: "Codex CLI is missing",
		};
	const version = parseVersion(`${p.stdout}\n${p.stderr}`);
	if (!version || compare(version, "0.133.0") < 0)
		return {
			ok: false as const,
			kind: "old",
			message: "Codex >=0.133.0 is required",
		};
	return { ok: true as const, version };
}

export function parsePluginList(
	text: string,
	marketplaceSource: string | null,
): { ok: boolean; plugin: boolean; legacy: boolean } {
	const lines = text.split(/\r?\n/).filter((line) => line.trim());
	if (
		lines.length === 0 ||
		(lines.length === 1 && lines[0] === "No marketplace plugins found.")
	)
		return { ok: true, plugin: false, legacy: false };
	const header = /^PLUGIN\s+STATUS\s+VERSION\s+PATH\s*$/;
	const provenance = /^Marketplace `([^`]+)`$/;
	const sensitiveRefs = new Set<string>();
	let plugin = false;
	let legacy = false;
	const parseRow = (line: string, marketplace: string | null) => {
		const row = line.match(
			/^(\S+)\s{2,}(\S(?:.*\S)?)\s{2,}(\S+)\s{2,}(\/\S.*)$/,
		);
		if (!row) return false;
		if (row[1] === REF || row[1] === LEGACY_REF) {
			if (
				!["not installed", "installed, enabled", "installed, disabled"].includes(
					row[2],
				)
			)
				return false;
			if (sensitiveRefs.has(row[1])) return false;
			sensitiveRefs.add(row[1]);
			if (
				marketplace !== null &&
				((row[1] === REF && marketplace !== MARKET) ||
					(row[1] === LEGACY_REF && marketplace !== "ccl-skills"))
			)
				return false;
		}
		if (row[1] === REF && row[2] === "installed, enabled") plugin = true;
		if (row[1] === LEGACY_REF && row[2].startsWith("installed,")) legacy = true;
		return true;
	};

	if (header.test(lines[0])) {
		for (const line of lines.slice(1)) if (!parseRow(line, null)) return { ok: false, plugin: false, legacy: false };
		return { ok: true, plugin, legacy };
	}
	if (!provenance.test(lines[0]))
		return { ok: false, plugin: false, legacy: false };

	const seenMarketplaces = new Set<string>();
	let index = 0;
	while (index < lines.length) {
		const match = lines[index].match(provenance);
		if (!match || index + 2 >= lines.length)
			return { ok: false, plugin: false, legacy: false };
		const marketplace = match[1];
		if (seenMarketplaces.has(marketplace))
			return { ok: false, plugin: false, legacy: false };
		seenMarketplaces.add(marketplace);
		const manifest = lines[index + 1];
		if (!isAbsolute(manifest))
			return { ok: false, plugin: false, legacy: false };
		if (
			marketplace === MARKET &&
			(!marketplaceSource ||
				canonicalAlias(resolve(manifest)) !==
					canonicalAlias(
						resolve(join(marketplaceSource, ".agents/plugins/marketplace.json")),
					))
		)
			return { ok: false, plugin: false, legacy: false };
		index += 2;
		if (!header.test(lines[index]))
			return { ok: false, plugin: false, legacy: false };
		index++;
		while (index < lines.length && !provenance.test(lines[index]))
			if (!parseRow(lines[index++], marketplace))
				return { ok: false, plugin: false, legacy: false };
	}
	return { ok: true, plugin, legacy };
}

function parseMarketplace(text: string): {
	ok: boolean;
	source: string | null;
} {
	const lines = text.split(/\r?\n/).filter((line) => line.trim());
	if (lines.length === 0) return { ok: true, source: null };
	if (lines.length === 1 && lines[0] === "No plugin marketplaces in scope.")
		return { ok: true, source: null };
	if (!/^MARKETPLACE\s+ROOT\s*$/.test(lines[0]))
		return { ok: false, source: null };
	let source: string | null = null;
	const seen = new Set<string>();
	for (const line of lines.slice(1)) {
		const match = line.match(/^(\S+)\s{2,}(\S.*)$/);
		if (!match) return { ok: false, source: null };
		if (seen.has(match[1])) return { ok: false, source: null };
		seen.add(match[1]);
		if (match[1] === MARKET) {
			if (!isAbsolute(match[2])) return { ok: false, source: null };
			source = resolve(match[2]);
		}
	}
	return { ok: true, source };
}

export function publicState(codexHome: string): HostState {
	const empty = {
		marketplace: false,
		marketplaceSource: null,
		plugin: false,
		legacy: false,
		marketplaceOutput: "",
		pluginOutput: "",
	};
	if (!existsSync(codexHome)) return { status: "known", ...empty };
	const marketplace = call(["plugin", "marketplace", "list"], codexHome);
	const plugins = call(["plugin", "list"], codexHome);
	const marketplaceOutput = `${marketplace.stdout}${marketplace.stderr}`;
	const pluginOutput = `${plugins.stdout}${plugins.stderr}`;
	const parsed = parseMarketplace(`${marketplace.stdout}`);
	const parsedPlugins = parsePluginList(`${plugins.stdout}`, parsed.source);
	if (
		marketplace.status !== 0 ||
		plugins.status !== 0 ||
		!parsed.ok ||
		!parsedPlugins.ok
	)
		return { status: "unknown", ...empty, marketplaceOutput, pluginOutput };
	return {
		status: "known",
		marketplace: parsed.source !== null,
		marketplaceSource: parsed.source,
		plugin: parsedPlugins.plugin,
		legacy: parsedPlugins.legacy,
		marketplaceOutput,
		pluginOutput,
	};
}

export const marketplaceAdd = (path: string, codexHome?: string) =>
	call(["plugin", "marketplace", "add", path], codexHome);
export const marketplaceRemove = (codexHome?: string) =>
	call(["plugin", "marketplace", "remove", MARKET], codexHome);
export const pluginAdd = (codexHome?: string) =>
	call(["plugin", "add", REF], codexHome);
export const pluginRemove = (codexHome?: string) =>
	call(["plugin", "remove", REF], codexHome);
