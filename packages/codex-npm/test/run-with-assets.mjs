import {run} from "../dist/index.js"
const [assets,command,...flags]=process.argv.slice(2),yes=flags.includes("--yes")||flags.includes("-y"),allowDowngrade=flags.includes("--allow-downgrade"),json=flags.includes("--json")
if(!["install","update","doctor","uninstall"].includes(command)){console.error("Invalid command or option. Run --help.");process.exit(2)}
if(allowDowngrade&&(command!=="update"||!yes)){console.error("--allow-downgrade is valid only with update --yes.");process.exit(2)}
const result=run(command,{yes,allowDowngrade},{assets});console.log(json?JSON.stringify(result):`${result.status}: ${result.message}`);process.exitCode=result.code
