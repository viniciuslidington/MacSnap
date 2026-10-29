// Content and downloads work without JavaScript. Demos are progressive enhancements.
const copy = JSON.parse(document.querySelector("#site-copy").textContent);
const formatCopy = (message, values) =>
  message.replace(/\{(\w+)\}/g, (token, key) => values[key] ?? token);
// Each language is a real static page; keep the current section when switching.
for (const link of document.querySelectorAll("[data-language-link]")) {
  link.addEventListener("click", () => {
    link.hash = window.location.hash;
  });
}
const copyButton = document.querySelector("[data-copy-command]");
const command = document.querySelector("#install-command");
const copyStatus = document.querySelector(".copy-status");

if (
  copyButton &&
  command &&
  copyStatus &&
  navigator.clipboard &&
  window.isSecureContext
) {
  copyButton.hidden = false;
  copyButton.addEventListener("click", async () => {
    copyButton.disabled = true;
    try {
      await navigator.clipboard.writeText(
        command.textContent.replace(/\s+/g, " ").trim(),
      );
      copyStatus.textContent = copy.copySuccess;
      copyButton.textContent = copy.copied;
    } catch {
      copyStatus.textContent = copy.copyFailure;
    } finally {
      copyButton.disabled = false;
    }
  });
}

// Keep motion local to the artwork, and stop listening when visitors opt out.
const motionPreference = window.matchMedia(
  "(hover: hover) and (pointer: fine) and (prefers-reduced-motion: no-preference)",
);
const motionSurfaces = document.querySelectorAll(".hero-product");
let stopMotion = () => {};

function configureMotion() {
  stopMotion();
  if (!motionPreference.matches) return;

  const controller = new AbortController();
  const cleanups = [];
  for (const surface of motionSurfaces) {
    let frame = 0;
    let pointerX = 0;
    let pointerY = 0;
    const reset = () => {
      cancelAnimationFrame(frame);
      frame = 0;
      surface.classList.remove("is-tracking");
      surface.style.removeProperty("--pointer-x");
      surface.style.removeProperty("--pointer-y");
    };
    surface.addEventListener(
      "pointermove",
      (event) => {
        if (event.pointerType !== "mouse" || event.buttons) return;
        const bounds = surface.getBoundingClientRect();
        pointerX = (event.clientX - bounds.left) / bounds.width - 0.5;
        pointerY = (event.clientY - bounds.top) / bounds.height - 0.5;
        if (frame) return;
        frame = requestAnimationFrame(() => {
          surface.classList.add("is-tracking");
          surface.style.setProperty("--pointer-x", `${pointerX * 20}px`);
          surface.style.setProperty("--pointer-y", `${pointerY * 16}px`);
          frame = 0;
        });
      },
      { signal: controller.signal },
    );
    surface.addEventListener("pointerleave", reset, {
      signal: controller.signal,
    });
    surface.addEventListener("pointercancel", reset, {
      signal: controller.signal,
    });
    window.addEventListener("scroll", reset, {
      signal: controller.signal,
      passive: true,
    });
    window.addEventListener("blur", reset, { signal: controller.signal });
    document.addEventListener(
      "visibilitychange",
      () => {
        if (document.hidden) reset();
      },
      { signal: controller.signal },
    );
    cleanups.push(reset);
  }
  stopMotion = () => {
    controller.abort();
    cleanups.forEach((reset) => reset());
  };
}
motionPreference.addEventListener("change", configureMotion);
configureMotion();

// Brief previews run once in view. User input always takes over immediately.
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const activePreviews = new Set();
function onceInView(element, play) {
  let played = false;
  let stop = () => {};
  let disconnect = () => {};
  const finish = () => {
    disconnect();
    activePreviews.delete(cancel);
  };
  const cancel = () => {
    stop();
    activePreviews.delete(cancel);
    if (played) disconnect();
  };
  const checkVisibility = (ratio, visible) => {
    if (!visible) cancel();
    if (played || ratio < 0.45 || reducedMotion.matches || document.hidden)
      return;
    played = true;
    stop = play(finish) || (() => {});
    activePreviews.add(cancel);
  };
  if (typeof IntersectionObserver === "function") {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries)
          checkVisibility(entry.intersectionRatio, entry.isIntersecting);
      },
      { threshold: [0, 0.45] },
    );
    disconnect = () => observer.disconnect();
    observer.observe(element);
  } else {
    // Embedded browsers may omit IntersectionObserver. Read once per scroll frame.
    let frame = 0;
    const check = () => {
      frame = 0;
      const rect = element.getBoundingClientRect();
      const height = Math.max(
        0,
        Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0),
      );
      checkVisibility(rect.height ? height / rect.height : 0, height > 0);
    };
    const queue = () => {
      if (!frame) frame = requestAnimationFrame(check);
    };
    window.addEventListener("scroll", queue, { passive: true });
    window.addEventListener("resize", queue);
    disconnect = () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", queue);
      window.removeEventListener("resize", queue);
    };
    queue();
  }
  return () => {
    played = true;
    cancel();
  };
}
const stopActivePreviews = () => {
  for (const stop of activePreviews) stop();
};
reducedMotion.addEventListener("change", () => {
  if (reducedMotion.matches) stopActivePreviews();
});
document.addEventListener("visibilitychange", () => {
  if (document.hidden) stopActivePreviews();
});
window.addEventListener("blur", stopActivePreviews);

