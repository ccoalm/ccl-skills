// CCL Skills OpenCode TUI plugin entry point.
// Startup-only local loaded/update reminder: reads the install manifest, never
// polls, never queries the network, and never executes update commands.

import { updateReminder } from "./reminder.js"

interface TuiToastOptions {
  title?: string
  message: string
}

interface TuiApi {
  ui?: {
    toast?: (options: TuiToastOptions) => unknown
  }
}

export const tui = async (api: TuiApi = {}, _options?: unknown, _meta?: unknown) => {
  try {
    const reminder = updateReminder()
    api.ui?.toast?.(
      reminder
        ? {
            title: "CCL Skills loaded",
            message: `${reminder.message}`,
          }
        : {
            title: "CCL Skills loaded",
            message: "ccl-skills is loaded. Use `/update` or `ccl-skills-opencode update` to preview updates when needed.",
          },
    )
  } catch {
    // TUI reminder failures must never break OpenCode startup.
  }
  return {}
}

export default {
  id: "ccl-skills",
  tui,
}
