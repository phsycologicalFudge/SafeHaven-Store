import { escapeHtml, SELF_PACKAGE_NAME, selfApp, selfDownloadUrl } from "../lib/shared.ts";

const SELF_APP_URL = `/app/${SELF_PACKAGE_NAME}`;

export const headerHtml = (index) => {
  const categories = (index && index.categories) || {};
  const categoryEntries = Object.entries(categories);

  const categoryOptions = categoryEntries
    .map(([k, v]) => `<option value="${escapeHtml(k)}">${escapeHtml(v)}</option>`)
    .join("");

  const categoryMenuLinks = categoryEntries
    .map(([k, v]) => `<a class="menu-cat-link" href="/?cat=${encodeURIComponent(k)}" data-cat="${escapeHtml(k)}">${escapeHtml(v)}</a>`)
    .join("");

  const self = selfApp(index);
  const selfIconUrl = (self?.iconUrl || "").trim();
  const downloadUrl = selfDownloadUrl(index) || SELF_APP_URL;

  const downloadIcon = selfIconUrl
    ? `<img src="${escapeHtml(selfIconUrl)}" alt="SafeHaven" />`
    : `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <path d="M12 3v12m0 0l-4-4m4 4l4-4M4 19h16"></path>
      </svg>`;

  return `<header>
  <div class="top-banner">
    <div class="top-banner-side top-banner-left">
      <button class="menu-toggle" id="menuToggle" aria-label="Browse categories">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <path d="M4 6h16M4 12h16M4 18h16"></path>
        </svg>
      </button>
    </div>
    <a class="top-banner-brand" href="/">
      <div class="top-banner-title">SafeHaven</div>
      <div class="top-banner-subtitle">store</div>
    </a>
    <div class="top-banner-side top-banner-right">
      <button class="search-toggle" id="searchToggle" aria-label="Search">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <circle cx="11" cy="11" r="7"></circle>
          <path d="M21 21l-4.35-4.35"></path>
        </svg>
      </button>
      <button class="theme-toggle" id="themeToggle" aria-label="Toggle theme">
        <svg id="themeIconSun" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <circle cx="12" cy="12" r="4"></circle>
          <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"></path>
        </svg>
        <svg id="themeIconMoon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="display:none">
          <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path>
        </svg>
      </button>
    </div>
    <div class="search-overlay" id="searchOverlay">
      <button class="search-close" id="searchClose" aria-label="Close search">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <path d="M18 6L6 18M6 6l12 12"></path>
        </svg>
      </button>
      <input type="text" id="searchInput" placeholder="Search apps..." autocomplete="off" />
      <button class="search-filter-btn" id="filterToggle" aria-label="Filters">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M4 6h16M6 12h12M8 18h8"></path>
        </svg>
      </button>
    </div>
  </div>
  <div class="filter-dropdown" id="filterDropdown">
    <label for="filterCategory">Category</label>
    <select id="filterCategory">
      <option value="">All</option>
      ${categoryOptions}
    </select>
    <label for="filterRating">Min rating</label>
    <select id="filterRating">
      <option value="0">Any</option>
      <option value="3">3+ &#9733;</option>
      <option value="4">4+ &#9733;</option>
      <option value="5">5 &#9733;</option>
    </select>
  </div>
</header>
<div class="menu-overlay" id="menuOverlay">
  <div class="menu-panel" id="menuPanel">
    <div class="menu-panel-header">
      <a class="menu-panel-brand" href="/">
        <div class="top-banner-title">SafeHaven</div>
        <div class="top-banner-subtitle">store</div>
      </a>
      <button class="menu-close" id="menuClose" aria-label="Close menu">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <path d="M18 6L6 18M6 6l12 12"></path>
        </svg>
      </button>
    </div>
    <nav class="menu-nav">
      <a class="menu-tile menu-home-link" href="/">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <path d="M4 11l8-7 8 7M6 10v9h5v-5h2v5h5v-9"></path>
        </svg>
        <span>Home</span>
      </a>
      <div class="menu-tile menu-categories-block">
        <button class="menu-categories-toggle" id="menuCategoriesToggle" aria-expanded="true" aria-controls="menuCategoriesList">
          <span>Categories</span>
          <svg class="menu-categories-chevron" id="menuCategoriesChevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
            <path d="M6 9l6 6 6-6"></path>
          </svg>
        </button>
        <div class="menu-categories-list" id="menuCategoriesList">
          ${categoryMenuLinks}
        </div>
      </div>
    </nav>
    <a class="menu-download-card" href="${escapeHtml(downloadUrl)}">
      <div class="menu-download-icon">
        ${downloadIcon}
      </div>
      <div class="menu-download-info">
        <div class="menu-download-title">SafeHaven App</div>
        <div class="menu-download-sub">A secure store, for you</div>
      </div>
      <span class="menu-download-btn">Get</span>
    </a>
  </div>
</div>`;
};

