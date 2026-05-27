---
title: "Batters Leaderboard"
---

<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css">
<style>
.dataTables_wrapper { overflow-x: auto; }
.tab-buttons { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; flex-wrap: wrap; }
.tab-btn {
  padding: 6px 18px; cursor: pointer; border: 1px solid #888;
  border-radius: 4px; background: transparent; color: inherit; font-size: 0.95rem;
}
.tab-btn.active { background: #555; color: #fff; border-color: #555; }
.tab-content { display: none; }
.tab-content.active { display: block; }
.filter-row { display: flex; gap: 2rem; align-items: center; flex-wrap: wrap; margin-bottom: 1rem; }
.col-btn {
  padding: 4px 12px; cursor: pointer; border: 1px solid #888;
  border-radius: 4px; background: transparent; color: inherit; font-size: 0.85rem;
}
.col-btn.active { background: #555; color: #fff; border-color: #555; }
</style>

<div class="tab-buttons">
  <button class="tab-btn active" onclick="switchTab('opponent', event)">Opponent Pitch Model</button>
  <button class="tab-btn" onclick="switchTab('xwoba', event)">xwOBA</button>
</div>

<!-- Opponent Pitch Model タブ -->
<div id="tab-opponent" class="tab-content active">
  <div class="filter-row">
    <div>
      <label for="oppYearFilter">シーズン：</label>
      <select id="oppYearFilter">
        <option value="">All</option>
        <option value="2021">2021</option>
        <option value="2022">2022</option>
        <option value="2023">2023</option>
        <option value="2024">2024</option>
        <option value="2025">2025</option>
      </select>
    </div>
    <div>
      <label for="oppMinPitches">最小Pitches数：<span id="oppMinPitchesVal">500</span></label><br>
      <input type="range" id="oppMinPitches" min="1" max="3000" value="500" step="50" style="width:200px;">
    </div>
  </div>
  <table id="batterTable" class="display" style="width:100%">
    <thead>
      <tr>
        <th>Name</th><th>Year</th><th>Pitches</th>
        <th>Opponent Stuff RV/70</th><th>Opponent Pitch RV/150</th><th>wOBA</th>
      </tr>
    </thead>
  </table>
</div>

<!-- xwOBA タブ -->
<div id="tab-xwoba" class="tab-content">
  <div class="filter-row">
    <div>
      <label for="xwobaYearFilter">シーズン：</label>
      <select id="xwobaYearFilter">
        <option value="">All</option>
        <option value="2021">2021</option>
        <option value="2022">2022</option>
        <option value="2023">2023</option>
        <option value="2024">2024</option>
        <option value="2025">2025</option>
      </select>
    </div>
    <div>
      <label for="xwobaMinPA">最小PA数：<span id="xwobaMinPAVal">300</span></label><br>
      <input type="range" id="xwobaMinPA" min="1" max="700" value="300" step="10" style="width:200px;">
    </div>
    <div>
      <span>表示列：</span>
      <button class="col-btn active" onclick="setColGroup('woba', event)">wOBA系</button>
      <button class="col-btn" onclick="setColGroup('wobacon', event)">wOBAcon系</button>
      <button class="col-btn" onclick="setColGroup('both', event)">両方</button>
    </div>
  </div>
  <table id="xwobaBatTable" class="display" style="width:100%">
    <thead>
      <tr>
        <th>Name</th><th>Year</th><th>PA</th>
        <th>wOBA</th>
        <th>xwOBA (ev+la)</th>
        <th>xwOBA (ev+la+sa)</th>
        <th>wOBA-xwOBA (2p)</th>
        <th>wOBA-xwOBA (3p)</th>
        <th>xwOBA (3p-2p)</th>
        <th>wOBAcon</th>
        <th>xwOBAcon (ev+la)</th>
        <th>xwOBAcon (ev+la+sa)</th>
        <th>wOBAcon-xwOBAcon (2p)</th>
        <th>wOBAcon-xwOBAcon (3p)</th>
        <th>xwOBAcon (3p-2p)</th>
      </tr>
    </thead>
  </table>
</div>

<script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/PapaParse/5.4.1/papaparse.min.js"></script>
<script>
var playersMap = {};
var oppData = [];
var xwobaBatData = [];
var loadedCount = 0;
var dtBatter = null;
var dtXwobaBat = null;

// wOBA系: col index 3-8, wOBAcon系: 9-14
var colGroups = {
  woba:    [3,4,5,6,7,8],
  wobacon: [9,10,11,12,13,14],
  both:    [3,4,5,6,7,8,9,10,11,12,13,14]
};

function tryRender() {
  if (loadedCount < 3) return;

  [oppData, xwobaBatData].forEach(function(arr) {
    arr.forEach(function(r) {
      var id = String(r.batter_id);
      r.name = playersMap[id] || id;
    });
  });

  // Opponent Pitch Model
  dtBatter = $("#batterTable").DataTable({
    data: oppData.filter(r => r.pitches >= 500),
    columns: [
      { data: "name" },
      { data: "year" },
      { data: "pitches" },
      { data: "stuff_rv_70",  render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "pitch_rv_150", render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "woba_fg",      render: d => d != null ? (+d).toFixed(3) : "-" }
    ],
    order: [[3, "desc"]],
    pageLength: 25
  });

  // xwOBA
  dtXwobaBat = $("#xwobaBatTable").DataTable({
    data: xwobaBatData.filter(r => r.pa >= 300),
    columns: [
      { data: "name" },
      { data: "year" },
      { data: "pa" },
      { data: "woba",                        render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwoba_ev_la",                 render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwoba_ev_la_sa",              render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "woba_minus_xwoba_2p",         render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "woba_minus_xwoba_3p",         render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwoba_3p_minus_xwoba_2p",     render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "wobacon",                     render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwobacon_ev_la",              render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwobacon_ev_la_sa",           render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "wobacon_minus_xwobacon_2p",   render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "wobacon_minus_xwobacon_3p",   render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwobacon_3p_minus_xwobacon_2p", render: d => d != null ? (+d).toFixed(3) : "-" }
    ],
    order: [[3, "desc"]],
    pageLength: 25,
    columnDefs: [
      { targets: [9,10,11,12,13,14], visible: false }
    ]
  });

  $("#oppYearFilter").on("change", function() { applyOppFilter(); });
  $("#oppMinPitches").on("input", function() {
    $("#oppMinPitchesVal").text($(this).val());
    applyOppFilter();
  });
  $("#xwobaYearFilter").on("change", function() { applyXwobaFilter(); });
  $("#xwobaMinPA").on("input", function() {
    $("#xwobaMinPAVal").text($(this).val());
    applyXwobaFilter();
  });
}

function applyOppFilter() {
  var yr   = $("#oppYearFilter").val();
  var minN = parseInt($("#oppMinPitches").val());
  $.fn.dataTable.ext.search = [];
  $.fn.dataTable.ext.search.push(function(settings, data, dataIndex, rowData) {
    if (settings.nTable.id !== "batterTable") return true;
    if (yr && String(rowData.year) !== yr) return false;
    if (rowData.pitches < minN) return false;
    return true;
  });
  dtBatter.draw();
}

function applyXwobaFilter() {
  var yr   = $("#xwobaYearFilter").val();
  var minN = parseInt($("#xwobaMinPA").val());
  $.fn.dataTable.ext.search = [];
  $.fn.dataTable.ext.search.push(function(settings, data, dataIndex, rowData) {
    if (settings.nTable.id !== "xwobaBatTable") return true;
    if (yr && String(rowData.year) !== yr) return false;
    if (rowData.pa < minN) return false;
    return true;
  });
  dtXwobaBat.draw();
}

function setColGroup(group, e) {
  document.querySelectorAll(".col-btn").forEach(el => el.classList.remove("active"));
  e.target.classList.add("active");
  var allCols = [3,4,5,6,7,8,9,10,11,12,13,14];
  var show = colGroups[group];
  allCols.forEach(function(i) {
    dtXwobaBat.column(i).visible(show.includes(i));
  });
}

function switchTab(name, e) {
  document.querySelectorAll(".tab-content").forEach(el => el.classList.remove("active"));
  document.querySelectorAll(".tab-btn").forEach(el => el.classList.remove("active"));
  document.getElementById("tab-" + name).classList.add("active");
  e.target.classList.add("active");
  if (name === "opponent" && dtBatter) dtBatter.columns.adjust().draw();
  if (name === "xwoba" && dtXwobaBat) dtXwobaBat.columns.adjust().draw();
}

Papa.parse("/solving-baseball/data/players.csv", {
  download: true, header: true,
  complete: function(results) {
    results.data.forEach(r => { if (r.MLBAMID) playersMap[String(r.MLBAMID)] = r.Name; });
    loadedCount++; tryRender();
  }
});

Papa.parse("/solving-baseball/data/leaderboards/opponent_pitch_model_gbdt_2021_2025.csv", {
  download: true, header: true, dynamicTyping: true,
  complete: function(results) {
    oppData = results.data.filter(r => r.batter_id);
    loadedCount++; tryRender();
  }
});

Papa.parse("/solving-baseball/data/leaderboards/xwoba_bat_2021_2025.csv", {
  download: true, header: true, dynamicTyping: true,
  complete: function(results) {
    xwobaBatData = results.data.filter(r => r.batter_id);
    loadedCount++; tryRender();
  }
});
</script>