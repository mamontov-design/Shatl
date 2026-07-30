import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";

async function renderedHtml() {
  const output = fileURLToPath(new URL("../out/index.html", import.meta.url));
  return readFile(output, "utf8");
}

test("exports the Shatl landing as static HTML", async () => {
  const html = await renderedHtml();
  const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

  assert.match(html, /<html lang="ru">/i);
  assert.match(html, /Shatl — лёгкий торрент‑клиент для Mac/);
  assert.match(html, /Контроль до начала загрузки/);
  assert.match(html, /От экономии заряда до максимальной скорости/);
  assert.match(html, /Приватность, которую можно проверить/);
  assert.match(html, /Попробуйте Shatl на своём Mac/);
  assert.match(html, /macOS 27 или новее/);
  assert.match(html, /Только Apple Silicon/);
  assert.ok(
    html.includes(`src="${basePath}/hero-logomark-light.png"`),
    "hero artwork must include the configured GitHub Pages base path",
  );
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});
