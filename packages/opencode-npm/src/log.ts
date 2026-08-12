// Minimal shared output helpers for the CLI.
// Keep messages short, actionable, and free of emojis that don't render in all terminals.

export function ok(msg: string): void {
  console.log(`  [OK] ${msg}`)
}

export function info(msg: string): void {
  console.log(`  [i] ${msg}`)
}

export function warn(msg: string): void {
  console.log(`  [!] ${msg}`)
}

export function fail(msg: string): void {
  console.error(`  [X] ${msg}`)
}

export function section(title: string): void {
  console.log(`\n== ${title} ==`)
}
