"use client";

// The hero's wallpaper: slow liquid folds in Dotphin water tones with one warm
// glossy shape, rendered by a single fragment shader on a three.js plane.
// Pauses offscreen, renders one still frame under reduced motion, and falls
// back to the CSS gradient on the container when WebGL isn't available.

import { useEffect, useRef } from "react";

const vertex = /* glsl */ `
  void main() { gl_Position = vec4(position.xy, 0.0, 1.0); }
`;

const fragment = /* glsl */ `
  precision highp float;
  uniform float uTime;
  uniform vec2 uRes;

  float height(vec2 p, float t) {
    vec2 q = p;
    q += 0.30 * vec2(sin(1.7 * q.y + t * 2.1), sin(1.3 * q.x - t * 1.7));
    q += 0.18 * vec2(sin(2.9 * q.y - t * 1.3 + 1.7), sin(2.3 * q.x + t * 1.1 + 0.4));
    q += 0.08 * vec2(sin(4.1 * q.y + t * 0.9), sin(3.7 * q.x - t * 0.8));
    return sin(2.0 * q.x + 1.25 * q.y + t) * 0.5 + 0.5;
  }

  void main() {
    vec2 uv = gl_FragCoord.xy / uRes;
    float asp = uRes.x / uRes.y;
    vec2 p = (uv - 0.5) * vec2(asp, 1.0) * 1.7;
    float t = uTime * 0.07;

    float e = 0.004;
    float h = height(p, t);
    float hx = height(p + vec2(e, 0.0), t) - h;
    float hy = height(p + vec2(0.0, e), t) - h;
    vec3 n = normalize(vec3(-hx / e * 0.16, -hy / e * 0.16, 1.0));

    vec3 L = normalize(vec3(-0.45, 0.65, 0.75));
    vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
    float diff = clamp(dot(n, L), 0.0, 1.0);
    float spec = pow(max(dot(n, H), 0.0), 70.0);
    float rim = pow(1.0 - n.z, 2.0);

    vec3 deep  = vec3(0.020, 0.330, 0.470);
    vec3 mid   = vec3(0.110, 0.600, 0.770);
    vec3 light = vec3(0.640, 0.880, 0.930);
    vec3 col = mix(deep, mid, smoothstep(0.0, 0.62, h));
    col = mix(col, light, smoothstep(0.58, 1.0, h) * 0.75);
    col *= 0.72 + 0.38 * diff;
    col += spec * 0.5 + rim * 0.55 * vec3(0.82, 0.96, 1.0);

    // The warm shape: a glossy disc with soft concentric ridges, lower right.
    vec2 c = vec2(0.62 * asp * 0.85, -0.78);
    vec2 d2 = (p - c) * vec2(0.95, 1.35);
    float d = length(d2);
    float body = smoothstep(0.78, 0.70, d);
    float ridges = 0.5 + 0.5 * sin(d * 34.0 - t * 6.0);
    vec3 sun = mix(vec3(1.0, 0.43, 0.06), vec3(1.0, 0.72, 0.30), ridges * smoothstep(0.75, 0.2, d));
    sun += pow(smoothstep(0.72, 0.0, length(d2 - vec2(-0.18, 0.22))), 3.0) * 0.35;
    col = mix(col, sun, body * 0.96);
    // a thin bright lip where the water passes over the warm shape
    col += smoothstep(0.02, 0.0, abs(d - 0.74)) * 0.25;

    // gentle falloff to the page gray at the top edge so it sits on the page
    col = mix(col, vec3(0.80, 0.86, 0.89), smoothstep(0.75, 1.0, uv.y) * 0.25);

    gl_FragColor = vec4(col, 1.0);
  }
`;

export function WaterCanvas({ className }: { className?: string }) {
  const host = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = host.current;
    if (!el) return;
    let disposed = false;
    let cleanup = () => {};

    (async () => {
      const THREE = await import("three");
      if (disposed) return;

      let renderer: import("three").WebGLRenderer;
      try {
        renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, powerPreference: "low-power" });
      } catch {
        return; // CSS gradient on the container stays visible
      }
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
      renderer.domElement.style.cssText = "position:absolute;inset:0;width:100%;height:100%;display:block";
      el.appendChild(renderer.domElement);

      const scene = new THREE.Scene();
      const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
      const uniforms = { uTime: { value: 18 }, uRes: { value: new THREE.Vector2(1, 1) } };
      const material = new THREE.ShaderMaterial({ vertexShader: vertex, fragmentShader: fragment, uniforms });
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), material);
      scene.add(mesh);

      const resize = () => {
        const { width, height } = el.getBoundingClientRect();
        renderer.setSize(width, height, false);
        renderer.getDrawingBufferSize(uniforms.uRes.value);
        renderer.render(scene, camera);
      };
      const ro = new ResizeObserver(resize);
      ro.observe(el);
      resize();

      const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      let raf = 0;
      let visible = true;
      const start = performance.now();
      const loop = () => {
        uniforms.uTime.value = 18 + (performance.now() - start) / 1000;
        renderer.render(scene, camera);
        raf = requestAnimationFrame(loop);
      };
      const io = new IntersectionObserver(([entry]) => {
        visible = entry.isIntersecting;
        cancelAnimationFrame(raf);
        if (visible && !reduced) raf = requestAnimationFrame(loop);
      });
      io.observe(el);

      cleanup = () => {
        cancelAnimationFrame(raf);
        io.disconnect();
        ro.disconnect();
        material.dispose();
        mesh.geometry.dispose();
        renderer.dispose();
        renderer.domElement.remove();
      };
    })();

    return () => {
      disposed = true;
      cleanup();
    };
  }, []);

  return (
    <div
      ref={host}
      aria-hidden="true"
      className={className}
      style={{
        background:
          "radial-gradient(60% 55% at 78% 92%, #ff8a1f 0 38%, transparent 39%), radial-gradient(80% 90% at 20% 20%, #9ee0ee, transparent 60%), linear-gradient(135deg, #2aa8cc, #0b6f93)",
      }}
    />
  );
}
