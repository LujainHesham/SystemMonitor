# System Monitor: Report Design & QR Code Implementation Detailed Explanation

This document focuses specifically on the **HTML Report Generation**, **Cyberpunk Design**, and **QR Code/PDF** features of the `monitor.sh` script. Use this for your group discussion to explain *how* the interface is built and how mobile access works.

## 1. The Core Strategy: "Heredocs"
**Concept**: Since `monitor.sh` is a single Bash script, it cannot easily rely on external `.html` or `.css` files being present everywhere (especially in Docker or ephemeral containers).
**Solution**: We use **Heredocs** (`<<'EOF'`) to embed the entire HTML, CSS, and JavaScript code *inside* the Bash script. When the script runs, it "echoes" this code into a real file.

*   **Reference in Code**:
    *   **CSS**: Line `965` (`cat > ... <<'CSS'`)
    *   **JS**: Line `1109` (`cat > ... <<'JS'`)
    *   **HTML**: Line `1141` (`cat > ... <<EOF`)

---

## 2. Cyberpunk Design (CSS) Breakdown
The design uses a "High-Contrast Neon" aesthetic inspired by Cyberpunk.

### 2.1 Color Palette
We used specific hex codes to match the theme:
*   **#000000 (Black)**: Background (void).
*   **#00FFFF (Cyan)**: Primary borders and main text (glow).
*   **#FF00FF (Magenta)**: Titles and active highlights.
*   **#FFFF00 (Yellow)**: Buttons and warnings.
*   **#00FF41 (Green)**: Data output (Matrix style).

### 2.2 Key CSS Features
*   **Glowing Borders**:
    ```css
    box-shadow: 0 0 20px #00FFFF;
    ```
    This creates the "neon light" effect around boxes.

*   **Glitch Animation** (Line `1100`):
    We defined a `@keyframes glitch` animation that rapidly shifts the text shadow (Red/Blue/Green) to create a jittery, holographic effect on the main title.

*   **Grid Layout**:
    The stats (Uptime, Host, etc.) use `display: grid` with `repeat(auto-fit, ...)` to automatically stack cards nicely on mobile screens.

---

## 3. Interactive Tabs (JavaScript)
**Goal**: The report has too much data to show at once. We used a "Tab" system.

*   **Logic (Line `1115`)**:
    1.  **Hide All**: `contents.forEach(c => c.style.display = 'none')`
    2.  **Show Target**: `document.getElementById(tabName).style.display = 'block'`
    3.  **Highlight Button**: Add `.active` class to the clicked button.
*   **Auto-Open**: The script automatically clicks the first tab ("QR & PDF") when the page loads so it's not empty.

---

## 4. PDF Generation Logic
**Function**: `generate_html_report` (Line `1245`)

We use a tool called **wkhtmltopdf** (Webkit HTML to PDF).
*   **Command**:
    ```bash
    wkhtmltopdf "$html_file" "$pdf_file"
    ```
*   **Concept**: This tool runs a headless browser, renders our Cyberpunk HTML path, and "prints" it to a PDF file. This is crucial for saving a snapshot of the system state.

---

## 5. QR Code & Mobile Access
**Goal**: Allow a user to scan their screen and walk away with the report on their phone.

### 5.1 QR Generation (Line `1261`)
*   **Tool**: `qrencode`
*   **Command**:
    ```bash
    qrencode -o "$qr_file" -s 6 -m 2 "$pdf_url"
    ```
    *   `-o`: Output filename (PNG image).
    *   `-s 6`: Size (scale) of the pixels (dots).
    *   `-m 2`: Margin (white space) around the code.
    *   `$pdf_url`: The data encoded (e.g., `http://192.168.1.5:8088/system_report.pdf`).

### 5.2 Dynamic Injection (Line `1267` - `sed`)
This is the trickiest part. We generate the HTML *first* with placeholder text `(generating...)` because we haven't made the PDF/QR yet.
**After** the QR code is made, we use `sed` (Stream Editor) to **inject** it back into the HTML file:
```bash
sed -i "s|(generating...)|<a href=\"${pdf_url}\">...|" "$html_file"
sed -i "s|src=\"\"|src=\"${qr_rel}\"|" "$html_file"
```
*   **Why?**: This prevents a "chicken and egg" problem where the HTML needs the QR image, but the QR image needs to know where the HTML/PDF will live.

