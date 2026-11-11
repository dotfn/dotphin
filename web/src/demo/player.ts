"use client";

// Plays a script of demo actions on a timeline. This is the only thing the
// interactive version replaces: user input will dispatch instead.

import { useReducedMotion } from "motion/react";
import { useEffect, useReducer, useRef, useState, type RefObject } from "react";
import { reduce, type Action, type DemoState } from "./state";

export type Step = { wait: number; action: Action };

/** Expands typing into one step per character, like a person at a keyboard. */
export function typeSteps(text: string, perChar = 55, startWait = 300): Step[] {
  return [...text].map((_, i) => ({
    wait: i === 0 ? startWait : perChar,
    action: { type: "termInput", text: text.slice(0, i + 1) },
  }));
}

function finalState(initial: DemoState, steps: Step[]): DemoState {
  return steps.reduce((s, step) => reduce(s, step.action), initial);
}

function useInView(ref: RefObject<Element | null>) {
  const [inView, setInView] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => setInView(e.isIntersecting), { threshold: 0.25 });
    io.observe(el);
    return () => io.disconnect();
  }, [ref]);
  return inView;
}

/**
 * Runs `steps` while `ref` is on screen, then holds for `hold` ms and loops.
 * Under reduced motion it shows the script's end state, still.
 */
export function useScriptedDemo(
  ref: RefObject<Element | null>,
  initial: DemoState,
  steps: Step[],
  { hold = 2600, loop = true }: { hold?: number; loop?: boolean } = {},
) {
  const [state, dispatch] = useReducer(reduce, initial);
  const reduced = useReducedMotion() ?? false;
  const inView = useInView(ref);
  const cursor = useRef(0);

  useEffect(() => {
    if (reduced) {
      dispatch({ type: "reset", state: finalState(initial, steps) });
      return;
    }
    if (!inView) return;

    let timer: ReturnType<typeof setTimeout>;
    const tick = () => {
      if (cursor.current >= steps.length) {
        if (!loop) return;
        timer = setTimeout(() => {
          cursor.current = 0;
          dispatch({ type: "reset", state: initial });
          tick();
        }, hold);
        return;
      }
      const step = steps[cursor.current];
      timer = setTimeout(() => {
        dispatch(step.action);
        cursor.current += 1;
        tick();
      }, step.wait);
    };
    tick();
    return () => clearTimeout(timer);
  }, [inView, reduced, initial, steps, hold, loop]);

  return { state, dispatch };
}
