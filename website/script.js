const themeButtons = document.querySelectorAll("[data-theme-option]");
const themeStorageKey = "the-climb-theme";

function readThemePreference() {
  try {
    return localStorage.getItem(themeStorageKey) || "system";
  } catch {
    return "system";
  }
}

function writeThemePreference(theme) {
  try {
    localStorage.setItem(themeStorageKey, theme);
  } catch {
    // Ignore storage failures; the current page still updates.
  }
}

function applyTheme(theme) {
  if (theme === "light" || theme === "dark") {
    document.documentElement.dataset.theme = theme;
  } else {
    delete document.documentElement.dataset.theme;
  }

  themeButtons.forEach((button) => {
    const isActive = button.dataset.themeOption === theme;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-pressed", String(isActive));
  });
}

const initialTheme = readThemePreference();
applyTheme(initialTheme);

themeButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const theme = button.dataset.themeOption || "system";
    writeThemePreference(theme);
    applyTheme(theme);
  });
});