---

## 6. Code References for Group Discussion

| Feature | Line Range (`monitor.sh`) | Explanation Point |
| :--- | :--- | :--- |
| **CSS Stylesheet** | `965` - `1106` | Show the `box-shadow` and colors. |
| **Glitch Animation** | `1100` - `1105` | "This is how we animate the text." |
| **JavaScript Tabs** | `1109` - `1139` | "Simple function to hide/show divs." |
| **HTML Structure** | `1141` - `1239` | "The skeleton of our report." |
| **PDF Command** | `1246` | `wkhtmltopdf` usage. |
| **QR Command** | `1262` | `qrencode` usage. |

---

## 7. Full Design Code Implementation

Here is the complete code used to generate the report design. You can include this in your project documentation under "Frontend Implementation".

### A. The CSS Generator (Cyberpunk Theme)
```bash
    # Cyberpunk Neon CSS
    cat > "${REPORT_DIR}/assets/style.css" <<'CSS'
body {
    background: #000000;
    color: #00FFFF;
    font-family: 'Courier New', monospace;
    margin: 0;
    padding: 0;
}
.container { max-width: 1200px; margin: 20px auto; padding: 20px; }
.header {
    background: #111;
    border: 2px solid #00FFFF;
    box-shadow: 0 0 20px #00FFFF;
    padding: 15px;
    margin-bottom: 30px;
    text-align: center;
}
.title {
    font-size: 2.2em;
    color: #FF00FF;
    text-shadow: 0 0 15px #FF00FF, 0 0 30px #FF00FF;
    animation: glitch 3s infinite;
    letter-spacing: 3px;
}
.controls { margin: 15px 0; display: flex; justify-content: center; gap: 15px; flex-wrap: wrap; }
.btn {
    background: #000;
    color: #FFFF00;
    border: 2px solid #00FFFF;
    padding: 10px 20px;
    border-radius: 6px;
    cursor: pointer;
    font-weight: bold;
    box-shadow: 0 0 10px #00FFFF;
    text-decoration: none;
    display: inline-block;
}
.btn:hover { background: #00FFFF; color: #000; box-shadow: 0 0 20px #00FFFF; }
.stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 10px;
    margin: 20px 0;
    color: #00FF41;
}
.stat {
    background: #111;
    border: 1px solid #00FFFF;
    padding: 12px;
    border-radius: 8px;
    text-align: center;
    box-shadow: 0 0 10px #00FFFF30;
}

/* Tabs */
.tab {
    overflow: hidden;
    border: 2px solid #00FFFF;
    background: #111;
    margin-bottom: 20px;
    box-shadow: 0 0 15px #00FFFF;
}
.tab button {
    background: #000;
    color: #FFFF00;
    float: left;
    border: none;
    outline: none;
    cursor: pointer;
    padding: 14px 20px;
    font-size: 1.1em;
    font-weight: bold;
}
.tab button:hover { background: #FF00FF; color: #000; }
.tab button.active { background: #00FFFF; color: #000; }

/* Tab content */
.tabcontent {
    display: none;
    padding: 30px;
    background: #111;
    border: 2px solid #00FFFF;
    border-top: none;
    min-height: 400px;
}
.tabcontent h2 {
    color: #FF00FF;
    text-shadow: 0 0 10px #FF00FF;
    margin-top: 0;
}
pre {
    background: #000;
    color: #00FF41;
    padding: 20px;
    border: 1px solid #00FFFF;
    border-radius: 8px;
    overflow-x: auto;
    box-shadow: inset 0 0 15px #00FFFF30;
    font-size: 0.95em;
}
.footer {
    margin: 50px 0 30px;
    text-align: center;
    color: #FF0055;
    font-size: 1em;
}
.qr {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 12px 16px;
    justify-content: center;
}
.qr img {
    border: 2px solid #00FFFF;
    border-radius: 8px;
    background: #000;
    box-shadow: 0 0 15px #00FFFF;
}
.qr-info {
    color: #00FF41;
}
.qr-info strong {
    color: #FFFF00;
}
.qr-info a {
    color: #FF00FF;
    text-decoration: none;
    font-weight: bold;
}
.qr-info a:hover {
    text-shadow: 0 0 10px #FF00FF;
}

/* Glitch animation */
@keyframes glitch {
    0% { text-shadow: 0 0 10px #FF00FF; }
    20% { text-shadow: 5px 0 15px #00FFFF, -5px 0 15px #FF0055; }
    40% { text-shadow: -5px 0 20px #FFFF00, 5px 0 20px #00FF41; }
    100% { text-shadow: 0 0 10px #FF00FF; }
}
CSS
```

