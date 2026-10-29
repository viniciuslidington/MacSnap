// The page and download links work without JavaScript. Only clipboard copying is enhanced.
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
