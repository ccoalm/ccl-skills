export function compare(a:string,b:string):number{const x=a.split(".").map(Number),y=b.split(".").map(Number);for(let i=0;i<3;i++){if((x[i]||0)!==(y[i]||0))return(x[i]||0)-(y[i]||0)}return 0}
export function parseVersion(text:string):string|null{return text.match(/\b(\d+\.\d+\.\d+)\b/)?.[1]||null}
