// Read only the trusted, static translation declarations; no runtime DOM code.
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
import { spawnSync } from 'node:child_process';
const source=await readFile(new URL('../priv/static/i18n.js',import.meta.url),'utf8');
const declarations=source.slice(source.indexOf('  const ro ='),source.indexOf('  const originals ='));
const catalog=runInNewContext('(()=>{'+declarations+';return ro;})()',{});
const result=spawnSync('python3',[new URL('./build_locales.py',import.meta.url).pathname,...process.argv.slice(2)],{input:JSON.stringify(catalog),encoding:'utf8',cwd:new URL('..',import.meta.url)});
if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);process.exitCode=result.status ?? 1;
