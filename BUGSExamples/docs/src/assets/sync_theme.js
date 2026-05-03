document.addEventListener("DOMContentLoaded", function() {
    const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
            if (mutation.attributeName === "data-theme") {
                updateDoodleBugsTheme();
            }
        });
    });
    
    observer.observe(document.documentElement, {
        attributes: true
    });
    
    function updateDoodleBugsTheme() {
        const theme = document.documentElement.getAttribute("data-theme") || "light";
        const isDark = theme.includes("dark");
        document.querySelectorAll("doodle-bugs").forEach(function(widget) {
            widget.setAttribute("theme-mode", isDark ? "dark" : "light");
        });
    }
    
    // Initial sync
    setTimeout(updateDoodleBugsTheme, 500);
});