const layoutDemo = document.querySelector("[data-layout-demo]");
if (layoutDemo) {
  const trigger = layoutDemo.querySelector(".layout-trigger");
  const panel = layoutDemo.querySelector(".layout-panel");
  const slots = [...layoutDemo.querySelectorAll(".layout-template button")];
  let pointerInside = false;
  let userControlled = false;
  let isOpen = null;
  let cancelIntro = () => {};
  const setOpen = (open) => {
    if (isOpen === open) return;
    isOpen = open;
    if (!open && panel.contains(document.activeElement))
      trigger.focus({ preventScroll: true });
    layoutDemo.classList.toggle("is-open", open);
    trigger.setAttribute("aria-expanded", String(open));
    trigger.setAttribute(
      "aria-label",
      open ? copy.hideLayouts : copy.showLayouts,
    );
    panel.inert = !open;
    panel.setAttribute("aria-hidden", String(!open));
  };
  const takeOver = () => {
    if (userControlled) return;
    userControlled = true;
    cancelIntro();
  };
  layoutDemo.classList.add("is-enhanced");
  trigger.hidden = false;
  setOpen(false);
  cancelIntro = onceInView(layoutDemo, (finish) => {
    const timers = [];
    const highlight = (index) => {
      slots.forEach((slot, i) =>
        slot.classList.toggle("is-demo-active", i === index),
      );
    };
    timers.push(setTimeout(() => setOpen(true), 350));
    [0, 3, 10].forEach((index, step) => {
      timers.push(setTimeout(() => highlight(index), 950 + step * 600));
    });
    timers.push(
      setTimeout(() => {
        highlight(-1);
        setOpen(false);
        finish();
      }, 3200),
    );
    return () => {
      timers.forEach(clearTimeout);
      highlight(-1);
      if (!userControlled) setOpen(false);
    };
  });
  layoutDemo.addEventListener("pointerenter", (event) => {
    if (event.pointerType !== "mouse") return;
    pointerInside = true;
    if (userControlled) setOpen(true);
  });
  layoutDemo.addEventListener("pointermove", (event) => {
    if (event.pointerType !== "mouse" || event.buttons) return;
    takeOver();
    setOpen(true);
  });
  layoutDemo.addEventListener("pointerleave", (event) => {
    if (event.pointerType !== "mouse") return;
    pointerInside = false;
    const keyboardFocus =
      layoutDemo.contains(document.activeElement) &&
      document.activeElement.matches(":focus-visible");
    if (!keyboardFocus) setOpen(false);
  });
  layoutDemo.addEventListener("focusin", (event) => {
    takeOver();
    if (event.target !== trigger) setOpen(true);
  });
  layoutDemo.addEventListener("focusout", (event) => {
    if (!layoutDemo.contains(event.relatedTarget) && !pointerInside)
      setOpen(false);
  });
  trigger.addEventListener("click", () => {
    const open = trigger.getAttribute("aria-expanded") === "true";
    takeOver();
    setOpen(!open);
  });
  layoutDemo.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    event.preventDefault();
    takeOver();
    setOpen(false);
    trigger.focus({ preventScroll: true });
  });
  document.addEventListener("pointerdown", (event) => {
    if (!layoutDemo.contains(event.target)) setOpen(false);
  });
}

const layoutButtons = document.querySelectorAll(".layout-playground button");
const layoutCaption = document.querySelector("[data-layout-caption]");
for (const button of layoutButtons) {
  button.addEventListener("click", () => {
    for (const other of layoutButtons)
      other.setAttribute("aria-pressed", "false");
    button.setAttribute("aria-pressed", "true");
    layoutCaption.textContent = formatCopy(copy.layoutSelected, {
      label: button.getAttribute("aria-label"),
    });
  });
}

