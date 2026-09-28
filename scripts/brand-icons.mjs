// Renders the app icons of the TypeScript clients from the Memento mark
// (web/public/favicon.svg: gradient square with a glowing dot).
//   node scripts/brand-icons.mjs
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = dirname(dirname(fileURLToPath(import.meta.url)));

const defs = `
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#7C3AED"/><stop offset="0.55" stop-color="#EC4899"/><stop offset="1" stop-color="#06B6D4"/>
    </linearGradient>
    <radialGradient id="c" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.95"/><stop offset="0.6" stop-color="#ffffff" stop-opacity="0.4"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
  </defs>`;
const dot = (cx, cy, scale = 1) => `<circle cx="${cx}" cy="${cy}" r="${14 * scale}" fill="url(#c)"/><circle cx="${cx}" cy="${cy}" r="${5 * scale}" fill="#ffffff"/>`;

/** The mark on a rounded square inside a canvas with `pad` units of margin (64-unit grid). */
const rounded = (pad) => {
  const size = 64 - pad * 2;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">${defs}<rect x="${pad}" y="${pad}" width="${size}" height="${size}" rx="${size * 0.225}" fill="url(#g)"/>${dot(32, 32, size / 60)}</svg>`;
};
/** Full-bleed square (iOS masks the corners itself). */
const square = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">${defs}<rect width="64" height="64" fill="url(#g)"/>${dot(32, 32, 1.1)}</svg>`;
/** Android adaptive layers: gradient background, dot foreground inside the safe zone. */
const background = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">${defs}<rect width="64" height="64" fill="url(#g)"/></svg>`;
const foreground = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">${defs}${dot(32, 32, 0.8)}</svg>`;
const monochrome = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><circle cx="32" cy="32" r="9" fill="#ffffff"/></svg>`;

async function render(svg, size, out) {
  mkdirSync(dirname(out), { recursive: true });
  await sharp(Buffer.from(svg), { density: 1024 }).resize(size, size).png().toFile(out);
  console.log(out);
}

const desktop = join(root, "apps/desktop");
const mobile = join(root, "apps/mobile/assets");
// macOS wants a margin around the rounded square (Big Sur grid: 824 of 1024).
await render(rounded(6.25), 1024, join(desktop, "build/icon.png"));
await render(rounded(2), 32, join(desktop, "static/tray.png"));
await render(rounded(2), 64, join(desktop, "static/tray@2x.png"));
await render(square, 1024, join(mobile, "icon.png"));
await render(rounded(2), 1024, join(mobile, "splash-icon.png"));
await render(background, 1024, join(mobile, "android-icon-background.png"));
await render(foreground, 1024, join(mobile, "android-icon-foreground.png"));
await render(monochrome, 1024, join(mobile, "android-icon-monochrome.png"));
await render(rounded(2), 48, join(mobile, "favicon.png"));