export const themeHeadScript = () => `<script>
(function () {
  try {
    if (localStorage.getItem('theme') === 'dark') {
      document.documentElement.setAttribute('data-theme', 'dark');
    }
  } catch (e) {}
})();
</script>`;

export const themeScript = () => `<script>
(function () {
  window.scrollTo(0, window.scrollY);
  document.documentElement.scrollLeft = 0;
  document.body.scrollLeft = 0;

  document.querySelectorAll('.h-scroll').forEach(function (el) {
    el.scrollLeft = 0;
  });

  var stored = null;
  try {
    stored = localStorage.getItem('theme');
  } catch (e) {}
  applyTheme(stored === 'dark');

  var themeToggle = document.getElementById('themeToggle');
  if (themeToggle) {
    themeToggle.addEventListener('click', function () {
      var nowDark = document.documentElement.getAttribute('data-theme') !== 'dark';
      applyTheme(nowDark);
      try {
        localStorage.setItem('theme', nowDark ? 'dark' : 'light');
      } catch (e) {}
    });
  }

  function applyTheme(dark) {
    if (dark) {
      document.documentElement.setAttribute('data-theme', 'dark');
    } else {
      document.documentElement.removeAttribute('data-theme');
    }
    var sun = document.getElementById('themeIconSun');
    var moon = document.getElementById('themeIconMoon');
    if (sun) sun.style.display = dark ? 'none' : 'block';
    if (moon) moon.style.display = dark ? 'block' : 'none';
  }

  var overlay = document.getElementById('searchOverlay');
  var input = document.getElementById('searchInput');
  var dropdown = document.getElementById('filterDropdown');
  var results = document.getElementById('searchResults');
  var content = document.getElementById('searchContent');
  var catSelect = document.getElementById('filterCategory');
  var ratingSelect = document.getElementById('filterRating');

  var menuToggle = document.getElementById('menuToggle');
  var menuOverlay = document.getElementById('menuOverlay');
  var menuClose = document.getElementById('menuClose');
  if (menuToggle && menuOverlay) {
    menuToggle.addEventListener('click', function () {
      menuOverlay.classList.add('active');
    });
  }
  if (menuClose && menuOverlay) {
    menuClose.addEventListener('click', function () {
      menuOverlay.classList.remove('active');
    });
  }
  if (menuOverlay) {
    menuOverlay.addEventListener('click', function (e) {
      if (e.target === menuOverlay) menuOverlay.classList.remove('active');
    });
  }

  var categoriesToggle = document.getElementById('menuCategoriesToggle');
  var categoriesList = document.getElementById('menuCategoriesList');
  var categoriesChevron = document.getElementById('menuCategoriesChevron');
  if (categoriesToggle && categoriesList) {
    categoriesToggle.addEventListener('click', function () {
      var collapsed = categoriesList.classList.toggle('collapsed');
      categoriesToggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
      if (categoriesChevron) categoriesChevron.classList.toggle('collapsed', collapsed);
    });
  }

  var searchToggle = document.getElementById('searchToggle');
  if (searchToggle && overlay) {
    searchToggle.addEventListener('click', function () {
      overlay.classList.add('active');
      if (input) input.focus();
    });
  }

  var searchClose = document.getElementById('searchClose');
  if (searchClose && overlay) {
    searchClose.addEventListener('click', function () {
      overlay.classList.remove('active');
      if (input) input.value = '';
      if (catSelect) catSelect.value = '';
      if (ratingSelect) ratingSelect.value = '0';
      if (dropdown) dropdown.classList.remove('active');
      hideResults();
    });
  }

  var filterToggle = document.getElementById('filterToggle');
  if (filterToggle && dropdown) {
    filterToggle.addEventListener('click', function (e) {
      e.stopPropagation();
      dropdown.classList.toggle('active');
    });
    document.addEventListener('click', function (e) {
      if (e.target.closest('#filterDropdown') || e.target.closest('#filterToggle')) return;
      dropdown.classList.remove('active');
    });
  }

  var initialParams = new URLSearchParams(window.location.search);
  var initialQuery = initialParams.get('q') || '';
  var initialCat = initialParams.get('cat') || '';
  var initialRating = initialParams.get('rating') || '0';

  if (input && initialQuery) input.value = initialQuery;
  if (catSelect && initialCat) catSelect.value = initialCat;
  if (ratingSelect && initialRating) ratingSelect.value = initialRating;

  if ((initialQuery || initialCat || initialRating !== '0') && overlay) {
    overlay.classList.add('active');
  }

  if (!results) {
    if (input) {
      input.addEventListener('keydown', function (e) {
        if (e.key !== 'Enter') return;
        navigateToSearch();
      });
    }
    if (catSelect) catSelect.addEventListener('change', navigateToSearch);
    if (ratingSelect) ratingSelect.addEventListener('change', navigateToSearch);
    return;
  }

  var timer;
  var lastQuery = '';

  if (input) {
    input.addEventListener('input', function () {
      clearTimeout(timer);
      timer = setTimeout(runSearch, 220);
    });
  }
  if (catSelect) catSelect.addEventListener('change', runSearch);
  if (ratingSelect) ratingSelect.addEventListener('change', runSearch);

  if (initialQuery || initialCat || initialRating !== '0') {
    runSearch();
  }

  function navigateToSearch() {
    var params = new URLSearchParams();
    var q = input ? input.value.trim() : '';
    var cat = catSelect ? catSelect.value : '';
    var rating = ratingSelect ? ratingSelect.value : '0';
    if (q) params.set('q', q);
    if (cat) params.set('cat', cat);
    if (rating !== '0') params.set('rating', rating);
    var query = params.toString();
    window.location.href = query ? '/?' + query : '/';
  }

  function runSearch() {
    var q = input ? input.value.trim() : '';
    var cat = catSelect ? catSelect.value : '';
    var rating = ratingSelect ? ratingSelect.value : '0';

    if (!q && !cat && rating === '0') { hideResults(); return; }

    var url = '/search?q=' + encodeURIComponent(q)
      + '&cat=' + encodeURIComponent(cat)
      + '&rating=' + encodeURIComponent(rating);

    lastQuery = url;
    results.classList.add('active');
    if (content) content.style.display = 'none';

    fetch(url)
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (url !== lastQuery) return;
        renderResults(data.results || []);
      })
      .catch(function () {
        if (url !== lastQuery) return;
        results.innerHTML = '<div class="search-empty">Search unavailable</div>';
      });
  }

  function escapeText(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function fallbackStyle(seed) {
    var palettes = [
      ['#3B71E8', '#D6E4FF'],
      ['#0F766E', '#CCFBF1'],
      ['#7C3AED', '#EDE9FE'],
      ['#DB2777', '#FCE7F3'],
      ['#D97706', '#FEF3C7'],
      ['#059669', '#D1FAE5'],
      ['#DC2626', '#FEE2E2'],
      ['#0284C7', '#E0F2FE']
    ];
    var value = String(seed || '');
    var hash = 0;
    for (var i = 0; i < value.length; i++) {
      hash = (hash * 31 + value.charCodeAt(i)) & 0x7fffffff;
    }
    var palette = palettes[hash % palettes.length];
    return 'background:' + palette[1] + ';color:' + palette[0];
  }

  function renderResults(list) {
    if (!list.length) {
      results.innerHTML = '<div class="search-empty">No apps found</div>';
      return;
    }
    var html = '';
    for (var i = 0; i < list.length; i++) {
      var a = list[i];
      var icon = a.i
        ? '<img class="app-icon" src="' + escapeText(a.i) + '" alt="" loading="lazy" />'
        : '<div class="app-icon-fallback" style="' + fallbackStyle(a.p) + '">' + escapeText((a.n || '?').charAt(0).toUpperCase()) + '</div>';
      html += '<a class="app-row" href="/app/' + encodeURIComponent(a.p) + '">'
        + icon
        + '<div class="app-row-info"><div class="app-row-name">' + escapeText(a.n) + '</div>'
        + (a.r ? '<div class="app-row-sub">' + escapeText(a.r) + ' \u2605</div>' : '')
        + '</div></a>';
    }
    results.innerHTML = html;
  }

  function hideResults() {
    lastQuery = '';
    if (results) {
      results.classList.remove('active');
      results.innerHTML = '';
    }
    if (content) content.style.display = '';
  }
})();
</script>`;
