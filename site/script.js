// Content and downloads work without JavaScript. Demos are progressive enhancements.
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
      copyStatus.textContent =
        "Comando copiado. Você pode conferir o script antes de executá-lo.";
      copyButton.textContent = "Copiado";
    } catch {
      copyStatus.textContent =
        "Não foi possível copiar. Selecione o comando e copie manualmente.";
    } finally {
      copyButton.disabled = false;
    }
  });
}

// Keep motion local to the artwork, and stop listening when visitors opt out.
const motionPreference = window.matchMedia(
  "(hover: hover) and (pointer: fine) and (prefers-reduced-motion: no-preference)",
);
const motionSurfaces = document.querySelectorAll(
  ".hero-product, .layouts-capture",
);
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

// Native range input provides the same demonstration with mouse, touch or keyboard.
const pairDemo = document.querySelector("[data-pair-demo]");
if (pairDemo) {
  const range = pairDemo.querySelector("input[type=range]");
  const diagram = pairDemo.querySelector(".pair-diagram");
  const ratio = pairDemo.querySelector("[data-pair-ratio]");
  const controls = pairDemo.querySelector(".pair-controls");
  const updatePair = () => {
    const first = Number(range.value);
    const second = 100 - first;
    diagram.style.gridTemplateColumns = `minmax(0, ${first}fr) 10px minmax(0, ${second}fr)`;
    diagram.setAttribute(
      "aria-label",
      `Demonstração de duas janelas: ${first}% para o trabalho e ${second}% para a referência`,
    );
    range.setAttribute(
      "aria-valuetext",
      `${first}% para o trabalho, ${second}% para a referência`,
    );
    ratio.textContent = `${first}% ↔ ${second}%`;
  };
  range.addEventListener("input", updatePair);
  updatePair();
  controls.hidden = false;
}
