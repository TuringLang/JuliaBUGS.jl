document.addEventListener("DOMContentLoaded", function() {
    function updateDoodleBugsTheme() {
        // Documenter might use data-theme on html, or local storage.
        const htmlTheme = document.documentElement.getAttribute("data-theme") || "";
        const storageTheme = window.localStorage.getItem("documenter-theme") || "";
        const theme = storageTheme || htmlTheme || "light";
        
        // Explicitly set data-theme so our CSS rules can target it
        document.documentElement.setAttribute("data-theme", theme);
        
        console.log("[DoodleBugs Theme Sync] Detected Documenter theme:", theme);
        
        const isDark = theme.includes("dark") || theme.includes("macchiato") || theme.includes("mocha") || theme.includes("frappe");
        const targetMode = isDark ? "dark" : "light";
        
        const widgets = document.querySelectorAll("doodle-bugs");
        console.log("[DoodleBugs Theme Sync] Found widgets:", widgets.length);
        
        widgets.forEach(function(widget) {
            console.log("[DoodleBugs Theme Sync] Setting widget to:", targetMode);
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
    
    // Also listen to storage events
    window.addEventListener('storage', function(e) {
        if (e.key === 'documenter-theme') {
            updateDoodleBugsTheme();
        }
    });
    
    // Initial sync
    setTimeout(updateDoodleBugsTheme, 500);
    setTimeout(updateDoodleBugsTheme, 2000);
});
