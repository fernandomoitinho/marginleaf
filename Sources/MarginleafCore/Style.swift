/// Reading styles for the preview. System fonts, a ~68-character column,
/// light and dark through `prefers-color-scheme`.
public enum Style {
    public static let css = """
    :root {
      color-scheme: light dark;
      --bg: #ffffff;
      --fg: #1d1d1f;
      --muted: #6e6e73;
      --rule: #e3e3e8;
      --code-bg: #f4f4f6;
      --accent: #0a62c9;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #1e1e20;
        --fg: #ececee;
        --muted: #9a9aa2;
        --rule: #38383d;
        --code-bg: #2a2a2e;
        --accent: #6cb2ff;
      }
    }
    html { background: var(--bg); }
    body {
      margin: 0;
      color: var(--fg);
      font: 17px/1.65 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      overflow-wrap: break-word;
    }
    article { max-width: 1240px; margin: 0 auto; padding: 56px 40px 120px; }
    /* Prose keeps a comfortable line length; tables, code and images use the full width. */
    article > :not(table):not(pre):not(img):not(hr):not(.footnotes) { max-width: 78ch; }
    article > table { width: max-content; min-width: 50%; max-width: 100%; }

    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.8em 0 0.5em; font-weight: 650; letter-spacing: -0.012em; }
    h1 { font-size: 2.05em; font-weight: 700; letter-spacing: -0.022em; line-height: 1.15; margin-top: 0.4em; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.2em; }
    h4 { font-size: 1em; }
    h5 { font-size: 0.95em; }
    h6 { font-size: 0.9em; color: var(--muted); }
    article > :first-child { margin-top: 0; }

    p { margin: 0.9em 0; }
    a { color: var(--accent); text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 3px; }
    strong { font-weight: 650; }

    ul, ol { padding-left: 1.5em; margin: 0.9em 0; }
    li { margin: 0.28em 0; }
    li > ul, li > ol { margin: 0.25em 0; }
    li:has(> input[type=checkbox]) { list-style: none; margin-left: -1.5em; }
    input[type=checkbox] { margin: 0 0.55em 0 0; transform: translateY(1px); }

    code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; }
    mark.fc { background: rgba(255, 204, 0, 0.38); color: inherit; border-radius: 3px; cursor: pointer; padding: 0.05em 0; }
    mark.fc:hover { background: rgba(255, 204, 0, 0.58); }
    html.nofc mark.fc { background: none; cursor: text; }
    #fc-add { position: fixed; z-index: 10; display: none; width: 24px; height: 24px; padding: 0; border: 0; border-radius: 7px;
      background: none; color: var(--accent); display: none; align-items: center; justify-content: center;
      cursor: pointer; opacity: 0.7; }
    #fc-add:hover { opacity: 1; background: var(--code-bg); }
    #fc-add svg { display: block; }
    html.nofc #fc-add { display: none !important; }
    @media print { #fc-add { display: none !important; } }
    code { font-size: 0.88em; background: var(--code-bg); padding: 0.15em 0.4em; border-radius: 5px; }
    pre { background: var(--code-bg); padding: 16px 18px; border-radius: 10px; overflow-x: auto; line-height: 1.5; margin: 1.2em 0; }
    pre code { background: none; padding: 0; font-size: 0.86em; border-radius: 0; }

    blockquote { margin: 1.2em 0; padding: 0 0 0 1.1em; border-left: 3px solid var(--rule); color: var(--muted); }
    blockquote > :first-child { margin-top: 0; }
    blockquote > :last-child { margin-bottom: 0; }

    hr { border: 0; border-top: 1px solid var(--rule); margin: 2.4em 0; }

    table { border-collapse: collapse; margin: 1.2em 0; display: block; overflow-x: auto; }
    th, td { padding: 0.5em 0.9em; border-bottom: 1px solid var(--rule); text-align: left; vertical-align: top; }
    th { font-weight: 650; border-bottom-width: 2px; }

    img { max-width: 100%; height: auto; border-radius: 6px; }
    del { color: var(--muted); }

    sup a { text-decoration: none; }
    .footnotes { margin-top: 3em; padding-top: 1em; border-top: 1px solid var(--rule); font-size: 0.88em; color: var(--muted); }
    .footnotes ol { padding-left: 1.2em; }
    """
}
