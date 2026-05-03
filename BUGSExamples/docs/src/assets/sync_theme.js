document.addEventListener("DOMContentLoaded", function() {
    function updateDoodleBugsTheme() {
        const htmlTheme = document.documentElement.getAttribute("data-theme") || "";
        const storageTheme = window.localStorage.getItem("documenter-theme") || "";
        const theme = storageTheme || htmlTheme || "auto";
        
        let isDark = false;
        if (theme === "auto") {
            isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        } else {
            isDark = theme.includes("dark") || theme.includes("mocha") || theme.includes("macchiato") || theme.includes("frappe");
        }
        
        const targetMode = isDark ? "dark" : "light";
        
        document.querySelectorAll("doodle-bugs").forEach(function(widget) {
            widget.setAttribute("theme-mode", targetMode);
            if ('themeMode' in widget) {
                widget.themeMode = targetMode;
            }
        });
    }

    const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
            if (mutation.attributeName === "data-theme" || mutation.attributeName === "class") {
                updateDoodleBugsTheme();
            }
        });
    });
    
    observer.observe(document.documentElement, {
        attributes: true,
        attributeFilter: ["data-theme", "class"]
    });
    
    window.addEventListener('storage', function(e) {
        if (e.key === 'documenter-theme') {
            updateDoodleBugsTheme();
        }
    });
    
    if (window.matchMedia) {
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function(e) {
            const currentTheme = window.localStorage.getItem("documenter-theme") || "auto";
            if (currentTheme === "auto") {
                updateDoodleBugsTheme();
            }
        });
    }
    
    setTimeout(updateDoodleBugsTheme, 500);
    setTimeout(updateDoodleBugsTheme, 2000);
});
