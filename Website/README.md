# Shatl landing

The landing page is a statically exported Next.js site published at:

`https://mamontov-design.github.io/Shatl/`

## Local development

```sh
npm ci
npm run dev
```

Local development uses `/` as the site root.

## Production build

```sh
NEXT_PUBLIC_BASE_PATH=/Shatl npm run build
```

The static export is written to `out/`. The GitHub Pages workflow builds with
the same base path so that scripts, fonts, images, icons, and metadata resolve
under the repository project URL.