// Drag the actual seam; the same handle exposes slider keys and values to AT.
const pairDemo = document.querySelector("[data-pair-demo]");
if (pairDemo) {
  const handle = pairDemo.querySelector("[data-pair-handle]");
  const diagram = pairDemo.querySelector(".pair-diagram");
  const ratio = pairDemo.querySelector("[data-pair-ratio]");
  const min = Number(handle.getAttribute("aria-valuemin"));
  const max = Number(handle.getAttribute("aria-valuemax"));
  let value = Number(handle.getAttribute("aria-valuenow"));
  let drag = null;
  let cancelPairPreview = () => {};
  handle.addEventListener("focus", () => cancelPairPreview());
  const updatePair = (nextValue) => {
    const first = Math.max(min, Math.min(max, Math.round(nextValue)));
    if (first === value && diagram.style.gridTemplateColumns) return;
    const second = 100 - first;
    value = first;
    diagram.style.gridTemplateColumns = `minmax(0, ${first}fr) 10px minmax(0, ${second}fr)`;
    handle.setAttribute("aria-valuenow", String(first));
    handle.setAttribute(
      "aria-valuetext",
      formatCopy(copy.splitValue, { first, second }),
    );
    ratio.textContent = `${first}% ↔ ${second}%`;
  };
  const stopDrag = () => {
    if (!drag) return;
    const pointerId = drag.pointerId;
    drag = null;
    pairDemo.classList.remove("is-dragging");
    if (handle.hasPointerCapture(pointerId))
      handle.releasePointerCapture(pointerId);
  };
  const moveDivider = (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    updatePair(drag.value + ((event.clientX - drag.x) / drag.width) * 100);
  };
  handle.addEventListener("pointerdown", (event) => {
    if (!event.isPrimary || event.button !== 0 || drag) return;
    cancelPairPreview();
    const style = getComputedStyle(diagram);
    const width =
      diagram.clientWidth -
      parseFloat(style.paddingLeft) -
      parseFloat(style.paddingRight) -
      diagram.querySelector(".pair-divider").offsetWidth;
    if (width <= 0) return;
    event.preventDefault();
    handle.focus({ preventScroll: true });
    drag = { pointerId: event.pointerId, x: event.clientX, value, width };
    handle.setPointerCapture(event.pointerId);
    pairDemo.classList.add("is-dragging");
  });
  handle.addEventListener("pointermove", moveDivider);
  handle.addEventListener("pointerup", (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    moveDivider(event);
    stopDrag();
  });
  handle.addEventListener("pointercancel", stopDrag);
  handle.addEventListener("lostpointercapture", stopDrag);
  window.addEventListener("blur", stopDrag);
  window.addEventListener("resize", stopDrag);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stopDrag();
  });
  handle.addEventListener("keydown", (event) => {
    if (event.altKey || event.ctrlKey || event.metaKey) return;
    const values = {
      ArrowLeft: value - 1,
      ArrowDown: value - 1,
      ArrowRight: value + 1,
      ArrowUp: value + 1,
      PageDown: value - 10,
      PageUp: value + 10,
      Home: min,
      End: max,
    };
    if (!Object.hasOwn(values, event.key)) return;
    event.preventDefault();
    cancelPairPreview();
    stopDrag();
    updatePair(values[event.key]);
  });
  updatePair(value);
  pairDemo.querySelector("[data-static-divider]").hidden = true;
  pairDemo.querySelector(".pair-hint").hidden = false;
  handle.hidden = false;
  cancelPairPreview = onceInView(diagram, (finish) => {
    const initial = value;
    const keyframes = [initial, 49, 61, initial];
    let start;
    let frame;
    pairDemo.classList.add("is-previewing");
    const tick = (now) => {
      start ??= now;
      const progress = Math.min(1, (now - start) / 2400);
      const segment = Math.min(2, Math.floor(progress * 3));
      const phase = progress * 3 - segment;
      const eased = phase * phase * (3 - 2 * phase);
      updatePair(
        keyframes[segment] +
          (keyframes[segment + 1] - keyframes[segment]) * eased,
      );
      if (progress < 1) frame = requestAnimationFrame(tick);
      else {
        pairDemo.classList.remove("is-previewing");
        finish();
      }
    };
    frame = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(frame);
      pairDemo.classList.remove("is-previewing");
    };
  });
}

const monitors = document.querySelector(".screen-drawing");
if (monitors) {
  onceInView(monitors, (finish) => {
    monitors.classList.add("is-demonstrating");
    const timer = setTimeout(() => {
      monitors.classList.remove("is-demonstrating");
      finish();
    }, 2000);
    return () => {
      clearTimeout(timer);
      monitors.classList.remove("is-demonstrating");
    };
  });
}
