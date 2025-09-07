// Populate the sidebar
//
// This is a script, and not included directly in the page, to control the total size of the book.
// The TOC contains an entry for each page, so if each page includes a copy of the TOC,
// the total size of the page becomes O(n**2).
class MDBookSidebarScrollbox extends HTMLElement {
    constructor() {
        super();
    }
    connectedCallback() {
        this.innerHTML = '<ol class="chapter"><li class="chapter-item expanded "><a href="welcome.html"><strong aria-hidden="true">1.</strong> Welcome to robotnix</a></li><li class="chapter-item expanded "><a href="configuration.html"><strong aria-hidden="true">2.</strong> Configuration</a></li><li><ol class="section"><li class="chapter-item expanded "><a href="modules/flavors.html"><strong aria-hidden="true">2.1.</strong> Flavors</a></li><li class="chapter-item expanded "><a href="modules/f-droid.html"><strong aria-hidden="true">2.2.</strong> F-Droid</a></li><li class="chapter-item expanded "><a href="modules/seedvault.html"><strong aria-hidden="true">2.3.</strong> Seedvault Backup</a></li><li class="chapter-item expanded "><a href="modules/microg.html"><strong aria-hidden="true">2.4.</strong> MicroG</a></li><li class="chapter-item expanded "><a href="modules/ota.html"><strong aria-hidden="true">2.5.</strong> Over-the-Air (OTA) Updater</a></li><li class="chapter-item expanded "><a href="modules/browsers.html"><strong aria-hidden="true">2.6.</strong> Browsers / Webview</a></li><li class="chapter-item expanded "><a href="modules/attestation.html"><strong aria-hidden="true">2.7.</strong> Remote Attestation</a></li><li class="chapter-item expanded "><a href="modules/prebuilt.html"><strong aria-hidden="true">2.8.</strong> Prebuilt Apps</a></li><li class="chapter-item expanded "><a href="modules/source.html"><strong aria-hidden="true">2.9.</strong> Source Directories</a></li><li class="chapter-item expanded "><a href="modules/other.html"><strong aria-hidden="true">2.10.</strong> Other Modules</a></li></ol></li><li class="chapter-item expanded "><a href="building.html"><strong aria-hidden="true">3.</strong> Building</a></li><li class="chapter-item expanded "><a href="installation.html"><strong aria-hidden="true">4.</strong> Installation / Updating</a></li><li class="chapter-item expanded "><a href="development.html"><strong aria-hidden="true">5.</strong> Development</a></li><li class="chapter-item expanded "><div><strong aria-hidden="true">6.</strong> Reference</div></li><li><ol class="section"><li class="chapter-item expanded "><a href="options.html"><strong aria-hidden="true">6.1.</strong> Options</a></li></ol></li></ol>';
        // Set the current, active page, and reveal it if it's hidden
        let current_page = document.location.href.toString().split("#")[0].split("?")[0];
        if (current_page.endsWith("/")) {
            current_page += "index.html";
        }
        var links = Array.prototype.slice.call(this.querySelectorAll("a"));
        var l = links.length;
        for (var i = 0; i < l; ++i) {
            var link = links[i];
            var href = link.getAttribute("href");
            if (href && !href.startsWith("#") && !/^(?:[a-z+]+:)?\/\//.test(href)) {
                link.href = path_to_root + href;
            }
            // The "index" page is supposed to alias the first chapter in the book.
            if (link.href === current_page || (i === 0 && path_to_root === "" && current_page.endsWith("/index.html"))) {
                link.classList.add("active");
                var parent = link.parentElement;
                if (parent && parent.classList.contains("chapter-item")) {
                    parent.classList.add("expanded");
                }
                while (parent) {
                    if (parent.tagName === "LI" && parent.previousElementSibling) {
                        if (parent.previousElementSibling.classList.contains("chapter-item")) {
                            parent.previousElementSibling.classList.add("expanded");
                        }
                    }
                    parent = parent.parentElement;
                }
            }
        }
        // Track and set sidebar scroll position
        this.addEventListener('click', function(e) {
            if (e.target.tagName === 'A') {
                sessionStorage.setItem('sidebar-scroll', this.scrollTop);
            }
        }, { passive: true });
        var sidebarScrollTop = sessionStorage.getItem('sidebar-scroll');
        sessionStorage.removeItem('sidebar-scroll');
        if (sidebarScrollTop) {
            // preserve sidebar scroll position when navigating via links within sidebar
            this.scrollTop = sidebarScrollTop;
        } else {
            // scroll sidebar to current active section when navigating via "next/previous chapter" buttons
            var activeSection = document.querySelector('#sidebar .active');
            if (activeSection) {
                activeSection.scrollIntoView({ block: 'center' });
            }
        }
        // Toggle buttons
        var sidebarAnchorToggles = document.querySelectorAll('#sidebar a.toggle');
        function toggleSection(ev) {
            ev.currentTarget.parentElement.classList.toggle('expanded');
        }
        Array.from(sidebarAnchorToggles).forEach(function (el) {
            el.addEventListener('click', toggleSection);
        });
    }
}
window.customElements.define("mdbook-sidebar-scrollbox", MDBookSidebarScrollbox);
