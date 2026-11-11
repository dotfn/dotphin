import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Static site today: `next build` writes plain HTML/CSS/JS to `out/`.
  output: "export",
  images: { unoptimized: true },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
