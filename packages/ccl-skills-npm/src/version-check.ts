#!/usr/bin/env node
// Detached entrypoint for the background version check. It is spawned with
// stdio ignored and unref'd, so it cannot slow, block, or outlive-block the
// command that scheduled it, and it exits 0 whatever the registry does.
import { paths } from "./paths.js";
import { cachePath, refresh } from "./update-notice.js";

refresh({ file: cachePath(paths().root) }).then(
	() => process.exit(0),
	() => process.exit(0),
);