### B. The JavaScript Logic (Tabs)
```javascript
    # Cyberpunk Neon JavaScript with Tab Functionality
    cat > "${REPORT_DIR}/assets/report.js" <<'JS'
(function(){
  // Tab switching logic
  const tabs = document.querySelectorAll('.tablinks');
  const contents = document.querySelectorAll('.tabcontent');
  
  function openTab(tabName) {
    contents.forEach(c => c.style.display = 'none');
    tabs.forEach(t => t.classList.remove('active'));
    
    const target = document.getElementById(tabName);
    if (target) {
      target.style.display = 'block';
      const btn = document.querySelector(`[data-tab="${tabName}"]`);
      if (btn) btn.classList.add('active');
    }
  }
  
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const tabName = tab.getAttribute('data-tab');
      openTab(tabName);
    });
  });
  
  // Open first tab by default
  if (tabs.length > 0) {
    openTab(tabs[0].getAttribute('data-tab'));
  }
})();
JS
```

### C. The HTML Structure Generator
```bash
    cat > "$html_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>CYBERKONSOLE v2077 // SYSTEM MONITOR</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="assets/style.css">
</head>
<body>
    <div class="header">
        <div class="title">⚡ SYSTEM MONITORING REPORT ⚡</div>
        <div class="stats">
            <div class="stat"><strong>SYSTEM:</strong> $(uname -srmo)</div>
            <div class="stat"><strong>HOST:</strong> $(hostname)</div>
            <div class="stat"><strong>UPTIME:</strong> $(uptime -p 2>/dev/null || echo "N/A")</div>
            <div class="stat"><strong>GENERATED:</strong> $(date "+%Y-%m-%d %H:%M:%S")</div>
            <div class="stat"><strong>TEMP CSV:</strong> ${csv_src}</div>
        </div>
        <div class="controls">
            <a class="btn" href="index.html">📊 REPORT INDEX</a>
        </div>
    </div>

    <div class="container">
        <!-- Tabs -->
        <div class="tab">
            <button class="tablinks" data-tab="QR">📱 QR & PDF</button>
            <button class="tablinks" data-tab="CPU">🔥 CPU</button>
            <button class="tablinks" data-tab="Memory">💾 MEMORY</button>
            <button class="tablinks" data-tab="Disk">💿 DISK</button>
            <button class="tablinks" data-tab="SMART">🔍 SMART</button>
            <button class="tablinks" data-tab="Temp">🌡️ TEMPERATURE</button>
            <button class="tablinks" data-tab="Network">🌐 NETWORK</button>
            <button class="tablinks" data-tab="GPU">🎮 GPU</button>
            <button class="tablinks" data-tab="Alerts">⚠️ ALERTS</button>
        </div>

        <div id="QR" class="tabcontent">
            <h2>📱 QR CODE & PDF DOWNLOAD // MOBILE ACCESS</h2>
            <div class="qr">
                <div class="qr-info">
                    <p><strong>PDF REPORT:</strong> <span id="pdfLinkText">(generating...)</span></p>
                    <p style="color: #00FFFF;">💡 Scan the QR code from your phone to open the PDF report</p>
                </div>
                <img id="qrImage" src="" alt="QR code" width="200" height="200" />
            </div>
        </div>

        <div id="CPU" class="tabcontent">
            <h2>🔥 CPU INFORMATION // NEURAL CORE</h2>
            <pre>${cpu_output}</pre>
        </div>

        <!-- Repeated for other sections... -->

        <div class="footer">
            <p>Report generated by <strong>CYBERKONSOLE v2077</strong> 🚀</p>
            <p>Arab Academy for Science, Technology & Maritime Transport</p>
        </div>
    </div>

    <script src="assets/report.js"></script>
</body>
</html>
EOF
```

