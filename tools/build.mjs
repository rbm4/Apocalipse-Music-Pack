import { cpSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const target = resolve(root, 'build', 'Contents', 'mods', 'Apocalipse-Music-Pack');
const allowed = resolve(root, 'build');
// Verify the absolute destination before any recursive removal on Windows.
if (target !== join(allowed, 'Contents', 'mods', 'Apocalipse-Music-Pack')) throw new Error('Invalid build target');
if (existsSync(target)) rmSync(target, { recursive: true });
if (process.argv.includes('--clean')) {
    console.log(`Cleaned ${target}`);
} else {
    mkdirSync(dirname(target), { recursive: true });
    cpSync(join(root, 'Apocalipse-Music-Pack'), target, {
        recursive: true,
        filter: path => !path.endsWith('.gitkeep'),
    });
    console.log(`Built B42 mod: ${target}`);
}
