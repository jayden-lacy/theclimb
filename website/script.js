const themeButtons = document.querySelectorAll("[data-theme-option]");
const themeStorageKey = "the-climb-theme";
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

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
    // Storage can fail in private browser modes; the live page still updates.
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

applyTheme(readThemePreference());

themeButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const theme = button.dataset.themeOption || "system";
    writeThemePreference(theme);
    applyTheme(theme);
  });
});

const currentPath = window.location.pathname
  .replace(/\/index\.html$/, "/")
  .replace(/\.html$/, "");

document.querySelectorAll(".nav-links a").forEach((link) => {
  const linkPath = new URL(link.href).pathname;
  if (linkPath === currentPath || (currentPath === "/" && linkPath === "/")) {
    link.classList.add("is-active");
  }
});

const revealItems = document.querySelectorAll(".reveal");

if (reduceMotion || !("IntersectionObserver" in window)) {
  revealItems.forEach((item) => item.classList.add("is-visible"));
} else {
  const revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        revealObserver.unobserve(entry.target);
      });
    },
    {
      threshold: 0.16,
      rootMargin: "0px 0px -8% 0px",
    }
  );

  revealItems.forEach((item) => revealObserver.observe(item));
}
