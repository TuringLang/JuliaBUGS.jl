(function () {
    function updateDoodleBugsTheme() {
        var isDark = document.documentElement.classList.contains('dark');
        var targetMode = isDark ? 'dark' : 'light';
        document.querySelectorAll('doodle-bugs').forEach(function (widget) {
            widget.setAttribute('theme-mode', targetMode);
            if ('themeMode' in widget) widget.themeMode = targetMode;
        });
    }

    // VitePress toggles the `dark` class on <html> for dark mode
    new MutationObserver(function () {
        updateDoodleBugsTheme();
    }).observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', updateDoodleBugsTheme);
    } else {
        updateDoodleBugsTheme();
    }
})();
